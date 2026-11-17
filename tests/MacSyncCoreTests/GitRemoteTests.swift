import MacSyncCore
import XCTest

final class GitRemoteTests: XCTestCase {
    func testHostedAndNestedGitEndpoints() throws {
        for input in ["https://github.com/user/data.git", "git@gitlab.com:group/subgroup/data.git",
                      "https://person@bitbucket.org/workspace/data.git", "ssh://git@git.example.org:2222/team/data.git"] {
            let remote = try XCTUnwrap(GitRemote(input))
            XCTAssertNotNil(GitRemote(remote.cloneURL))
            XCTAssertFalse(remote.displayURL.contains("person@"))
        }
        XCTAssertEqual(GitRemote("git@gitlab.com:team/subteam/data.git")?.sshURL, "ssh://git@gitlab.com/team/subteam/data.git")
        XCTAssertEqual(GitRemote("https://bitbucket.org/team/data")?.sshURL, "git@bitbucket.org:team/data.git")
    }

    func testUnsafeOrCredentialedCloneEndpointsAreRejected() {
        for input in ["file:///tmp/data", "/tmp/data", "http://gitlab.com/team/data", "-uhoh", "ext::sh shell",
                      "https://user:password@github.com/team/data", "https://github.com/team/data?token=value",
                      "git@github.com:../data", "https://github.com/team/../data", "https://github.com/team//data"] {
            XCTAssertNil(GitRemote(input), input)
        }
    }

    func testProviderCreationLinksDoNotCreateAnythingAutomatically() {
        XCTAssertTrue(GitHostingProvider.github.creationURL?.absoluteString.contains("visibility=private") == true)
        XCTAssertEqual(GitHostingProvider.gitlab.creationURL?.host, "gitlab.com")
        XCTAssertEqual(GitHostingProvider.bitbucket.creationURL?.host, "bitbucket.org")
        XCTAssertNil(GitHostingProvider.other.creationURL)
    }
}
