import ServiceManagement

@MainActor
protocol LoginItemControlling: AnyObject {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

@MainActor
final class SystemLoginItemController: LoginItemControlling {
    private let service: SMAppService

    init(service: SMAppService = .mainApp) {
        self.service = service
    }

    var isEnabled: Bool {
        switch service.status {
        case .enabled, .requiresApproval:
            true
        case .notRegistered, .notFound:
            false
        @unknown default:
            false
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        guard enabled != isEnabled else { return }
        if enabled {
            try service.register()
        } else {
            try service.unregister()
        }
    }
}
