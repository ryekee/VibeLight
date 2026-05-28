import Foundation
import ServiceManagement

enum LoginItemManager {
    enum SyncResult {
        case ok
        case notSupported    // SMAppService unavailable (e.g. unsigned bundle outside /Applications)
        case failed(String)
    }

    @discardableResult
    static func sync(enabled: Bool) -> SyncResult {
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status == .enabled { return .ok }
                try service.register()
            } else {
                if service.status == .notRegistered { return .ok }
                try service.unregister()
            }
            return .ok
        } catch let err as NSError {
            // For unsigned dev bundles SMAppService returns error code 1.
            if err.domain == "SMAppServiceErrorDomain" && err.code == 1 {
                return .notSupported
            }
            return .failed(err.localizedDescription)
        }
    }

    static var currentStatus: SMAppService.Status {
        SMAppService.mainApp.status
    }
}
