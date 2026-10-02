import UIKit

// One public-API touch receiver for the entire key surface. UIKit cannot reject
// an inferred gap/row-edge key or discard a second contact on the same button.
final class KeyCanvasView: UIView {
    private struct Contact {
        let key: TouchKey
        let title: String
        let start: CGPoint
        let frame: CGRect
        var hold: DispatchWorkItem?
    }
    private var candidates: [TouchResolver.Candidate] = []
    private var keys: [TouchKey] = []
    private var contacts: [AnyHashable: Contact] = [:]
    private var previewOwner: AnyHashable?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        accessibilityIdentifier = "milazy.keyCanvas"
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isMultipleTouchEnabled = true
    }

    func cacheLayout() {
        keys = subviews.compactMap { $0 as? TouchKey }
        candidates = keys.enumerated().map {
            TouchResolver.Candidate(id: $0.offset, frame: $0.element.frame,
                                    learningKey: $0.element.learningKey)
        }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01, isUserInteractionEnabled, bounds.contains(point)
        else { return nil }
        return self
    }

    // These are also exercised by integration tests with overlapping contacts.
    // Native event entry points below supply the identity of each UITouch.
    @discardableResult
    func beginContact(_ id: AnyHashable, at point: CGPoint) -> Bool {
        guard contacts[id] == nil, bounds.contains(point) else { return false }
        let hitbox = KeyboardPreferences.shared.hitboxMode
        guard let index = TouchResolver.resolve(point, candidates: candidates,
            expansion: CGSize(width: hitbox.expansionX, height: hitbox.expansionY)),
            keys.indices.contains(index), keys[index].isEnabled else { return false }
        let key = keys[index]
        let contact = Contact(key: key, title: key.currentTitle ?? "", start: point, frame: key.frame)
        contacts[id] = contact
        previewOwner = id
        // Commit first, before highlight, popup, learning, or hold scheduling.
        key.sendActions(for: .touchDown)
        // Layout/page actions can synchronously cancel and rebuild the keys.
        guard contacts[id] != nil else { return true }
        DispatchQueue.main.async { [weak self, weak key] in
            guard let self, let key, let current = self.contacts[id] else { return }
            key.isHighlighted = true
            if self.previewOwner == id { key.onFingerBegan?(key, current.title) }
        }
        if key.referenceRole == .delete {
            let hold = DispatchWorkItem { [weak self, weak key] in
                guard let self, let key, self.contacts[id] != nil else { return }
                key.onHoldBegan?()
            }
            contacts[id]?.hold = hold
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32, execute: hold)
        }
        return true
    }

    func moveContact(_ id: AnyHashable, to point: CGPoint) {
        guard let contact = contacts[id] else { return }
        if previewOwner == id {
            contact.key.onFingerMoved?(contact.key, point, contact.title)
        }
        if contact.key.referenceRole == .delete,
           !contact.frame.insetBy(dx: -12, dy: -12).contains(point) {
            contact.hold?.cancel()
            contact.key.onHoldEnded?()
        }
        // Movement never inserts or switches a character already committed.
    }

    func endContact(_ id: AnyHashable, cancelled: Bool = false) {
        guard let contact = contacts.removeValue(forKey: id) else { return }
        contact.hold?.cancel()
        if !contacts.values.contains(where: { $0.key === contact.key }) {
            contact.key.isHighlighted = false
            contact.key.onHoldEnded?()
        }
        if previewOwner == id {
            previewOwner = nil
            if cancelled { contact.key.onFingerCancelled?() }
            else { contact.key.onFingerEnded?(contact.key, contact.start, contact.title) }
        }
        if !cancelled, let key = contact.key.learningKey {
            TouchLearningModel.shared.record(key: key, point: contact.start, frame: contact.frame)
        }
    }

    func cancelAllContacts() {
        for id in Array(contacts.keys) { endContact(id, cancelled: true) }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Set iteration order is unspecified. Preserve chronological thumb input.
        let ordered = touches.sorted {
            if $0.timestamp != $1.timestamp { return $0.timestamp < $1.timestamp }
            let lhs = $0.location(in: self), rhs = $1.location(in: self)
            return lhs.x == rhs.x ? lhs.y < rhs.y : lhs.x < rhs.x
        }
        for touch in ordered { beginContact(ObjectIdentifier(touch), at: touch.location(in: self)) }
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { moveContact(ObjectIdentifier(touch), to: touch.location(in: self)) }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { endContact(ObjectIdentifier(touch)) }
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { endContact(ObjectIdentifier(touch), cancelled: true) }
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { cancelAllContacts() }
    }
}
