import XCTest
@testable import AavaCore

private actor GitHubTransportFixture {
    var bodies: [String]
    var requests: [URLRequest] = []
    init(_ bodies: [String]) { self.bodies = bodies }
    func send(_ request: URLRequest) throws -> (Data, URLResponse) {
        requests.append(request)
        guard !bodies.isEmpty else { throw URLError(.badServerResponse) }
        return (Data(bodies.removeFirst().utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
final class GitHubAPITests: XCTestCase {
    func testAuthenticatedReadPaginationUsesFixedEndpointAndCursor() async throws {
        let fixture = GitHubTransportFixture([
            #"{"data":{"viewer":{"login":"test-user"}}}"#,
            #"{"data":{"search":{"issueCount":0,"pageInfo":{"hasNextPage":true,"endCursor":"next-page"},"nodes":[]}}}"#,
            #"{"data":{"search":{"issueCount":0,"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}}}"#
        ])
        let api = GitHubAPI(transport: { try await fixture.send($0) })
        let login = try await api.login(token: "fixture-only")
        let result = try await api.pulls(configuration: GitHubFolderConfiguration(), login: login, token: "fixture-only")
        XCTAssertTrue(result.isEmpty)
        let requests = await fixture.requests
        XCTAssertEqual(requests.count, 3)
        XCTAssertTrue(requests.allSatisfy { $0.url?.absoluteString == "https://api.github.com/graphql" && $0.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-only" })
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: requests[2].httpBody!) as? [String: Any])
        XCTAssertEqual((body["variables"] as? [String: Any])?["cursor"] as? String, "next-page")
        XCTAssertFalse((body["query"] as? String ?? "").contains("mutation"))
    }
    func testPartialErrorsCannotReplaceKnownResultsWithEmptyFolder() async throws {
        let fixture = GitHubTransportFixture([#"{"data":{"search":{"issueCount":0,"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}},"errors":[{"message":"permission denied"}]}"#])
        let api = GitHubAPI(transport: { try await fixture.send($0) })
        do { _ = try await api.pulls(configuration: GitHubFolderConfiguration(), login: "test", token: "fixture-only"); XCTFail("Expected a permission error") } catch { XCTAssertTrue(error.localizedDescription.contains("access")) }
    }
    func testSearchLimitIsExplicitInsteadOfSilentlyDroppingPRs() async throws {
        let fixture = GitHubTransportFixture([#"{"data":{"search":{"issueCount":1001,"pageInfo":{"hasNextPage":true,"endCursor":"next"},"nodes":[]}}}"#])
        let api = GitHubAPI(transport: { try await fixture.send($0) })
        do { _ = try await api.pulls(configuration: GitHubFolderConfiguration(), login: "test", token: "fixture-only"); XCTFail("Expected narrowing request") } catch { XCTAssertTrue(error.localizedDescription.contains("1,000")) }
    }
    func testCancelledRefreshMakesNoRequest() async throws {
        let fixture = GitHubTransportFixture([])
        let api = GitHubAPI(transport: { try await fixture.send($0) })
        let task = Task { withUnsafeCurrentTask { $0?.cancel() }; return try await api.pulls(configuration: GitHubFolderConfiguration(), login: "test", token: "fixture-only") }
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch { XCTAssertTrue(error is CancellationError) }
        let count = await fixture.requests.count; XCTAssertEqual(count, 0)
    }
}
