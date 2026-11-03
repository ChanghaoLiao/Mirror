import Foundation
import XCTest

@testable import Mirror

final class AccessibilityDiagnosticsTests: XCTestCase {
    func testHistoryNeverTurnsARevokedPermissionIntoAGrant() throws {
        try withDefaults { defaults in
            let diagnostics = make("first", defaults: defaults)
            XCTAssertEqual(diagnostics.observe(granted: false), .notGranted)
            XCTAssertEqual(diagnostics.observe(granted: true), .granted)
            XCTAssertEqual(diagnostics.observe(granted: false), .previouslyGranted)
        }
    }

    func testChangedAdHocBuildIsIdentifiedOnlyAfterAnObservedGrant() throws {
        try withDefaults { defaults in
            XCTAssertEqual(make("first", defaults: defaults).observe(granted: false), .notGranted)
            XCTAssertEqual(make("second", defaults: defaults).observe(granted: false), .notGranted)
            _ = make("first", defaults: defaults).observe(granted: true)
            let updated = make("second", defaults: defaults)
            XCTAssertEqual(updated.observe(granted: false), .changedDevelopmentBuild)
            XCTAssertEqual(updated.observe(granted: true), .granted)
            XCTAssertEqual(updated.observe(granted: false), .previouslyGranted)
        }
    }

    func testCertificateSignedUpdateIsNotDiagnosedAsAnAdHocIdentityChange() throws {
        try withDefaults { defaults in
            _ = make("first", defaults: defaults).observe(granted: true)
            XCTAssertEqual(
                make("second", adHoc: false, defaults: defaults).observe(granted: false),
                .previouslyGranted)
        }
    }

    func testUnavailableSigningInformationDoesNotInventAnIdentityChange() throws {
        try withDefaults { defaults in
            _ = make("first", defaults: defaults).observe(granted: true)
            XCTAssertEqual(make(nil, defaults: defaults).observe(granted: false), .previouslyGranted)
        }
    }

    func testGrantWithoutAReadableHashDiscardsTheOlderBuildIdentity() throws {
        try withDefaults { defaults in
            _ = make("first", defaults: defaults).observe(granted: true)
            _ = make(nil, defaults: defaults).observe(granted: true)
            XCTAssertEqual(make("second", defaults: defaults).observe(granted: false), .previouslyGranted)
        }
    }

    private func make(_ hash: String?, adHoc: Bool = true, defaults: UserDefaults)
        -> AccessibilityDiagnostics
    {
        AccessibilityDiagnostics(
            identity: .init(
                codeHash: hash, adHoc: adHoc, appURL: URL(fileURLWithPath: "/example/Mirror.app")),
            defaults: defaults)
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "MirrorPermissionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }
}
