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
            complain("No goal set. Set one in the app, or pass ZIELZEIT_GOAL=100000.")
            return 2
        }
        do {
            let snapshot = try provider.fetchSnapshot()
            print(Report(goal: goal, snapshot: snapshot).textReport())
            return 0
        } catch {
            complain("Error: \(error.localizedDescription)")
            return 1
        }
    }

    /// The onboarding steps, as text.
    private static func setupInstructions(for state: SetupState) -> String {
        var lines = ["Zielzeit isn't connected to your portfolio yet.", ""]

        switch state {
        case .cliMissing:
            lines += [
                "1. Install the Scalable CLI (it's in beta):",
                "     \(AccessRequest.installCommand)",
                "   \(AccessRequest.repositoryURL.absoluteString)",
                "",
                "2. Request allowlisting — run `sc installation-code`, then email the code to",
                "     \(AccessRequest.emailAddress)   (subject: \(AccessRequest.emailSubject))",
                "   \(AccessRequest.senderNote)",
                "",
                "3. Sign in:",
                "     \(AccessRequest.loginCommand)",
            ]

        case .notConnected(let code, let hasRequested):
            if let code {
                lines += ["Your installation code: \(code)", ""]
            }
            if !hasRequested {
                lines += [
                    "If you haven't been allowlisted yet, email the code to",
                    "  \(AccessRequest.emailAddress)   (subject: \(AccessRequest.emailSubject))",
                    "  \(AccessRequest.senderNote)",
                    "",
                ]
            }
            lines += ["Then sign in:", "  \(AccessRequest.loginCommand)"]

        case .connected:
            break
        }

        return lines.joined(separator: "\n")
    }

    private static func complain(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
