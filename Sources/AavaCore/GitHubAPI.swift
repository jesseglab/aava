import Foundation

public enum GitHubFailure: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
private final class GitHubRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
public struct GitHubAPI {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private let transport: Transport
    public init(transport: @escaping Transport = GitHubAPI.send) { self.transport = transport }
    public static func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil; configuration.urlCache = nil; configuration.urlCredentialStorage = nil
        let session = URLSession(configuration: configuration, delegate: GitHubRedirectPolicy(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return try await session.data(for: request)
    }
    private func request(query: String, variables: [String: Any] = [:], token: String) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://api.github.com/graphql")!)
        request.httpMethod = "POST"; request.timeoutInterval = 30
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Aava", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])
        let (data, response) = try await transport(request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw GitHubFailure.message(status == 401 ? "GitHub rejected the connection. Replace the token in this space." : status == 403 || status == 429 ? "GitHub access is limited or rate-limited. Check repository access, then refresh later." : "GitHub is unavailable. Your last results are kept.")
        }
        return data
    }
    public func login(token: String) async throws -> String {
        struct Response: Decodable { struct Payload: Decodable { struct Viewer: Decodable { let login: String }; let viewer: Viewer }; let data: Payload? }
        let data = try await request(query: "query { viewer { login } }", token: token)
        guard let login = try JSONDecoder().decode(Response.self, from: data).data?.viewer.login else { throw GitHubFailure.message("GitHub couldn’t verify this connection. Check your token’s access.") }
        return login
    }
    public func pulls(configuration: GitHubFolderConfiguration, login: String, token: String) async throws -> [GitHubPullRequest] {
        let query = """
        query($query: String!, $cursor: String) {
          search(query: $query, type: ISSUE, first: 100, after: $cursor) {
            issueCount pageInfo { hasNextPage endCursor }
            nodes { ... on PullRequest {
              id number title url isDraft reviewDecision mergeable repository { nameWithOwner }
              commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
            } }
          }
        }
        """
        var cursor: String?, results: [GitHubPullRequest] = []
        for _ in 0..<10 {
            try Task.checkCancellation()
            var variables: [String: Any] = ["query": configuration.query(login: login)]
            if let cursor { variables["cursor"] = cursor }
            let data = try await request(query: query, variables: variables, token: token)
            let response = try JSONDecoder().decode(GitHubSearchPage.self, from: data)
            guard response.errors?.isEmpty != false, let search = response.data?.search else { throw GitHubFailure.message("GitHub couldn’t read PRs or their checks. Check this token’s repository and status-check access. Last results are kept.") }
            guard search.issueCount <= 1000 else { throw GitHubFailure.message("More than 1,000 PRs match. Narrow the repository filter to show a complete folder.") }
            results += search.nodes.compactMap { $0?.item }.filter { $0.url.scheme == "https" && $0.url.host == "github.com" }
            if !search.pageInfo.hasNextPage { return results }
            guard let next = search.pageInfo.endCursor, next != cursor else { throw GitHubFailure.message("GitHub returned an incomplete page. Refresh to try again.") }
            cursor = next
        }
        throw GitHubFailure.message("Too many PR pages. Narrow the repository filter.")
    }
}
