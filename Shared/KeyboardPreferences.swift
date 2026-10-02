import Foundation

final class KeyboardPreferences {
    static let shared = KeyboardPreferences()
    private let defaults = UserDefaults.standard
    private var cached: [String: Any] = [:]

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
        get { LanguageMode(rawValue: cached["milazy.pref.language"] as? String ?? "") ?? .automatic }
        set { cached["milazy.pref.language"] = newValue.rawValue; defaults.set(newValue.rawValue, forKey: "milazy.pref.language") }
    }

    var layoutMode: LayoutMode {
        get { LayoutMode(rawValue: cached["milazy.pref.layout"] as? String ?? "") ?? .ios }
        set { cached["milazy.pref.layout"] = newValue.rawValue; defaults.set(newValue.rawValue, forKey: "milazy.pref.layout") }
    }

    var hitboxMode: HitboxMode {
        get { HitboxMode(rawValue: cached["milazy.pref.hitbox"] as? String ?? "") ?? .large }
        set { cached["milazy.pref.hitbox"] = newValue.rawValue; defaults.set(newValue.rawValue, forKey: "milazy.pref.hitbox") }
    }

    var keyPopups: Bool {
        get { cached["milazy.pref.popups"] as? Bool ?? true }
        set { cached["milazy.pref.popups"] = newValue; defaults.set(newValue, forKey: "milazy.pref.popups") }
    }

    var haptics: Bool {
        get { cached["milazy.pref.haptics"] as? Bool ?? true }
        set { cached["milazy.pref.haptics"] = newValue; defaults.set(newValue, forKey: "milazy.pref.haptics") }
    }

    var sound: Bool {
        get { cached["milazy.pref.sound"] as? Bool ?? true }
        set { cached["milazy.pref.sound"] = newValue; defaults.set(newValue, forKey: "milazy.pref.sound") }
    }

    private init() {
        for key in ["language", "layout", "hitbox", "popups", "haptics", "sound"] {
            cached["milazy.pref." + key] = defaults.object(forKey: "milazy.pref." + key)
        }
    }
}

