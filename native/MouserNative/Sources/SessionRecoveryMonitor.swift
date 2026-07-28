import Foundation
import IOKit

struct IOConsoleLockStateReader: Sendable {
    func read() -> Bool? {
        let root = IORegistryGetRootEntry(0)
        guard root != 0 else { return nil }
        defer { IOObjectRelease(root) }

        guard let unmanagedValue = IORegistryEntryCreateCFProperty(
            root,
            "IOConsoleLocked" as CFString,
            nil,
            0
        ) else {
            return nil
        }
        let value = unmanagedValue.takeRetainedValue()
        return value as? Bool
    }
}
