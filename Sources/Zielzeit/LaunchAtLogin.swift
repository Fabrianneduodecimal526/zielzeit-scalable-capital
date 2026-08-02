import Foundation
import ServiceManagement

/// Wraps `SMAppService` login-item registration.
///
/// Only meaningful for a real `.app` bundle — the bare executable produced by
/// `swift build` cannot be registered, so the menu item is shown disabled
/// rather than failing at the moment it is clicked.
enum LaunchAtLogin {

    /// Whether registration is possible at all in this run.
    static var isSupported: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    static var isEnabled: Bool {
        isSupported && SMAppService.mainApp.status == .enabled
    }

    /// Flips registration. Throws so the caller can surface the reason.
    static func toggle() throws {
        guard isSupported else { return }
        if SMAppService.mainApp.status == .enabled {
            try SMAppService.mainApp.unregister()
        } else {
            try SMAppService.mainApp.register()
        }
    }
}
