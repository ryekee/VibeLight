import Foundation
import VibeBrokerCore

/// Source of truth for app-side settings. Non-secret values live in UserDefaults;
/// HA token lives in Keychain. Changes publish to subscribers via `onChange`.
@MainActor
final class SettingsStore: ObservableObject {
    // MARK: - Published settings

    @Published var haURL: String {
        didSet { defaults.set(haURL, forKey: Keys.haURL.rawValue); fire() }
    }
    @Published var haLightEntity: String {
        didSet { defaults.set(haLightEntity, forKey: Keys.haLightEntity.rawValue); fire() }
    }
    @Published var brokerPort: Int {
        didSet { defaults.set(brokerPort, forKey: Keys.brokerPort.rawValue); fire() }
    }
    @Published var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Keys.launchAtLogin.rawValue); fire() }
    }
    @Published var notifyOnHAError: Bool {
        didSet { defaults.set(notifyOnHAError, forKey: Keys.notifyOnHAError.rawValue); fire() }
    }
    @Published var defaultPauseSeconds: Int {
        didSet { defaults.set(defaultPauseSeconds, forKey: Keys.defaultPauseSeconds.rawValue); fire() }
    }
    @Published var renderMode: RenderMode {
        didSet { defaults.set(renderMode.rawValue, forKey: Keys.renderMode.rawValue); fire() }
    }
    @Published var colors: [VibeBrokerCore.State: ColorConfig] {
        didSet { persistColors(); fire() }
    }
    @Published var homeSSIDHint: String? {
        didSet { defaults.set(homeSSIDHint, forKey: Keys.homeSSIDHint.rawValue); fire() }
    }

    // MARK: - Token (Keychain-backed)

    var haToken: String? {
        get { KeychainHelper.get("haToken") }
        set {
            if let v = newValue, !v.isEmpty {
                KeychainHelper.set(v, for: "haToken")
            } else {
                KeychainHelper.delete(for: "haToken")
            }
            fire()
        }
    }

    // MARK: - Derived

    /// Settings considered "complete enough" to skip onboarding.
    var isConfigured: Bool {
        !haURL.isEmpty && !haLightEntity.isEmpty && (haToken?.isEmpty == false)
    }

    // MARK: - Change subscriptions

    var onChange: () -> Void = {}
    private func fire() { onChange() }

    // MARK: - Render mode

    enum RenderMode: String { case brokerEmulated, scenePack }

    // MARK: - Init

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.haURL = defaults.string(forKey: Keys.haURL.rawValue) ?? ""
        self.haLightEntity = defaults.string(forKey: Keys.haLightEntity.rawValue) ?? ""
        self.brokerPort = defaults.object(forKey: Keys.brokerPort.rawValue) as? Int ?? 17345
        self.launchAtLogin = defaults.object(forKey: Keys.launchAtLogin.rawValue) as? Bool ?? true
        self.notifyOnHAError = defaults.object(forKey: Keys.notifyOnHAError.rawValue) as? Bool ?? true
        self.defaultPauseSeconds = defaults.object(forKey: Keys.defaultPauseSeconds.rawValue) as? Int ?? 1800
        self.renderMode = RenderMode(rawValue: defaults.string(forKey: Keys.renderMode.rawValue) ?? "")
            ?? .brokerEmulated
        self.colors = Self.loadColors(defaults: defaults)
        self.homeSSIDHint = defaults.string(forKey: Keys.homeSSIDHint.rawValue)
    }

    private static func defaultColors() -> [VibeBrokerCore.State: ColorConfig] {
        [
            .idle:         ColorConfig(rgb: [80, 30, 120],  brightness: 80,  effect: .solid),
            .working:      ColorConfig(rgb: [40, 120, 255], brightness: 200, effect: .breathe),
            .compacting:   ColorConfig(rgb: [240, 220, 60], brightness: 200, effect: .breathe),
            .waitingInput: ColorConfig(rgb: [255, 140, 30], brightness: 220, effect: .blinkThenSolid),
            .needsAuth:    ColorConfig(rgb: [255, 30, 30],  brightness: 230, effect: .solid),
            .error:        ColorConfig(rgb: [255, 30, 30],  brightness: 230, effect: .blink),
            .done:         ColorConfig(rgb: [80, 30, 120],  brightness: 200, effect: .blink),
        ]
    }

    private static func loadColors(defaults: UserDefaults) -> [VibeBrokerCore.State: ColorConfig] {
        guard let data = defaults.data(forKey: Keys.colors.rawValue),
              let decoded = try? JSONDecoder().decode([String: ColorConfig].self, from: data) else {
            return defaultColors()
        }
        var result: [VibeBrokerCore.State: ColorConfig] = [:]
        for state in VibeBrokerCore.State.allCases {
            result[state] = decoded[state.serializedName] ?? defaultColors()[state]!
        }
        return result
    }

    private func persistColors() {
        var raw: [String: ColorConfig] = [:]
        for (state, color) in colors { raw[state.serializedName] = color }
        if let data = try? JSONEncoder().encode(raw) {
            defaults.set(data, forKey: Keys.colors.rawValue)
        }
    }

    func resetColors() {
        colors = Self.defaultColors()
    }

    func resetAll() {
        for key in Keys.allCases { defaults.removeObject(forKey: key.rawValue) }
        KeychainHelper.delete(for: "haToken")
        haURL = ""; haLightEntity = ""; brokerPort = 17345
        launchAtLogin = true; notifyOnHAError = true; defaultPauseSeconds = 1800
        renderMode = .brokerEmulated
        colors = Self.defaultColors()
        homeSSIDHint = nil
    }

    enum Keys: String, CaseIterable {
        case haURL              = "haURL"
        case haLightEntity      = "haLightEntity"
        case brokerPort         = "brokerPort"
        case launchAtLogin      = "launchAtLogin"
        case notifyOnHAError    = "notifyOnHAError"
        case defaultPauseSeconds = "defaultPauseSeconds"
        case renderMode         = "renderMode"
        case colors             = "colors"
        case homeSSIDHint       = "homeSSIDHint"
    }
}
