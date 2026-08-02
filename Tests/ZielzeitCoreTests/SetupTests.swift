import XCTest
@testable import ZielzeitCore

/// The allowlisting request has to be exactly right — a wrong address or a
/// missing installation code means the user waits for a reply that never comes,
/// and nothing in the app would reveal why.
final class AccessRequestTests: XCTestCase {

    private let code = "DEMO-1234-5678-ABCD"

    func testAddressAndSubjectMatchTheDocumentedValues() {
        XCTAssertEqual(AccessRequest.emailAddress, "cli.beta@scalable.capital")
        XCTAssertEqual(AccessRequest.emailSubject, "Scalable CLI Allowlisting")
    }

    func testBodyCarriesTheInstallationCode() {
        XCTAssertTrue(AccessRequest.emailBody(installationCode: code).contains(code))
    }

    func testMailtoURLTargetsTheRightRecipient() throws {
        let url = try XCTUnwrap(AccessRequest.mailtoURL(installationCode: code))
        XCTAssertEqual(url.scheme, "mailto")
        // Asserted against the string rather than `url.path`. The recipient of a
        // mailto URL lives in the path rather than the host, but Foundation does
        // not agree with itself about where that path is: `URL.path` returns the
        // address on macOS 26 and an empty string on macOS 15, so a test using it
        // passes on a current Mac and fails in CI on the deployment target.
        XCTAssertTrue(
            url.absoluteString.hasPrefix("mailto:cli.beta@scalable.capital?"),
            url.absoluteString
        )
    }

    func testMailtoURLCarriesSubjectAndCode() throws {
        let url = try XCTUnwrap(AccessRequest.mailtoURL(installationCode: code))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = try XCTUnwrap(components.queryItems)

        let subject = items.first { $0.name == "subject" }?.value
        XCTAssertEqual(subject, AccessRequest.emailSubject)

        let body = try XCTUnwrap(items.first { $0.name == "body" }?.value)
        XCTAssertTrue(body.contains(code), body)
    }

    func testMailtoURLPercentEncodesSpaces() throws {
        let url = try XCTUnwrap(AccessRequest.mailtoURL(installationCode: code))
        // A raw space in a URL makes mail clients truncate the subject.
        XCTAssertFalse(url.absoluteString.contains(" "), url.absoluteString)
        XCTAssertTrue(url.absoluteString.contains("Scalable%20CLI%20Allowlisting"))
    }

    func testMailtoURLEncodesPlusSigns() throws {
        // "+" in a mailto query is decoded as a space by many clients, so it must
        // arrive percent-encoded.
        let url = try XCTUnwrap(AccessRequest.mailtoURL(installationCode: "AB+CD"))
        XCTAssertFalse(url.absoluteString.contains("AB+CD"))
        XCTAssertTrue(url.absoluteString.contains("AB%2BCD"), url.absoluteString)
    }

    func testInstallCommandUsesTheOfficialTap() {
        // Zielzeit never ships its own copy of the CLI: the documentation asks
        // users to trust only official artifacts.
        XCTAssertTrue(AccessRequest.installCommand.contains("ScalableCapital/tap"))
        XCTAssertTrue(AccessRequest.installCommand.contains("scalable-cli"))
    }

    func testLoginCommandEnforcesReadOnly() {
        // The whole product promise is read-only access; the session should be
        // structurally incapable of mutation.
        XCTAssertEqual(AccessRequest.loginCommand, "sc login --local-read-only")
    }
}

final class SetupStateTests: XCTestCase {

    func testOnlyConnectedCountsAsConnected() {
        XCTAssertTrue(SetupState.connected(accountName: "Ada").isConnected)
        XCTAssertTrue(SetupState.connected(accountName: nil).isConnected)
        XCTAssertFalse(SetupState.cliMissing.isConnected)
        XCTAssertFalse(
            SetupState.notConnected(installationCode: "X", hasRequestedAccess: true).isConnected
        )
    }
}

final class SetupStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "com.zielzeit.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testAccessRequestedDefaultsToFalseAndPersists() {
        let store = SetupStore(defaults: defaults)
        XCTAssertFalse(store.hasRequestedAccess)
        store.hasRequestedAccess = true
        XCTAssertTrue(SetupStore(defaults: defaults).hasRequestedAccess)
    }
}

/// Setup detection against a stub CLI, so every branch is exercised without
/// touching the real one.
final class SetupProbeTests: XCTestCase {

    func testMissingCLIIsDetectedWithoutRunningAnything() {
        let client = ScalableClient(executablePath: "/nonexistent/sc")
        XCTAssertEqual(client.detectSetup(), .cliMissing)
    }

    func testFailingSessionReportsNotConnected() throws {
        // An installed CLI that errors on every command: no session, and no
        // installation code either.
        let script = try makeScript("#!/bin/sh\necho 'no saved session, please run sc login' >&2\nexit 1\n")
        defer { try? FileManager.default.removeItem(at: script) }

        let state = ScalableClient(executablePath: script.path, timeout: 5).detectSetup()
        guard case .notConnected(let code, _) = state else {
            return XCTFail("expected notConnected, got \(state)")
        }
        XCTAssertNil(code)
    }

