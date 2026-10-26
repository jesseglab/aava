import XCTest
@testable import AavaCore

final class GitHubFolderTests: XCTestCase {
    func testRepositoryFilterRejectsSearchInjection() {
        XCTAssertTrue(GitHubFolderConfiguration.validRepository("geeklab/aava"))
        XCTAssertFalse(GitHubFolderConfiguration.validRepository("owner/repo is:closed"))
        XCTAssertFalse(GitHubFolderConfiguration.validRepository("https://github.com/owner/repo"))
        var config = GitHubFolderConfiguration(); config.repositories = ["owner/repo"]
        XCTAssertEqual(config.query(login: "jay"), "is:pr is:open sort:updated-desc author:jay repo:owner/repo")
        config.filter = .reviewRequested
        XCTAssertTrue(config.query(login: "jay").contains("review-requested:jay"))
    }
    func testStatusNeverClaimsSuccessForMissingChecks() {
        XCTAssertEqual(GitHubPRStatus.resolve(draft: false, checks: nil, review: "APPROVED", mergeable: "MERGEABLE"), .unknown)
        XCTAssertEqual(GitHubPRStatus.resolve(draft: false, checks: "SUCCESS", review: "CHANGES_REQUESTED", mergeable: nil), .failed)
        XCTAssertEqual(GitHubPRStatus.resolve(draft: false, checks: "SUCCESS", review: "APPROVED", mergeable: "CONFLICTING"), .failed)
        XCTAssertEqual(GitHubPRStatus.resolve(draft: true, checks: "SUCCESS", review: nil, mergeable: nil), .draft)
        XCTAssertEqual(GitHubPRStatus.resolve(draft: false, checks: "PENDING", review: nil, mergeable: nil), .pending)
        XCTAssertEqual(GitHubPRStatus.resolve(draft: false, checks: "SUCCESS", review: "REVIEW_REQUIRED", mergeable: nil), .review)
        XCTAssertEqual(GitHubPRStatus.resolve(draft: false, checks: "SUCCESS", review: "APPROVED", mergeable: "MERGEABLE"), .approved)
    }
    func testRepositorySummaryKeepsFailuresAndUnknownVisible() {
        XCTAssertEqual(GitHubPRStatus.aggregate([.approved, .failed, .pending]), .failed)
        XCTAssertEqual(GitHubPRStatus.aggregate([.approved, .unknown]), .unknown)
        XCTAssertEqual(GitHubPRStatus.aggregate([]), .unknown)
    }
    func testGraphQLMappingPreservesRepoURLAndStatus() throws {
        let json = #"{"data":{"search":{"issueCount":1,"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"id":"PR_1","number":42,"title":"Fix sidebar","url":"https://github.com/geeklab/aava/pull/42","isDraft":false,"reviewDecision":"APPROVED","mergeable":"MERGEABLE","repository":{"nameWithOwner":"geeklab/aava"},"commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"SUCCESS"}}}]}}]}}}"#
        let response = try JSONDecoder().decode(GitHubSearchPage.self, from: Data(json.utf8))
        let pr = try XCTUnwrap(response.data?.search.nodes.first??.item)
        XCTAssertEqual(pr.repository, "geeklab/aava"); XCTAssertEqual(pr.number, 42); XCTAssertEqual(pr.status, .approved)
    }
}
