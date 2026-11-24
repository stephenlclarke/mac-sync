import Foundation
@testable import MacSyncApp
import MacSyncCore
import XCTest

final class GitCredentialServiceTests: XCTestCase {
    func testPayloadIsHostScopedAndNeverEmbedsCredentialsInURL() throws {
        let data = try GitCredentialService.payload(remote: "https://git.example.test:8443/owner/repo", username: "demo", token: "not-a-real-token")
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "protocol=https\nhost=git.example.test:8443\nusername=demo\npassword=not-a-real-token\n\n")
    }

    func testRejectsCredentialProtocolInjectionAndSSH() {
        for remote in ["https://demo:secret@git.example.test/owner/repo", "git@git.example.test:owner/repo"] {
            XCTAssertThrowsError(try GitCredentialService.payload(remote: remote, username: "demo", token: "not-a-real-token"))
        }
        XCTAssertThrowsError(try GitCredentialService.payload(remote: "https://git.example.test/owner/repo", username: "demo\npassword=other", token: "test"))
        XCTAssertThrowsError(try GitCredentialService.payload(remote: "https://git.example.test/owner/repo", username: "demo", token: String(repeating: "t", count: 32769)))
    }

    func testProcessInputIsStreamedWithoutArguments() {
        let payload = Data(repeating: 65, count: 128 * 1024)
        let result = ProcessRunner().run("/bin/cat", timeout: 5, outputLimit: 256 * 1024, input: payload)
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(Data(result.stdout.utf8), payload)
        XCTAssertEqual(ProcessRunner().run("/usr/bin/false", timeout: 5, input: payload).status, 1)
    }
}
