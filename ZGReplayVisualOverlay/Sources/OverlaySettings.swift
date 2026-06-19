import Foundation
import UIKit

/// Keep these identifiers in one place.
/// If you change the bundle IDs in project.yml, change them here too.
enum ZGShared {
    static let appGroupID = "group.com.snilelife.zgreplayvisualoverlay"
    static let extensionBundleID = "com.snilelife.zgreplayvisualoverlay.broadcast"
    static let pasteboardName = "com.snilelife.zgreplayvisualoverlay.shared"
    static let pasteboardOverlayKey = "zg_overlay_state_json"
    static let pasteboardPreviewKey = "zg_preview_frame_jpeg"
    static let pasteboardPreviewTimestampKey = "zg_preview_frame_timestamp"
    /// Optional fallback bridge when App Group signing is broken.
    /// Example: "https://your-zg-relay.onrender.com"
    static let relayBaseURL = ""
    static let relayStreamKey = "zg-default"

    static var mainBundleID: String {
        Bundle.main.bundleIdentifier ?? "unknown"
    }

    static func sharedDefaults() -> UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static func sharedContainerURL() -> URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            return url
        }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var appGroupReady: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) != nil
    }

    static var sharedPasteboard: UIPasteboard? {
        UIPasteboard(name: UIPasteboard.Name(pasteboardName), create: true)
    }

    static var expectedExtensionURL: URL? {
        Bundle.main.builtInPlugInsURL?.appendingPathComponent("ZGReplayVisualOverlayBroadcast.appex")
    }

    static var broadcastExtensionEmbedded: Bool {
        guard let url = expectedExtensionURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    static var broadcastExtensionDisplayName: String {
        guard let url = expectedExtensionURL,
              let bundle = Bundle(url: url),
              let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String else {
            return "not found"
        }
        return name
    }
}

struct OverlaySettings: Codable, Equatable {
    var scannerEnabled = true
    var holdScanResult = true
    var predictionEnabled = true
    var keepLine = true
    var manualPocket = false
    var showSideLines = true
    var recordAnnotatedVideo = true
    var showDetectedBalls = true
    var showGhostBall = true
    var fastScanMode = true
    var showMicrophoneButton = false
    /// On by default so the blue button tries to open this broadcast extension directly.
    /// If the button appears dead, turn this off to show Apple's full chooser and verify whether the extension is listed.
    var directZGExtensionMode = true
    var lineLength: Double = 0.86
    var holdScanSeconds: Double = 8.0
    var maxBounces: Int = 3
    var selectedPocket: Int = 1
    var scanRoute: Int = 0
    var predictionStyle: Int = 1
}

final class OverlaySettingsStore: ObservableObject {
    @Published var settings: OverlaySettings

    private let defaults: UserDefaults
    private let key = "ZGOverlaySettings"

    init(defaults: UserDefaults = ZGShared.sharedDefaults()) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(OverlaySettings.self, from: data) {
            settings = decoded
        } else {
            settings = OverlaySettings()
        }
        save()
    }

    func save() {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: key)
        }
        defaults.set(settings.scannerEnabled, forKey: "scannerEnabled")
        defaults.set(settings.holdScanResult, forKey: "holdScanResult")
        defaults.set(settings.predictionEnabled, forKey: "predictionEnabled")
        defaults.set(settings.keepLine, forKey: "keepLine")
        defaults.set(settings.manualPocket, forKey: "manualPocket")
        defaults.set(settings.showSideLines, forKey: "showSideLines")
        defaults.set(settings.recordAnnotatedVideo, forKey: "recordAnnotatedVideo")
        defaults.set(settings.showDetectedBalls, forKey: "showDetectedBalls")
        defaults.set(settings.showGhostBall, forKey: "showGhostBall")
        defaults.set(settings.fastScanMode, forKey: "fastScanMode")
        defaults.set(settings.showMicrophoneButton, forKey: "showMicrophoneButton")
        defaults.set(settings.directZGExtensionMode, forKey: "directZGExtensionMode")
        defaults.set(settings.lineLength, forKey: "lineLength")
        defaults.set(settings.holdScanSeconds, forKey: "holdScanSeconds")
        defaults.set(settings.maxBounces, forKey: "maxBounces")
        defaults.set(settings.selectedPocket, forKey: "selectedPocket")
        defaults.set(settings.scanRoute, forKey: "scanRoute")
        defaults.set(settings.predictionStyle, forKey: "predictionStyle")
        defaults.synchronize()
    }
}
