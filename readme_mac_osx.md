# macOS 原生版

macOS 版 Mouser 使用 Swift 6、SwiftUI、IOKit/CoreHID 与当前 macOS API 实现，不打包 Python、PySide6 或 Qt。

## Requirements

- **macOS 27** 或更高版本
- Apple Silicon 或 Intel Mac（同一个 universal DMG）
- Xcode 27 与 XcodeGen（仅源码构建需要）
- **Accessibility permission** — required for CGEventTap to intercept mouse events

## Granting Accessibility Permission

Mouser uses a **CGEventTap** to intercept and suppress mouse button events. macOS requires Accessibility permission for this:

1. Open **System Settings → Privacy & Security → Accessibility**
2. Click the **+** button
3. 添加并启用 **Mouser.app**
4. Ensure the checkbox is **enabled**
5. Restart Mouser if it was already running

如果授权后仍提示未开启，请在列表中移除旧 Mouser 条目，再重新添加当前 `/Applications/Mouser.app` 并重启应用。

## Platform Differences

| Feature | Windows | macOS |
|---------|---------|-------|
| Mouse hook | SetWindowsHookExW (LL hook) | CGEventTap |
| Key simulation | SendInput (VK codes) | CGEvent (CGKeyCodes) |
| Media keys | VK_MEDIA_* constants | NSEvent (NX key IDs) |
| App detection | GetForegroundWindow | NSWorkspace.frontmostApplication |
| Gesture button | HID++ + Raw Input fallback | HID++ + event-tap movement |
| Scroll inversion | Coalesced SendInput | CGEventCreateScrollWheelEvent |
| Modifier key | Ctrl | Cmd (⌘) |
| Config location | `%APPDATA%\Mouser` | `~/Library/Application Support/Mouser` |
| Auto-reconnect | Device change notification | HID++ reconnect loop |

### Key Mapping Differences

Actions that use **Ctrl** on Windows automatically use **Cmd (⌘)** on macOS:
- Copy → Cmd+C
- Paste → Cmd+V
- Cut → Cmd+X
- Undo → Cmd+Z
- etc.

Desktop/navigation actions are also remapped to native macOS behavior:
- **Alt+Tab** becomes **Cmd+Tab**
- Compatibility entries like **Win+D** / **Task View** resolve to native macOS navigation shortcuts
- Mouser also exposes macOS-specific actions such as **Mission Control**, **App Expose**, **Previous Desktop**, **Next Desktop**, **Show Desktop**, and **Launchpad**

### HID Access

原生版通过 `IOHIDDeviceOpen(..., kIOHIDOptionsTypeNone)` 非独占访问 HID++ 接口，Mouser 读写设备时不会抢占鼠标。

### Trackpad and Magic Mouse Scroll

Mouser ignores trackpad and Magic Mouse continuous scroll events by default so two-finger gestures and macOS natural scrolling keep working normally while mouse wheel mappings stay active.

You can change this in **Point & Scroll → Scroll Direction → Ignore trackpad**. Leave it enabled for built-in trackpads and most Logitech mouse setups. Disable it only if you intentionally want Mouser to handle Magic Mouse or trackpad scroll events.

## Building a Native macOS App

The repository now includes a dedicated macOS bundle flow:

```bash
cd native/MouserNative
xcodegen generate
open MouserNative.xcodeproj
```

For signed release artifacts:

```bash
./release.sh
```

Notes:

- The native app requires macOS 27 and uses Swift 6, SwiftUI, CoreHID and HID++ directly.
- Release and Debug are both universal Developer ID builds. The script notarizes and staples each app and DMG through the `Mouser-Notary` Keychain profile.
- GitHub release builds require a trusted self-hosted macOS runner labelled `mouser-release`; signing and notarization identities remain in that runner's Keychain.
- No Apple ID password is stored in the repository or passed on the command line.
- The app can then be moved to `/Applications/Mouser.app` and launched directly from Finder, Spotlight, or Dock.
- Python/PyInstaller remains the Windows/Linux implementation only.

The packaged app runs as an `LSUIElement`, so it lives in the menu bar instead of showing a Dock icon.

## 运行源码

```bash
cd native/MouserNative
xcodegen generate
open MouserNative.xcodeproj
```

在 Xcode 中运行 `MouserNative` scheme。正式 App 可在设置中选择“启动后隐藏窗口”。

## Start at Login

Mouser can now manage **Start at login** from the app UI on macOS.

- 原生版使用系统 `SMAppService` 管理登录项，不写入 LaunchAgent 或脚本。
- “启动后隐藏窗口”与“登录时启动”彼此独立。

## Accessibility for the Packaged App

If you switch from Terminal-based startup to `Mouser.app`, re-grant Accessibility for the app bundle:

1. Open **System Settings → Privacy & Security → Accessibility**
2. 如有需要，移除旧 Terminal、Python 或旧版 Mouser 条目
3. Add **Mouser.app**
4. Ensure it is enabled
5. Restart Mouser

## 调试

在“设置 → 开发者诊断”中开启内存事件日志与 HID++ 手势录制；“导出诊断”不会包含配置内容、账户或凭据。
