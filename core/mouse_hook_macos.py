"""
macOS mouse hook implementation.
"""

import functools
import ctypes
import queue
import sys
import threading
import time

from core.mouse_hook_base import BaseMouseHook, HidGestureListener
from core.mouse_hook_types import MouseEvent, hscroll_event_type

try:
    import objc
except ImportError as exc:
    raise ImportError(
        "PyObjC is required on macOS. Run "
        "`python -m pip install -r requirements.txt`."
    ) from exc

try:
    import Quartz

    _QUARTZ_OK = True
except ImportError:
    _QUARTZ_OK = False
    print(
        "[MouseHook] pyobjc-framework-Quartz not installed — "
        "pip install pyobjc-framework-Quartz"
    )


def _autoreleased(fn):
    @functools.wraps(fn)
    def wrapper(*args, **kwargs):
        with objc.autorelease_pool():
            return fn(*args, **kwargs)
    return wrapper


_BTN_MIDDLE = 2
_BTN_BACK = 3
_BTN_FORWARD = 4
# Quartz other-button number -> per-button slide-gesture owner name (the config
# button keys back/forward/middle map to).
_BTN_TO_GESTURE_OWNER = {
    _BTN_MIDDLE: "middle",
    _BTN_BACK: "xbutton1",
    _BTN_FORWARD: "xbutton2",
}
_SCROLL_INVERT_MARKER = 0x4D4F5553
_INJECTED_EVENT_MARKER = 0x4D4F5554
_SHIFT_WHEEL_HSCROLL_MARKER = 0x4D4F5556
_kCGEventTapDisabledByTimeout = 0xFFFFFFFE
_kCGEventTapDisabledByUserInput = 0xFFFFFFFF


@functools.lru_cache(maxsize=1)
def _console_lock_iokit_bindings():
    """Return the small IOKit/CoreFoundation surface used for lock polling."""
    iokit = ctypes.CDLL(
        "/System/Library/Frameworks/IOKit.framework/IOKit"
    )
    core_foundation = ctypes.CDLL(
        "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation"
    )

    iokit.IORegistryGetRootEntry.argtypes = [ctypes.c_uint]
    iokit.IORegistryGetRootEntry.restype = ctypes.c_uint
    iokit.IORegistryEntryCreateCFProperty.argtypes = [
        ctypes.c_uint,
        ctypes.c_void_p,
        ctypes.c_void_p,
        ctypes.c_uint,
    ]
    iokit.IORegistryEntryCreateCFProperty.restype = ctypes.c_void_p
    iokit.IOObjectRelease.argtypes = [ctypes.c_uint]
    iokit.IOObjectRelease.restype = ctypes.c_int

    core_foundation.CFStringCreateWithCString.argtypes = [
        ctypes.c_void_p,
        ctypes.c_char_p,
        ctypes.c_uint32,
    ]
    core_foundation.CFStringCreateWithCString.restype = ctypes.c_void_p
    core_foundation.CFBooleanGetTypeID.argtypes = []
    core_foundation.CFBooleanGetTypeID.restype = ctypes.c_ulong
    core_foundation.CFGetTypeID.argtypes = [ctypes.c_void_p]
    core_foundation.CFGetTypeID.restype = ctypes.c_ulong
    core_foundation.CFBooleanGetValue.argtypes = [ctypes.c_void_p]
    core_foundation.CFBooleanGetValue.restype = ctypes.c_bool
    core_foundation.CFRelease.argtypes = [ctypes.c_void_p]

    # kCFStringEncodingUTF8. The cached key is intentionally retained for the
    # process lifetime together with the cached function bindings.
    key = core_foundation.CFStringCreateWithCString(
        None, b"IOConsoleLocked", 0x08000100
    )
    if not key:
        raise RuntimeError("could not create IOConsoleLocked key")
    return iokit, core_foundation, key


def _read_console_locked():
    """Read the kernel's current console lock state, or None if unavailable."""
    root = 0
    value = None
    try:
        iokit, core_foundation, key = _console_lock_iokit_bindings()
        root = iokit.IORegistryGetRootEntry(0)
        if not root:
            return None
        value = iokit.IORegistryEntryCreateCFProperty(root, key, None, 0)
        if not value:
            return None
        if core_foundation.CFGetTypeID(value) != core_foundation.CFBooleanGetTypeID():
            return None
        return bool(core_foundation.CFBooleanGetValue(value))
    except Exception:
        return None
    finally:
        if value:
            core_foundation.CFRelease(value)
        if root:
            iokit.IOObjectRelease(root)


