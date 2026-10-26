import Foundation

public enum ToastPosition: String, Codable, CaseIterable {
    case topLeft = "top-left", topCenter = "top-center", topRight = "top-right"
    case bottomLeft = "bottom-left", bottomCenter = "bottom-center", bottomRight = "bottom-right"
    public var isTop: Bool { rawValue.hasPrefix("top") }
    public var isLeft: Bool { rawValue.hasSuffix("left") }
    public var isCenter: Bool { rawValue.hasSuffix("center") }
}

public struct NotificationPreferences: Codable, Equatable {
    public var position: ToastPosition = .topRight
    public var expanded = false
    public init() {}
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        position = (try? values.decode(ToastPosition.self, forKey: .position)) ?? .topRight
        expanded = (try? values.decode(Bool.self, forKey: .expanded)) ?? false
    }
}

public struct NotificationPreferencesRepository {
    public let fileURL: URL
    public init(fileURL: URL) { self.fileURL = fileURL }
    public func load() throws -> NotificationPreferences {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return NotificationPreferences() }
        return try JSONDecoder().decode(NotificationPreferences.self, from: Data(contentsOf: fileURL))
    }
    public func save(_ value: NotificationPreferences) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: fileURL, options: .atomic)
    }
}

public struct AavaToast: Identifiable, Equatable {
    public let id: UUID
    public let title: String
    public let detail: String
    public let scope: UUID
    public init(title: String, detail: String = "", scope: UUID) {
        id = UUID(); self.title = title; self.detail = detail; self.scope = scope
    }
}

public struct ToastQueue {
    public private(set) var items: [AavaToast] = []
    public init() {}
    public mutating func push(_ toast: AavaToast) {
        items.removeAll { $0.scope == toast.scope && $0.title == toast.title && $0.detail == toast.detail }
        items.insert(toast, at: 0)
        items = Array(items.prefix(3))
    }
    public mutating func remove(_ id: UUID) { items.removeAll { $0.id == id } }
    public mutating func clear() { items.removeAll() }
}
