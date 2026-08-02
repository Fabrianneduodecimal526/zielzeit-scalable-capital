import Foundation

/// Resolves the preferences domain shared by the app and the CLI modes.
///
/// `UserDefaults.standard` resolves to the main bundle identifier, which the
/// packaged app has and a bare `swift run` does not. But inside the packaged app
/// that same name *is* the bundle identifier, and `UserDefaults(suiteName:)`
/// refuses to open its own bundle identifier as a suite — it logs "does not make
/// sense and will not work" and hands back an unusable store. So each context
/// needs a different route to the one domain.
enum Defaults {

    /// The single domain everything reads and writes.
    static let suiteName = "com.zielzeit.Zielzeit"

    static func shared() -> UserDefaults {
        if Bundle.main.bundleIdentifier == suiteName {
            return .standard
        }
        return UserDefaults(suiteName: suiteName) ?? .standard
    }
}
