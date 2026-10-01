import Foundation
import UIKit

final class ClipboardHistory {
    static let shared = ClipboardHistory()
    private let defaults = UserDefaults.standard
    private let key = "milazy.clipboard.history.v1"
    private(set) var items: [String]

    private init() {
        items = defaults.stringArray(forKey: key) ?? []
    }

    func importSystemClipboard() {
        guard let text = UIPasteboard.general.string else { return }
        add(text)
    }

    func add(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items.removeAll { $0 == trimmed }
        items.insert(trimmed, at: 0)
        if items.count > 30 { items = Array(items.prefix(30)) }
        defaults.set(items, forKey: key)
    }

    func clear() {
        items.removeAll()
        defaults.removeObject(forKey: key)
    }
}
