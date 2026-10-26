import Foundation

public struct OnboardingState: Codable, Equatable {
    public static let currentVersion = 1
    public static let stepCount = 7
    public var completedVersion: Int = 0
    public var step: Int = 0
    public init() {}
    public var needsPresentation: Bool { completedVersion < Self.currentVersion }
    public mutating func advance() { step = min(Self.stepCount - 1, max(0, step) + 1) }
    public mutating func back() { step = max(0, min(Self.stepCount - 1, step) - 1) }
    public mutating func complete() { completedVersion = Self.currentVersion; step = 0 }
    public mutating func replay() { step = 0 }
    public mutating func normalize() { step = min(Self.stepCount - 1, max(0, step)) }
}

public struct OnboardingRepository {
    public let fileURL: URL
    public init(fileURL: URL) { self.fileURL = fileURL }
    public func load() throws -> OnboardingState {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return OnboardingState() }
        var value = try JSONDecoder().decode(OnboardingState.self, from: Data(contentsOf: fileURL))
        value.normalize()
        return value
    }
    public func save(_ value: OnboardingState) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: fileURL, options: .atomic)
    }
}
