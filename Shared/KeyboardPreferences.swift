import Foundation

final class KeyboardPreferences {
    static let shared = KeyboardPreferences()
    private let defaults = UserDefaults.standard

    enum LanguageMode: String, CaseIterable {
        case automatic, italian, english
        var title: String {
            switch self {
            case .automatic: return "Auto IT/EN"
            case .italian: return "Italiano"
            case .english: return "English"
            }
        }
    }

    enum LayoutMode: String, CaseIterable {
        case ios, wide, compact
        var title: String {
            switch self {
            case .ios: return "iOS"
            case .wide: return "Wide"
            case .compact: return "Compact"
            }
        }
    }

    enum HitboxMode: String, CaseIterable {
        case normal, large, maximum
        var title: String {
            switch self {
            case .normal: return "Normal"
            case .large: return "Large"
            case .maximum: return "Max"
            }
        }
        var expansionX: CGFloat {
            switch self { case .normal: return 5.5; case .large: return 8.5; case .maximum: return 12.0 }
        }
        var expansionY: CGFloat {
            switch self { case .normal: return 6.0; case .large: return 9.0; case .maximum: return 12.0 }
        }
        var comfortBonus: CGFloat {
            switch self { case .normal: return 24; case .large: return 42; case .maximum: return 62 }
        }
    }

    var languageMode: LanguageMode {
        get { LanguageMode(rawValue: defaults.string(forKey: "milazy.pref.language") ?? "") ?? .automatic }
        set { defaults.set(newValue.rawValue, forKey: "milazy.pref.language") }
    }

    var layoutMode: LayoutMode {
        get { LayoutMode(rawValue: defaults.string(forKey: "milazy.pref.layout") ?? "") ?? .ios }
        set { defaults.set(newValue.rawValue, forKey: "milazy.pref.layout") }
    }

    var hitboxMode: HitboxMode {
        get { HitboxMode(rawValue: defaults.string(forKey: "milazy.pref.hitbox") ?? "") ?? .large }
        set { defaults.set(newValue.rawValue, forKey: "milazy.pref.hitbox") }
    }

    var keyPopups: Bool {
        get { defaults.object(forKey: "milazy.pref.popups") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "milazy.pref.popups") }
    }

    var haptics: Bool {
        get { defaults.object(forKey: "milazy.pref.haptics") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "milazy.pref.haptics") }
    }

    var sound: Bool {
        get { defaults.object(forKey: "milazy.pref.sound") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "milazy.pref.sound") }
    }

    private init() {}
}