    func testWorkingSessionReportsConnectedWithTheAccountName() throws {
        let script = try makeScript("""
        #!/bin/sh
        echo '{"ok":true,"command":"whoami","data":{"result":{"personOverview":{"personalDetails":{"firstName":"Ada"}}}}}'
        """)
        defer { try? FileManager.default.removeItem(at: script) }

        let state = ScalableClient(executablePath: script.path, timeout: 5).detectSetup()
        XCTAssertEqual(state, .connected(accountName: "Ada"))
    }

    func testSessionWithoutANameStillCountsAsConnected() throws {
        let script = try makeScript("""
        #!/bin/sh
        echo '{"ok":true,"command":"whoami","data":{"result":{}}}'
        """)
        defer { try? FileManager.default.removeItem(at: script) }

        XCTAssertEqual(
            ScalableClient(executablePath: script.path, timeout: 5).detectSetup(),
            .connected(accountName: nil)
        )
    }

    // MARK: - Installation code

    func testInstallationCodePrefersTheGroupedDisplayForm() throws {
        // The grouped form is what a person reads out and retypes.
        let json = #"{"ok":true,"command":"installation-code","data":{"display_code":"DEMO-1234-5678-ABCD","installation_code":"DEMO12345678ABCD"}}"#
        let payload = try ScalableClient.decodeDirect(
            InstallationCodePayload.self, from: Data(json.utf8), command: "installation-code"
        )
        XCTAssertEqual(payload.displayCode, "DEMO-1234-5678-ABCD")
        XCTAssertEqual(payload.installationCode, "DEMO12345678ABCD")
    }

    func testInstallationCodePayloadSitsDirectlyUnderData() throws {
        // Unlike the broker commands there is no `result` wrapper here; decoding
        // it with the wrapped envelope would fail.
        let json = #"{"ok":true,"data":{"installation_code":"ABC"}}"#
        XCTAssertThrowsError(
            try ScalableClient.decode(
                InstallationCodePayload.self, from: Data(json.utf8), command: "installation-code"
            )
        )
        XCTAssertNoThrow(
            try ScalableClient.decodeDirect(
                InstallationCodePayload.self, from: Data(json.utf8), command: "installation-code"
            )
        )
    }

    func testInstallationCodeFailureIsReported() {
        let json = #"{"ok":false,"error":"cannot generate code"}"#
        XCTAssertThrowsError(
            try ScalableClient.decodeDirect(
                InstallationCodePayload.self, from: Data(json.utf8), command: "installation-code"
            )
        ) { error in
            XCTAssertEqual(error as? ScalableError, .failed("cannot generate code"))
        }
    }

    // MARK: - Helpers

    private func makeScript(_ contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("zielzeit-setup-\(UUID().uuidString).sh")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }
}

/// The state a real new user is actually in: CLI installed, no session yet, but
/// `installation-code` works because it needs no session. That is the state whose
/// whole purpose is to produce the code for the Request-access button, so it is
/// worth pinning separately from the everything-fails variant.
final class NewUserSetupTests: XCTestCase {

    func testInstalledButUnauthenticatedStillYieldsAnInstallationCode() throws {
        let script = try makeScript("""
        #!/bin/sh
        case "$1" in
          whoami) echo 'no saved session, please run sc login' >&2; exit 1 ;;
          installation-code)
            echo '{"ok":true,"command":"installation-code","data":{"display_code":"DEMO-1234-5678-ABCD","installation_code":"DEMO12345678ABCD"}}' ;;
          *) exit 1 ;;
        esac
        """)
        defer { try? FileManager.default.removeItem(at: script) }

        let state = ScalableClient(executablePath: script.path, timeout: 5).detectSetup()
        guard case .notConnected(let code, _) = state else {
            return XCTFail("expected notConnected, got \(state)")
        }
        // Without this the Request-access button has nothing to send.
        XCTAssertEqual(code, "DEMO-1234-5678-ABCD")
    }

    func testTheCodeItYieldsSurvivesIntoTheMailtoURL() throws {
        let script = try makeScript("""
        #!/bin/sh
        case "$1" in
          whoami) exit 1 ;;
          installation-code)
            echo '{"ok":true,"data":{"display_code":"AAAA-BBBB-CCCC-DDDD","installation_code":"AAAABBBBCCCCDDDD"}}' ;;
          *) exit 1 ;;
        esac
        """)
        defer { try? FileManager.default.removeItem(at: script) }

        let state = ScalableClient(executablePath: script.path, timeout: 5).detectSetup()
        guard case .notConnected(let code?, _) = state else {
            return XCTFail("expected a code, got \(state)")
        }
        let url = try XCTUnwrap(AccessRequest.mailtoURL(installationCode: code))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let body = try XCTUnwrap(components.queryItems?.first { $0.name == "body" }?.value)
        XCTAssertTrue(body.contains("AAAA-BBBB-CCCC-DDDD"), body)
    }

    private func makeScript(_ contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("zielzeit-newuser-\(UUID().uuidString).sh")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }
}

/// The sender-address requirement is the one mistake that fails silently, so the
/// warning has to actually be present wherever the request is offered.
final class SenderNoteTests: XCTestCase {

    func testSenderNoteNamesTheRequirementAndWhereToCheck() {
        let note = AccessRequest.senderNote
        XCTAssertTrue(note.lowercased().contains("registered"), note)
        XCTAssertTrue(note.contains("Scalable Capital"), note)
        // Naming the From field is what makes it actionable: a mailto link opens
        // whatever the default account is.
        XCTAssertTrue(note.contains("From"), note)
    }
}
