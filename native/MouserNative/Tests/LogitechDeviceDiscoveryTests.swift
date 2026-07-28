import CoreHID
import Foundation
import Testing
@testable import MouserNative

private actor NotificationSubscriptionCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

private enum NotificationStreamFailure: Error {
    case disconnected
}

@Suite("Logitech device discovery")
@MainActor
struct LogitechDeviceDiscoveryTests {
    @Test("CoreHID notification stream is resubscribed after a failure")
    func notificationStreamRetries() async {
        let subscriptions = NotificationSubscriptionCounter()
        let discovery = CoreHIDLogitechDeviceDiscovery(
            notificationSource: { _ in
                await subscriptions.increment()
                return AsyncThrowingStream<HIDDeviceManager.Notification, any Error> {
                    continuation in
                    continuation.finish(throwing: NotificationStreamFailure.disconnected)
                }
            },
            retryDelay: .milliseconds(1)
        )
        let monitor = Task {
            for await _ in discovery.updates() {}
        }

        for _ in 0..<100 where await subscriptions.value < 2 {
            try? await Task.sleep(for: .milliseconds(2))
        }

        #expect(await subscriptions.value >= 2)
        monitor.cancel()
        _ = await monitor.result
    }

    @Test("IOKit snapshot is emitted before CoreHID notifications arrive")
    func initialIOKitSnapshotIsEmitted() async {
        let receiver = LogitechHIDDevice(
            id: 0x1002EB0C9,
            productID: 0xC52B,
            productName: "USB Receiver",
            transport: "USB",
            usagePage: 0xFF00,
            usage: 1,
            locationID: 0x0123_0000
        )
        let discovery = CoreHIDLogitechDeviceDiscovery(
            notificationSource: { _ in
                AsyncThrowingStream<HIDDeviceManager.Notification, any Error> { _ in }
            },
            retryDelay: .seconds(1),
            snapshotSource: { [receiver] }
        )

        var firstSnapshot: [LogitechHIDDevice]?
        for await snapshot in discovery.updates() where !snapshot.isEmpty {
            firstSnapshot = snapshot
            break
        }

        #expect(firstSnapshot == [receiver])
    }

