import Foundation
import ZielzeitCore

/// `zielzeit --once`: print the report to stdout and exit.
///
/// Exists so the whole pipeline — CLI call, decoding, projection, formatting —
/// can be exercised from a terminal without a menu bar.
enum TextMode {

    /// Returns a process exit code.
    static func run(
        provider: PortfolioProviding = ScalableClient(),
        goalStore: GoalStore = GoalStore(),
        prober: SetupProbing? = ScalableClient()
    ) -> Int32 {
        // Same guidance the popover gives, so a terminal user is not left with a
        // bare error when the real problem is that setup is incomplete.
        if let prober {
            let setup = prober.detectSetup()
            if !setup.isConnected {
                complain(setupInstructions(for: setup))
                return 3
            }
        }

        guard let goal = goalStore.goal else {
            complain(Strings.noGoalSet)
            return 2
        }
        do {
            let snapshot = try provider.fetchSnapshot()
            print(Report(goal: goal, snapshot: snapshot).textReport())
            return 0
        } catch {
            complain(Strings.errorPrefix(error.localizedDescription))
            return 1
        }
    }

    /// The onboarding steps, as text.
    private static func setupInstructions(for state: SetupState) -> String {
        var lines = [Strings.notConnectedYet, ""]

        switch state {
        case .cliMissing:
            lines += [
                Strings.stepInstallCLI,
                "     \(AccessRequest.installCommand)",
                "   \(AccessRequest.repositoryURL.absoluteString)",
                "",
                Strings.stepRequestAllowlisting,
                "     \(AccessRequest.emailAddress)   \(Strings.subjectNote(AccessRequest.emailSubject))",
                "   \(AccessRequest.senderNote)",
                "",
                Strings.stepSignIn,
                "     \(AccessRequest.loginCommand)",
            ]

        case .notConnected(let code, let hasRequested):
            if let code {
                lines += [Strings.yourInstallationCode(code), ""]
            }
            if !hasRequested {
                lines += [
                    Strings.ifNotAllowlistedEmail,
                    "  \(AccessRequest.emailAddress)   \(Strings.subjectNote(AccessRequest.emailSubject))",
                    "  \(AccessRequest.senderNote)",
                    "",
                ]
            }
            lines += [Strings.thenSignIn, "  \(AccessRequest.loginCommand)"]

        case .connected:
            break
        }

        return lines.joined(separator: "\n")
    }

    private static func complain(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
