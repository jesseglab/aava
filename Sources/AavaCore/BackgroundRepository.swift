import Foundation
import ImageIO

public struct BackgroundRepository {
    public let root: URL
    public init(root: URL) { self.root = root }
    public enum Failure: LocalizedError {
        case invalid, tooLarge
        public var errorDescription: String? {
            switch self {
            case .invalid: return "Choose a PNG, JPEG, HEIC, WebP, TIFF or GIF image."
            case .tooLarge: return "Choose an image under 32 MB and 8,192 pixels per side, with no more than 600 GIF frames."
            }
        }
    }
    public func url(for asset: BackgroundAsset, profile: UUID) -> URL? {
        guard asset.validFilename else { return nil }
        return root.appendingPathComponent(profile.uuidString, isDirectory: true).appendingPathComponent(asset.filename)
    }
    public func importFile(_ file: URL, profile: UUID) throws -> BackgroundAsset {
        guard file.isFileURL else { throw Failure.invalid }
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw Failure.invalid }
        guard (values.fileSize ?? Int.max) <= 32 * 1024 * 1024 else { throw Failure.tooLarge }
        return try importData(Data(contentsOf: file, options: .mappedIfSafe), name: file.lastPathComponent, profile: profile)
    }
    public func importData(_ data: Data, name: String, profile: UUID) throws -> BackgroundAsset {
        guard data.count <= 32 * 1024 * 1024 else { throw Failure.tooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let kind = CGImageSourceGetType(source) as String? else { throw Failure.invalid }
        let extensions = ["public.png": "png", "public.jpeg": "jpg", "public.heic": "heic", "org.webmproject.webp": "webp", "public.tiff": "tiff", "com.compuserve.gif": "gif"]
        guard let ext = extensions[kind] else { throw Failure.invalid }
        let count = CGImageSourceGetCount(source)
        guard count > 0, count <= 600 else { throw Failure.tooLarge }
        for index in 0..<count {
            guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
                  let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int,
                  w > 0, h > 0, w <= 8192, h <= 8192 else { throw Failure.tooLarge }
        }
        guard CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 64, kCGImageSourceShouldCache: false] as CFDictionary) != nil else { throw Failure.invalid }
        let asset = BackgroundAsset(filename: UUID().uuidString + "." + ext, displayName: String(name.prefix(160)), animated: ext == "gif" && count > 1)
        let destination = url(for: asset, profile: profile)!
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: destination, options: [.atomic, .completeFileProtectionUnlessOpen])
        return asset
    }
    public func remove(_ asset: BackgroundAsset, profile: UUID) {
        if let file = url(for: asset, profile: profile) { try? FileManager.default.removeItem(at: file) }
    }
}
