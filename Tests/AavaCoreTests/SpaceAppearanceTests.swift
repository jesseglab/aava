import XCTest
import CoreGraphics
import ImageIO
@testable import AavaCore

final class SpaceAppearanceTests: XCTestCase {
    func testTenDistinctNaturePresetsAndExactColorRoundTrips() {
        XCTAssertEqual(SpacePreset.all.count, 10)
        XCTAssertEqual(Set(SpacePreset.all.map(\.id)).count, 10)
        for hex in SpacePreset.all.flatMap({ [$0.theme.top, $0.theme.bottom] }) + ["000000", "FFFFFF", "FF0000", "00FF00", "0000FF", "808080"] {
            XCTAssertEqual(WheelColor(hex: hex).hex, hex)
        }
    }
    func testWheelWrapAndAppearanceBounds() {
        XCTAssertEqual(WheelColor(hue: 1, saturation: 1, brightness: 1).hex, "FF0000")
        XCTAssertEqual(WheelColor(hue: -1, saturation: 1, brightness: 1).hex, "FF0000")
        XCTAssertEqual(SpaceAppearance(transparency: 2, noise: -1).safeTransparency, 0.85)
        XCTAssertEqual(SpaceAppearance(transparency: 2, noise: -1).safeNoise, 0)
        XCTAssertEqual(SpaceAppearance(transparency: .nan, noise: .infinity).safeTransparency, 0)
        XCTAssertEqual(SpaceAppearance(transparency: .nan, noise: .infinity).safeNoise, 0)
    }
    func testAppearanceAndPrivacyPreferencesRemainPerSpace() throws {
        var state = BrowserState()
        state.spaces[0].appearance = SpaceAppearance(transparency: 0.4, noise: 0.25)
        state.spaces[0].privacy = PrivateSpaceSettings(idleMinutes: 30, stayOn: true)
        let loaded = try JSONDecoder().decode(BrowserState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(loaded.spaces[0].appearance?.safeNoise, 0.25)
        XCTAssertNil(loaded.spaces[1].appearance)
        XCTAssertEqual(loaded.spaces[0].privacy?.stayOn, true)
        XCTAssertFalse(PrivateSpacePolicy().isUnlocked(loaded.spaces[0].id, now: Date()))
    }
    func testLegacyPrivacyWithoutStayOnDecodesLocked() throws {
        let settings = try JSONDecoder().decode(PrivateSpaceSettings.self, from: Data(#"{"idleMinutes":30}"#.utf8))
        XCTAssertNil(settings.stayOn)
        XCTAssertEqual(settings.idleMinutes, 30)
    }
    func testUpdatedGrantChangesLeavingBehaviorWithoutAffectingOtherSpace() {
        let a = UUID(), b = UUID(), now = Date()
        var policy = PrivateSpacePolicy()
        policy.unlock(a, stayOn: false, minutes: 15, now: now)
        policy.unlock(b, stayOn: true, minutes: 60, now: now)
        policy.unlock(a, stayOn: true, minutes: 30, now: now)
        policy.leave(a)
        XCTAssertTrue(policy.isUnlocked(a, now: now.addingTimeInterval(20 * 60)))
        XCTAssertFalse(policy.isUnlocked(a, now: now.addingTimeInterval(30 * 60)))
        XCTAssertTrue(policy.isUnlocked(b, now: now.addingTimeInterval(30 * 60)))
    }
    func testBackgroundFilenamesCannotEscapeProfileDirectory() {
        let root = URL(fileURLWithPath: "/tmp/aava-test")
        let repo = BackgroundRepository(root: root), profile = UUID()
        XCTAssertNil(repo.url(for: BackgroundAsset(filename: "../../secret.png", displayName: "", animated: false), profile: profile))
        XCTAssertNil(repo.url(for: BackgroundAsset(filename: UUID().uuidString + ".html", displayName: "", animated: false), profile: profile))
        let asset = BackgroundAsset(filename: UUID().uuidString + ".png", displayName: "", animated: false)
        XCTAssertEqual(repo.url(for: asset, profile: profile)?.deletingLastPathComponent().lastPathComponent, profile.uuidString)
    }
    func testValidImageCopiesIndependentlyAndRejectsNonImageData() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = BackgroundRepository(root: root), a = UUID(), b = UUID()
        let data = try imageData(gif: false)
        let first = try repository.importData(data, name: "Sample.png", profile: a)
        let second = try repository.importData(data, name: "Sample.png", profile: b)
        XCTAssertFalse(first.animated)
        XCTAssertNotEqual(repository.url(for: first, profile: a), repository.url(for: second, profile: b))
        XCTAssertEqual(try Data(contentsOf: repository.url(for: first, profile: a)!), data)
        XCTAssertThrowsError(try repository.importData(Data("not an image".utf8), name: "fake.gif", profile: a))
        repository.remove(first, profile: a)
        XCTAssertTrue(FileManager.default.fileExists(atPath: repository.url(for: second, profile: b)!.path))
    }
    func testAnimatedGIFKeepsItsFramesOnImport() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = BackgroundRepository(root: root), profile = UUID(), data = try imageData(gif: true)
        let asset = try repository.importData(data, name: "Waves.gif", profile: profile)
        XCTAssertTrue(asset.animated)
        let file = try XCTUnwrap(repository.url(for: asset, profile: profile))
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(file as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetCount(source), 2)
    }
    private func imageData(gif: Bool) throws -> Data {
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, (gif ? "com.compuserve.gif" : "public.png") as CFString, gif ? 2 : 1, nil))
        for index in 0..<(gif ? 2 : 1) {
            let context = try XCTUnwrap(CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 64, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(CGColor(red: CGFloat(index), green: 0.5, blue: 0.7, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
            CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.15]] as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination)); return data as Data
    }
}