class MouseHook(BaseMouseHook):
    """
    Uses CGEventTap on macOS to intercept mouse button presses and scroll
    events. Requires Accessibility permission.
    """

    def __init__(self):
        super().__init__()
        self._running = False
        self._tap = None
        self._tap_source = None
        self.ignore_trackpad = True
        self._wake_observer = None
        self._session_resign_observer = None
        self._session_activate_observer = None
        self._screen_unlock_observer = None
        self._session_rearm_timers = set()
        self._session_rearm_lock = threading.Lock()
        self._console_lock_stop = threading.Event()
        self._console_lock_thread = None
        self._init_dispatch_queue(maxsize=512)
        self._dispatch_thread = None
        self._first_event_logged = False

    def _negate_scroll_axis(self, cg_event, axis):
        for field_name in (
            f"kCGScrollWheelEventDeltaAxis{axis}",
            f"kCGScrollWheelEventFixedPtDeltaAxis{axis}",
            f"kCGScrollWheelEventPointDeltaAxis{axis}",
        ):
            field = getattr(Quartz, field_name, None)
            if field is None:
                continue
            value = Quartz.CGEventGetIntegerValueField(cg_event, field)
            if value:
                Quartz.CGEventSetIntegerValueField(cg_event, field, -value)

    def _post_shift_hscroll_event(self, cg_event):
        """Translate Shift+vertical-wheel into a horizontal scroll event.

        The translated event has axis-1 zeroed and axis-1 deltas copied onto
        axis-2.  The Shift modifier is stripped so that apps which already
        translate Shift+scroll themselves do not double-translate.  The
        `invert_hscroll` setting flips the direction.
        """
        v_line = Quartz.CGEventGetIntegerValueField(
            cg_event, Quartz.kCGScrollWheelEventDeltaAxis1
        )
        v_fixed = Quartz.CGEventGetIntegerValueField(
            cg_event, Quartz.kCGScrollWheelEventFixedPtDeltaAxis1
        )
        v_point = Quartz.CGEventGetIntegerValueField(
            cg_event, Quartz.kCGScrollWheelEventPointDeltaAxis1
        )

        if self.invert_hscroll:
            v_line = -v_line
            v_fixed = -v_fixed
            v_point = -v_point

        is_continuous = Quartz.CGEventGetIntegerValueField(cg_event, 88)
        if is_continuous:
            unit = Quartz.kCGScrollEventUnitPixel
            primary_delta = v_point
        else:
            unit = Quartz.kCGScrollEventUnitLine
            primary_delta = v_line

        new_event = Quartz.CGEventCreateScrollWheelEvent(
            None, unit, 2, 0, primary_delta
        )
        if not new_event:
            return False

        flags = Quartz.CGEventGetFlags(cg_event)
        Quartz.CGEventSetFlags(new_event, flags & ~Quartz.kCGEventFlagMaskShift)
        Quartz.CGEventSetIntegerValueField(
            new_event,
            Quartz.kCGEventSourceUserData,
            _SHIFT_WHEEL_HSCROLL_MARKER,
        )

        for field_name, value in (
            ("kCGScrollWheelEventDeltaAxis2", v_line),
            ("kCGScrollWheelEventFixedPtDeltaAxis2", v_fixed),
            ("kCGScrollWheelEventPointDeltaAxis2", v_point),
            ("kCGScrollWheelEventDeltaAxis1", 0),
            ("kCGScrollWheelEventFixedPtDeltaAxis1", 0),
            ("kCGScrollWheelEventPointDeltaAxis1", 0),
        ):
            field = getattr(Quartz, field_name, None)
            if field is None:
                continue
            Quartz.CGEventSetIntegerValueField(new_event, field, value)

        for field_name in (
            "kCGScrollWheelEventScrollPhase",
            "kCGScrollWheelEventMomentumPhase",
        ):
            field = getattr(Quartz, field_name, None)
            if field is None:
                continue
            value = Quartz.CGEventGetIntegerValueField(cg_event, field)
            Quartz.CGEventSetIntegerValueField(new_event, field, value)

        Quartz.CGEventPost(Quartz.kCGHIDEventTap, new_event)
        return True

    def _post_inverted_scroll_event(self, cg_event):
        v_point = Quartz.CGEventGetIntegerValueField(
            cg_event, Quartz.kCGScrollWheelEventPointDeltaAxis1
        )
        h_point = Quartz.CGEventGetIntegerValueField(
            cg_event, Quartz.kCGScrollWheelEventPointDeltaAxis2
        )
        if self.invert_vscroll:
            v_point = -v_point
        if self.invert_hscroll:
            h_point = -h_point

        inverted = Quartz.CGEventCreateScrollWheelEvent(
            None,
            Quartz.kCGScrollEventUnitPixel,
            2,
            v_point,
            h_point,
        )
        if not inverted:
            return False
        Quartz.CGEventSetFlags(inverted, Quartz.CGEventGetFlags(cg_event))
        Quartz.CGEventSetIntegerValueField(
            inverted, Quartz.kCGEventSourceUserData, _SCROLL_INVERT_MARKER
        )
        for axis in (1, 2):
            sign = -1 if (
                (axis == 1 and self.invert_vscroll)
                or (axis == 2 and self.invert_hscroll)
            ) else 1
            for field_name in (
                f"kCGScrollWheelEventDeltaAxis{axis}",
                f"kCGScrollWheelEventFixedPtDeltaAxis{axis}",
                f"kCGScrollWheelEventPointDeltaAxis{axis}",
            ):
                field = getattr(Quartz, field_name, None)
                if field is None:
                    continue
                value = Quartz.CGEventGetIntegerValueField(cg_event, field)
                Quartz.CGEventSetIntegerValueField(inverted, field, sign * value)
        for field_name in (
            "kCGScrollWheelEventScrollPhase",
            "kCGScrollWheelEventMomentumPhase",
        ):
            field = getattr(Quartz, field_name, None)
            if field is None:
                continue
            value = Quartz.CGEventGetIntegerValueField(cg_event, field)
            Quartz.CGEventSetIntegerValueField(inverted, field, value)
        Quartz.CGEventPost(Quartz.kCGHIDEventTap, inverted)
        return True

    def _emit_gesture_swipe(self, mouse_event):
        self._enqueue_dispatch_event(mouse_event)

    def _dispatch_worker(self):
        while self._running:
            try:
                event = self._dispatch_queue.get(timeout=0.05)
            except queue.Empty:
                continue
            # Action execution downstream of _dispatch creates Quartz
            # CGEvent / NSEvent objects (key_simulator). This worker runs on
            # its own thread, which has no NSAutoreleasePool, so without an
            # explicit pool every autoreleased Foundation temporary produced
            # while injecting a keystroke or mouse click leaks for the process
            # lifetime -- the memory-growth-per-click reported in #233. The
            # CGEventTap callback is already wrapped (@_autoreleased); this
            # covers the second thread that touches Foundation objects.
            with objc.autorelease_pool():
                self._dispatch(event)

    @_autoreleased
    def _event_tap_callback(self, proxy, event_type, cg_event, refcon):
        try:
            if event_type in (
                _kCGEventTapDisabledByTimeout,
                _kCGEventTapDisabledByUserInput,
            ):
                print(
                    f"[MouseHook] CGEventTap disabled by system "
                    f"(type=0x{event_type:X}), re-enabling",
                    flush=True,
                )
                # A pending owner-gesture release may have been dropped while
                # the tap was disabled -- abort it so the cursor can't freeze.
                self.abort_button_gesture("tap_disabled")
                Quartz.CGEventTapEnable(self._tap, True)
                return cg_event

            if not self._first_event_logged:
                self._first_event_logged = True
                print("[MouseHook] CGEventTap: first event received", flush=True)

            try:
                if (
                    Quartz.CGEventGetIntegerValueField(
                        cg_event, Quartz.kCGEventSourceUserData
                    )
                    == _INJECTED_EVENT_MARKER
                ):
                    return cg_event
            except Exception:
                pass

            # KVM / cold-start guard: when no Logitech is currently bound to
            # this host, the CGEventTap must be a complete pass-through. The
            # tap sees events from every mouse the OS knows about, so without
            # this guard a trackpad swipe or a generic USB mouse's xbutton
            # click would get routed through Mouser's remap pipeline -- the
            # exact failure mode users hit when their KVM switches the
            # Logitech to another machine while Mouser keeps running on
            # this one.
            if not self._should_intercept_events():
                return cg_event

            mouse_event = None
            should_block = False

            # ── Per-button slide gestures (back/forward/middle) ──────────
            # Motion while an owner button is held feeds the shared recognizer
            # and is swallowed (return None) so the cursor freezes during the
            # gesture. Fast None-check when no owner is armed.
            if (
                self._button_gesture_active_owner is not None
                and event_type in (
                    Quartz.kCGEventMouseMoved,
                    Quartz.kCGEventOtherMouseDragged,
                )
            ):
                dx = Quartz.CGEventGetIntegerValueField(
                    cg_event, Quartz.kCGMouseEventDeltaX
                )
                dy = Quartz.CGEventGetIntegerValueField(
                    cg_event, Quartz.kCGMouseEventDeltaY
                )
                self.sample_button_gesture(dx, dy, "os_motion")
                return None

            if (
                event_type
                in (
                    Quartz.kCGEventMouseMoved,
                    Quartz.kCGEventOtherMouseDragged,
                )
                and self._gesture_active
            ):
                if not self._gesture_direction_enabled:
                    return cg_event
                dx = Quartz.CGEventGetIntegerValueField(
                    cg_event, Quartz.kCGMouseEventDeltaX
                )
                dy = Quartz.CGEventGetIntegerValueField(
                    cg_event, Quartz.kCGMouseEventDeltaY
                )
                self._emit_debug(
                    f"Gesture move event type={int(event_type)} dx={dx} dy={dy}"
                )
                self._gesture_recognizer.sample(dx, dy, "event_tap")
                return None

            if event_type == Quartz.kCGEventOtherMouseDown:
                btn = Quartz.CGEventGetIntegerValueField(
                    cg_event, Quartz.kCGMouseEventButtonNumber
                )
                if self.debug_mode and self._debug_callback:
                    try:
                        self._debug_callback(f"OtherMouseDown btn={btn}")
                    except Exception:
                        pass
                owner = _BTN_TO_GESTURE_OWNER.get(btn)
                if (owner is not None and self.is_button_gesture_owner(owner)
                        and self.arm_button_gesture(owner)):
                    # Armed as a gesture pad -- swallow the press; motion feeds
                    # the recognizer and the release resolves it.
                    return None
                if btn == _BTN_MIDDLE:
                    mouse_event = MouseEvent(MouseEvent.MIDDLE_DOWN)
                    should_block = MouseEvent.MIDDLE_DOWN in self._blocked_events
                elif btn == _BTN_BACK:
                    mouse_event = MouseEvent(MouseEvent.XBUTTON1_DOWN)
                    should_block = MouseEvent.XBUTTON1_DOWN in self._blocked_events
                elif btn == _BTN_FORWARD:
                    mouse_event = MouseEvent(MouseEvent.XBUTTON2_DOWN)
                    should_block = MouseEvent.XBUTTON2_DOWN in self._blocked_events

            elif event_type == Quartz.kCGEventOtherMouseUp:
                btn = Quartz.CGEventGetIntegerValueField(
                    cg_event, Quartz.kCGMouseEventButtonNumber
                )
                if self.debug_mode and self._debug_callback:
                    try:
                        self._debug_callback(f"OtherMouseUp btn={btn}")
                    except Exception:
                        pass
                owner = _BTN_TO_GESTURE_OWNER.get(btn)
                if (owner is not None
                        and self._button_gesture_active_owner == owner):
                    # owner-button up while armed -> resolve and swallow.
                    self.release_button_gesture(owner)
                    return None
                if btn == _BTN_MIDDLE:
                    mouse_event = MouseEvent(MouseEvent.MIDDLE_UP)
                    should_block = MouseEvent.MIDDLE_UP in self._blocked_events
                elif btn == _BTN_BACK:
                    mouse_event = MouseEvent(MouseEvent.XBUTTON1_UP)
                    should_block = MouseEvent.XBUTTON1_UP in self._blocked_events
                elif btn == _BTN_FORWARD:
                    mouse_event = MouseEvent(MouseEvent.XBUTTON2_UP)
                    should_block = MouseEvent.XBUTTON2_UP in self._blocked_events

            elif event_type == Quartz.kCGEventScrollWheel:
                source_marker = Quartz.CGEventGetIntegerValueField(
                    cg_event, Quartz.kCGEventSourceUserData
                )
                if source_marker in (
                    _SCROLL_INVERT_MARKER,
                    _SHIFT_WHEEL_HSCROLL_MARKER,
                ):
                    return cg_event
                if self.ignore_trackpad:
                    scroll_phase = Quartz.CGEventGetIntegerValueField(
                        cg_event, Quartz.kCGScrollWheelEventScrollPhase
                    )
                    momentum_phase = Quartz.CGEventGetIntegerValueField(
                        cg_event, Quartz.kCGScrollWheelEventMomentumPhase
                    )
                    if scroll_phase != 0 or momentum_phase != 0:
                        return cg_event
                h_delta = Quartz.CGEventGetIntegerValueField(
                    cg_event, Quartz.kCGScrollWheelEventFixedPtDeltaAxis2
                )
                h_delta = h_delta / 65536.0
                if self.debug_mode and self._debug_callback:
                    try:
                        v_delta = (
                            Quartz.CGEventGetIntegerValueField(
                                cg_event,
                                Quartz.kCGScrollWheelEventFixedPtDeltaAxis1,
                            )
                            / 65536.0
                        )
                        self._debug_callback(f"ScrollWheel v={v_delta} h={h_delta}")
                    except Exception:
                        pass
                if h_delta == 0:
                    flags = Quartz.CGEventGetFlags(cg_event)
                    if flags & Quartz.kCGEventFlagMaskShift:
                        v_fixed = Quartz.CGEventGetIntegerValueField(
                            cg_event,
                            Quartz.kCGScrollWheelEventFixedPtDeltaAxis1,
                        )
                        if v_fixed != 0 and self._post_shift_hscroll_event(cg_event):
                            return None
                event_type = hscroll_event_type(h_delta)
                if event_type:
                    mouse_event = MouseEvent(event_type, abs(h_delta))
                    should_block = event_type in self._blocked_events
                if mouse_event:
                    self._enqueue_dispatch_event(mouse_event)
                    mouse_event = None
                if should_block:
                    return None
                if (self.invert_vscroll or self.invert_hscroll) and not self.wheel_native_invert_active:
                    if self._post_inverted_scroll_event(cg_event):
                        return None

            if mouse_event:
                self._enqueue_dispatch_event(mouse_event)

            if should_block:
                return None
            return cg_event

        except Exception as exc:
            print(f"[MouseHook] event tap callback error: {exc}")
            return cg_event

    def _on_hid_mode_shift_down(self):
        self._emit_debug("HID mode shift button down")
        self._dispatch(MouseEvent(MouseEvent.MODE_SHIFT_DOWN))

    def _on_hid_mode_shift_up(self):
        self._emit_debug("HID mode shift button up")
        self._dispatch(MouseEvent(MouseEvent.MODE_SHIFT_UP))

    def _on_hid_dpi_switch_down(self):
        self._emit_debug("HID DPI switch button down")
        self._dispatch(MouseEvent(MouseEvent.DPI_SWITCH_DOWN))

    def _on_hid_dpi_switch_up(self):
        self._emit_debug("HID DPI switch button up")
        self._dispatch(MouseEvent(MouseEvent.DPI_SWITCH_UP))

    def _register_wake_observer(self):
        try:
            from AppKit import NSDistributedNotificationCenter, NSWorkspace
        except ImportError:
            return
        notification_center = NSWorkspace.sharedWorkspace().notificationCenter()
        distributed_center = NSDistributedNotificationCenter.defaultCenter()
        hg = self._hid_gesture
        unlock_recovery_lock = threading.Lock()
        last_unlock_recovery_at = [float("-inf")]

        def _re_enable_tap_and_reconnect(reason):
            if self._tap and self._running:
                Quartz.CGEventTapEnable(self._tap, True)
                ok = Quartz.CGEventTapIsEnabled(self._tap)
                print(
                    f"[MouseHook] Event tap re-enabled ({reason}): "
                    f"{'OK' if ok else 'FAILED — may need restart'}",
                    flush=True,
                )
            if hg:
                hg.force_reconnect()

        def _retry_after_session_transition(reason, delay):
            """Retry after macOS finishes rebuilding the login session.

            On lock/unlock, NSWorkspace's active notification can arrive
            before the HID receiver and CGEventTap are usable again. A single
            immediate re-enable races that transition and leaves the hook
            alive but ineffective. Keep the retry bounded and cancel it in
            ``stop`` so this cannot create a permanent background worker.
            """
            def _retry():
                with self._session_rearm_lock:
                    self._session_rearm_timers.discard(timer)
                if self._running:
                    _re_enable_tap_and_reconnect(reason)

            timer = threading.Timer(delay, _retry)
            timer.daemon = True
            with self._session_rearm_lock:
                self._session_rearm_timers.add(timer)
            timer.start()

        def _on_wake(notification):
            _re_enable_tap_and_reconnect("wake")
            _retry_after_session_transition("wake-retry-1", 1.0)
            _retry_after_session_transition("wake-retry-2", 3.0)

        def _on_session_resign(notification):
            print("[MouseHook] Session deactivated", flush=True)

        def _on_session_activate(notification):
            _re_enable_tap_and_reconnect("user-switch")
            _retry_after_session_transition("session-retry-1", 1.0)
            _retry_after_session_transition("session-retry-2", 3.0)

        def _on_screen_unlock(notification):
            # A normal lock-screen round trip does not emit the workspace
            # wake or fast-user-switch notifications above. Logitech firmware
            # can still lose its native wheel-invert bit while the existing
            # HID connection remains logically alive, so force a bounded
            # reconnect after this separate screen-unlock signal.
            #
            # Some macOS versions emit the distributed notification while the
            # IOConsoleLocked fallback observes the same transition. Coalesce
            # that pair so one unlock creates only one reconnect sequence.
            now = time.monotonic()
            with unlock_recovery_lock:
                if now - last_unlock_recovery_at[0] < 1.0:
                    print(
                        "[MouseHook] Duplicate screen-unlock recovery coalesced",
                        flush=True,
                    )
                    return
                last_unlock_recovery_at[0] = now
            _re_enable_tap_and_reconnect("screen-unlock")
            _retry_after_session_transition("screen-unlock-retry-1", 1.0)
            _retry_after_session_transition("screen-unlock-retry-2", 3.0)

        # `com.apple.screenIsUnlocked` is not emitted on every macOS release
        # and lock path. IOConsoleLocked is the authoritative kernel-side
        # state on those systems, so watch its true -> false edge as a bounded
        # fallback. The edge invokes the same full HID reconnect path, which
        # re-discovers features, re-diverts the wheel-mode button, and lets the
        # engine replay saved wheel settings.
        self._console_lock_stop.clear()

        def _monitor_console_lock():
            previous = None
            while not self._console_lock_stop.is_set():
                locked = _read_console_locked()
                if locked is not None:
                    if previous is True and locked is False:
                        print(
                            "[MouseHook] Screen unlock detected "
                            "(IOConsoleLocked)",
                            flush=True,
                        )
                        try:
                            _on_screen_unlock(None)
                        except Exception as exc:
                            print(
                                f"[MouseHook] Screen unlock recovery failed: {exc}",
                                flush=True,
                            )
                    previous = locked
                if self._console_lock_stop.wait(0.5):
                    return

        self._console_lock_thread = threading.Thread(
            target=_monitor_console_lock,
            daemon=True,
            name="ConsoleLockMonitor",
        )
        self._console_lock_thread.start()

        self._wake_observer = notification_center.addObserverForName_object_queue_usingBlock_(
            "NSWorkspaceDidWakeNotification",
            None,
            None,
            _on_wake,
        )
        self._session_resign_observer = (
            notification_center.addObserverForName_object_queue_usingBlock_(
                "NSWorkspaceSessionDidResignActiveNotification",
                None,
                None,
                _on_session_resign,
            )
        )
        self._session_activate_observer = (
            notification_center.addObserverForName_object_queue_usingBlock_(
                "NSWorkspaceSessionDidBecomeActiveNotification",
                None,
                None,
                _on_session_activate,
            )
        )
        self._screen_unlock_observer = (
            distributed_center.addObserverForName_object_queue_usingBlock_(
                "com.apple.screenIsUnlocked",
                None,
                None,
                _on_screen_unlock,
            )
        )

    def _unregister_wake_observer(self):
        try:
            from AppKit import NSDistributedNotificationCenter, NSWorkspace

            notification_center = NSWorkspace.sharedWorkspace().notificationCenter()
            for attr in (
                "_wake_observer",
                "_session_resign_observer",
                "_session_activate_observer",
            ):
                observer = getattr(self, attr, None)
                if observer is not None:
                    notification_center.removeObserver_(observer)
                    setattr(self, attr, None)
            observer = self._screen_unlock_observer
            if observer is not None:
                NSDistributedNotificationCenter.defaultCenter().removeObserver_(
                    observer
                )
                self._screen_unlock_observer = None
        except Exception:
            pass

    def _stop_console_lock_monitor(self):
        self._console_lock_stop.set()
        thread = self._console_lock_thread
        if thread is not None and thread is not threading.current_thread():
            thread.join(timeout=2)
        self._console_lock_thread = None

    def start(self):
        if not _QUARTZ_OK:
            print("[MouseHook] Quartz not available — hook not installed")
            return False
        if self._running:
            return True

        event_mask = (
            Quartz.CGEventMaskBit(Quartz.kCGEventMouseMoved)
            | Quartz.CGEventMaskBit(Quartz.kCGEventOtherMouseDown)
            | Quartz.CGEventMaskBit(Quartz.kCGEventOtherMouseUp)
            | Quartz.CGEventMaskBit(Quartz.kCGEventOtherMouseDragged)
            | Quartz.CGEventMaskBit(Quartz.kCGEventScrollWheel)
        )

        self._tap = Quartz.CGEventTapCreate(
            Quartz.kCGSessionEventTap,
            Quartz.kCGHeadInsertEventTap,
            Quartz.kCGEventTapOptionDefault,
            event_mask,
            self._event_tap_callback,
            None,
        )

        if self._tap is None:
            print("[MouseHook] ERROR: Failed to create CGEventTap!")
            print("[MouseHook] Grant Accessibility permission in:")
            print(
                "[MouseHook]   System Settings -> Privacy & Security -> Accessibility"
            )
            return False

        print("[MouseHook] CGEventTap created successfully", flush=True)

        self._tap_source = Quartz.CFMachPortCreateRunLoopSource(None, self._tap, 0)
        Quartz.CFRunLoopAddSource(
            Quartz.CFRunLoopGetCurrent(),
            self._tap_source,
            Quartz.kCFRunLoopCommonModes,
        )
        Quartz.CGEventTapEnable(self._tap, True)
        print("[MouseHook] CGEventTap enabled and integrated with run loop", flush=True)
        self._running = True

        self._dispatch_thread = threading.Thread(
            target=self._dispatch_worker,
            daemon=True,
            name="MouseHook-dispatch",
        )
        self._dispatch_thread.start()

        self._start_hid_listener()
        self._register_wake_observer()
        return True

    def stop(self):
        self._stop_console_lock_monitor()
        self._unregister_wake_observer()
        with self._session_rearm_lock:
            timers = tuple(self._session_rearm_timers)
            self._session_rearm_timers.clear()
        for timer in timers:
            timer.cancel()
        self._running = False
        self.abort_button_gesture("stop")
        self._stop_hid_listener()
        self._connected_device = None

        if self._tap:
            Quartz.CGEventTapEnable(self._tap, False)
            if self._tap_source:
                Quartz.CFRunLoopRemoveSource(
                    Quartz.CFRunLoopGetCurrent(),
                    self._tap_source,
                    Quartz.kCFRunLoopCommonModes,
                )
                self._tap_source = None
            self._tap = None
            print("[MouseHook] CGEventTap disabled and removed", flush=True)

        if self._dispatch_thread:
            self._dispatch_thread.join(timeout=1)
            self._dispatch_thread = None


MouseHook._platform_module = sys.modules[__name__]


__all__ = [
    "MouseHook",
    "HidGestureListener",
    "Quartz",
    "_QUARTZ_OK",
    "_BTN_MIDDLE",
    "_BTN_BACK",
    "_BTN_FORWARD",
    "_SCROLL_INVERT_MARKER",
    "_INJECTED_EVENT_MARKER",
    "_SHIFT_WHEEL_HSCROLL_MARKER",
    "_kCGEventTapDisabledByTimeout",
    "_kCGEventTapDisabledByUserInput",
]
