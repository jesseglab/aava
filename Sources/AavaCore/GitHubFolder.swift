import Foundation

public enum GitHubPRFilter: String, Codable, CaseIterable, Sendable {
    case authored, reviewRequested, assigned, repository
    public var title: String { switch self { case .authored: return "My open PRs"; case .reviewRequested: return "Review requested"; case .assigned: return "Assigned to me"; case .repository: return "All PRs in repositories" } }
}
public struct GitHubFolderConfiguration: Codable, Equatable, Sendable {
    public var enabled = true
    public var filter: GitHubPRFilter = .authored
    public var repositories: [String] = []
    public var collapsedRepositories: Set<String> = []
    public init() {}
    public func query(login: String) -> String {
        var parts = ["is:pr", "is:open", "sort:updated-desc"]
        switch filter { case .authored: parts.append("author:" + login); case .reviewRequested: parts.append("review-requested:" + login); case .assigned: parts.append("assignee:" + login); case .repository: break }
        parts += repositories.map { "repo:" + $0 }
        return parts.joined(separator: " ")
    }
    public static func validRepository(_ text: String) -> Bool {
        text.range(of: "^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", options: .regularExpression) != nil
    }
}
public enum GitHubPRStatus: String, Codable, Sendable, CaseIterable {
    case failed, pending, review, approved, draft, unknown
    public var title: String { switch self { case .failed: return "Needs attention"; case .pending: return "Checks running"; case .review: return "Awaiting review"; case .approved: return "Checks passed"; case .draft: return "Draft"; case .unknown: return "Status unavailable" } }
    public static func resolve(draft: Bool, checks: String?, review: String?, mergeable: String?) -> Self {
        if checks == "FAILURE" || checks == "ERROR" || review == "CHANGES_REQUESTED" || mergeable == "CONFLICTING" { return .failed }
        if draft { return .draft }
        if checks == "PENDING" || checks == "EXPECTED" { return .pending }
        if checks == nil { return .unknown }
        if review == "REVIEW_REQUIRED" { return .review }
        return checks == "SUCCESS" ? .approved : .unknown
    }
    public static func aggregate(_ values: [Self]) -> Self {
        for status in [Self.failed, .pending, .unknown, .review, .draft, .approved] where values.contains(status) { return status }
        return .unknown
    }
}
public struct GitHubPullRequest: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var number: Int
    public var title: String
    public var url: URL
    public var repository: String
    public var status: GitHubPRStatus
    public init(id: String, number: Int, title: String, url: URL, repository: String, status: GitHubPRStatus) { self.id = id; self.number = number; self.title = title; self.url = url; self.repository = repository; self.status = status }
}
public struct GitHubSearchPage: Decodable {
    public struct Payload: Decodable { public var search: Search }
    public struct Search: Decodable {
        public var issueCount: Int
        public var pageInfo: PageInfo
        public var nodes: [Node?]
    }
    public struct PageInfo: Decodable { public var hasNextPage: Bool; public var endCursor: String? }
    public struct Node: Decodable {
        public var id: String; public var number: Int; public var title: String; public var url: URL
        public var isDraft: Bool; public var reviewDecision: String?; public var mergeable: String?
        public var repository: Repository; public var commits: Commits
        public struct Repository: Decodable { public var nameWithOwner: String }
        public struct Commits: Decodable {
            public var nodes: [CommitNode]
            public struct CommitNode: Decodable {
                public var commit: Commit
                public struct Commit: Decodable { public var statusCheckRollup: Rollup?; public struct Rollup: Decodable { public var state: String } }
            }
        }
        public var item: GitHubPullRequest {
            GitHubPullRequest(id: id, number: number, title: title, url: url, repository: repository.nameWithOwner,
                              status: .resolve(draft: isDraft, checks: commits.nodes.last?.commit.statusCheckRollup?.state, review: reviewDecision, mergeable: mergeable))
        }
    }
    public var data: Payload?
    public var errors: [ErrorMessage]?
    public struct ErrorMessage: Decodable { public var message: String }
}
