import Foundation
import IOKit

struct IOConsoleLockStateReader: Sendable {
    func read() -> Bool? {
        let root = IORegistryGetRootEntry(0)
        guard root != 0 else { return nil }
        defer { IOObjectRelease(root) }

        let ioConsoleLocked = Self.property(
            named: "IOConsoleLocked",
            from: root
        ) as? Bool
        let consoleUsers = Self.property(
            named: "IOConsoleUsers",
            from: root
        ) as? [[String: Any]]
        let consoleUserLockStates = (consoleUsers ?? []).compactMap { user -> Bool? in
            if let isOnConsole = user["kCGSSessionOnConsoleKey"] as? Bool,
               !isOnConsole {
                return nil
            }
            return user["kCGSSessionScreenIsLocked"] as? Bool
        }
        return Self.resolve(
            ioConsoleLocked: ioConsoleLocked,
            consoleUserLockStates: consoleUserLockStates
        )
    }

    static func resolve(
        ioConsoleLocked: Bool?,
        consoleUserLockStates: [Bool]
    ) -> Bool? {
        if consoleUserLockStates.contains(true) {
            return true
        }
        if !consoleUserLockStates.isEmpty {
            return false
        }
        return ioConsoleLocked
    }

    private static func property(named name: String, from root: io_registry_entry_t) -> Any? {
        guard let unmanagedValue = IORegistryEntryCreateCFProperty(
            root,
            name as CFString,
            nil,
            0
        ) else {
            return nil
        }
        return unmanagedValue.takeRetainedValue()
    }
}
