import Foundation

/// Keep these identifiers in one place.
/// If you change the bundle IDs in project.yml, change them here too.
enum ZGShared {
    static let appGroupID = "group.com.snilelife.zgreplayvisualoverlay"
    static let extensionBundleID = "com.snilelife.zgreplayvisualoverlay.broadcast"

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
}

struct OverlaySettings: Codable, Equatable {
    var predictionEnabled = true
    var keepLine = true
    var manualPocket = false
    var showSideLines = true
    var recordAnnotatedVideo = true
    var showDetectedBalls = true
    var showGhostBall = true
    var showMicrophoneButton = false
    /// Off by default because phone signers can change extension bundle IDs.
    /// Off = Apple shows the normal chooser, where the user selects "Z G Overlay Record".
    /// On = tries to open our extension directly by bundle ID.
    var directZGExtensionMode = false
    var lineLength: Double = 0.86
    var maxBounces: Int = 3
    var selectedPocket: Int = 1
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
        defaults.set(settings.predictionEnabled, forKey: "predictionEnabled")
        defaults.set(settings.keepLine, forKey: "keepLine")
        defaults.set(settings.manualPocket, forKey: "manualPocket")
        defaults.set(settings.showSideLines, forKey: "showSideLines")
        defaults.set(settings.recordAnnotatedVideo, forKey: "recordAnnotatedVideo")
        defaults.set(settings.showDetectedBalls, forKey: "showDetectedBalls")
        defaults.set(settings.showGhostBall, forKey: "showGhostBall")
        defaults.set(settings.showMicrophoneButton, forKey: "showMicrophoneButton")
        defaults.set(settings.directZGExtensionMode, forKey: "directZGExtensionMode")
        defaults.set(settings.lineLength, forKey: "lineLength")
        defaults.set(settings.maxBounces, forKey: "maxBounces")
        defaults.set(settings.selectedPocket, forKey: "selectedPocket")
        defaults.synchronize()
    }
}