    @Test("opt-in real HID smoke test identifies the connected Logitech mouse")
    func realHIDSmokeTest() async {
        let sentinel = "/tmp/mouser-real-hid-test-enabled"
        guard ProcessInfo.processInfo.environment["MOUSER_REAL_HID"] == "1" ||
                FileManager.default.fileExists(atPath: sentinel)
        else {
            print("[RealHID] skipped")
            return
        }
        print("[RealHID] enabled")
        let discovery = CoreHIDLogitechDeviceDiscovery()
        let devices = await withTaskGroup(of: [LogitechHIDDevice].self) { group in
            group.addTask {
                for await snapshot in discovery.updates() where !snapshot.isEmpty {
                    return snapshot
                }
                return []
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(8))
                return []
            }
            let result = await group.next() ?? []
            group.cancelAll()
            return result
        }
        for device in devices {
            print(
                "[RealHID] id=\(device.id) pid=0x\(String(device.productID, radix: 16)) " +
                "usage=0x\(String(device.usagePage, radix: 16))/\(device.usage.map(String.init) ?? "nil") " +
                "name=\(device.productName ?? "nil")"
            )
        }
        guard let interface = LogitechDeviceInventory.preferredHIDPPInterface(from: devices) else {
            Issue.record("8 秒内未发现 Logitech HID++ 接口")
            return
        }
        print("[RealHID] selected id=\(interface.id) pid=0x\(String(interface.productID, radix: 16))")
        let identity = await discovery.identify(interface)
        #expect(identity != nil, "发现 HID++ 接口但未识别到接收器中的鼠标")
        if let identity {
            print("[RealHID] identified \(identity.name), slot \(identity.deviceIndex)")
            guard let controller = await discovery.controller(
                for: interface,
                identity: identity
            ) else {
                Issue.record("已识别鼠标但无法创建 HID++ 控制器")
                return
            }
            let state = await controller.readState(timeout: .seconds(2))
            print(
                "[RealHID] dpi=\(state.dpi.map(String.init) ?? "nil") " +
                "smartShift=\(String(describing: state.smartShift)) " +
                "verticalInverted=\(state.verticalScrollInverted.map(String.init) ?? "nil") " +
                "battery=\(String(describing: state.battery))"
            )
            #expect(state.dpi != nil, "鼠标已识别但 DPI 状态不可读")
            #expect(state.smartShift != nil, "鼠标已识别但 SmartShift 状态不可读")
            #expect(state.verticalScrollInverted != nil, "鼠标已识别但纵向滚轮模式不可读")
        } else {
            for line in await discovery.diagnosticFeatureProbe(interface) {
                print("[RealHID] \(line)")
            }
        }
    }

    @Test("a receiver is reported without pretending that a mouse was identified")
    func receiverDoesNotPretendToBeMouse() {
        let receiver = LogitechHIDDevice(
            id: 0x1002EB0C9,
            productID: 0xC52B,
            productName: "USB Receiver",
            transport: "USB"
        )
        let model = WorkspaceModel.preview

        model.applyDetectedDevices([receiver])

        #expect(!model.mouseConnected)
        #expect(model.receiverDetected)
        #expect(model.deviceName == "Logitech USB Receiver")
        #expect(model.deviceTransport == "USB")
        #expect(model.deviceStatusText == "已检测到接收器，鼠标待确认")
    }

    @Test("known MX Master devices take priority over their receiver")
    func knownMouseTakesPriority() {
        let receiver = LogitechHIDDevice(
            id: 1,
            productID: 0xC548,
            productName: "Logi Bolt Receiver",
            transport: "USB"
        )
        let mouse = LogitechHIDDevice(
            id: 2,
            productID: 0xB034,
            productName: nil,
            transport: "Bluetooth Low Energy"
        )
        let model = WorkspaceModel.preview

        model.applyDetectedDevices([receiver, mouse])

        #expect(model.mouseConnected)
        #expect(model.receiverDetected)
        #expect(model.deviceName == "MX Master 3S")
        #expect(model.deviceTransport == "Bluetooth Low Energy")
        #expect(model.deviceStatusText == "已检测到，控制未接管")
    }

    @Test("vendor-defined receiver collection is selected for HID++ reports")
    func selectsVendorDefinedReceiverCollection() {
        let mouseCollection = LogitechHIDDevice(
            id: 1,
            productID: 0xC52B,
            productName: "USB Receiver",
            transport: "USB",
            usagePage: 0x01,
            usage: 0x02
        )
        let hidppCollection = LogitechHIDDevice(
            id: 2,
            productID: 0xC52B,
            productName: "USB Receiver",
            transport: "USB",
            usagePage: 0xFF00,
            usage: 0x01
        )

        #expect(!mouseCollection.isHIDPPInterface)
        #expect(hidppCollection.isHIDPPInterface)
        #expect(
            LogitechDeviceInventory.preferredHIDPPInterface(
                from: [mouseCollection, hidppCollection]
            )?.id == 2
        )
    }

    @Test("IOKit matching targets the exact CoreHID interface")
    func matchesExactIOKitInterface() {
        let device = LogitechHIDDevice(
            id: 42,
            productID: 0xC52B,
            productName: "USB Receiver",
            transport: "USB",
            usagePage: 0xFF00,
            usage: 0x01,
            locationID: 0x14200000
        )

        let matching = IOKitHIDDeviceMatcher.matchingDictionary(for: device)

        #expect(matching["VendorID"] as? Int == 0x046D)
        #expect(matching["ProductID"] as? Int == 0xC52B)
        #expect(matching["PrimaryUsagePage"] as? Int == 0xFF00)
        #expect(matching["PrimaryUsage"] as? Int == 0x01)
        #expect(matching["LocationID"] as? Int == 0x14200000)
    }
}
