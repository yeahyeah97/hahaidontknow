import UIKit

final class TouchKey: UIButton {
    var referenceRole: KeyboardViewController.KeyRole = .normal
    var learningKey: String?
    var onFingerBegan: ((TouchKey, String) -> Void)?
    var onFingerMoved: ((TouchKey, CGPoint, String) -> Void)?
    var onFingerEnded: ((TouchKey, CGPoint, String) -> Void)?
    var onFingerCancelled: (() -> Void)?
    private var touchStartText: String = ""

    override var isHighlighted: Bool {
        didSet {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.alpha = self.isHighlighted ? 0.86 : 1
            }
        }
    }

    private var initialPoint: CGPoint?
    private var initialFrame: CGRect = .zero

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        touchStartText = currentTitle ?? ""
        initialPoint = superview.map { touch.location(in: $0) }
        initialFrame = frame
        let accepted = super.beginTracking(touch, with: event)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isTracking else { return }
            self.onFingerBegan?(self, self.touchStartText)
        }
        return accepted
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        let accepted = super.continueTracking(touch, with: event)
        if let container = superview {
            onFingerMoved?(self, touch.location(in: container), touchStartText)
        }
        return accepted
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        super.endTracking(touch, with: event)
        if let touch, let container = superview {
            onFingerEnded?(self, touch.location(in: container), touchStartText)
        } else { onFingerCancelled?() }
        if let point = initialPoint, let key = learningKey {
            TouchLearningModel.shared.record(key: key, point: point, frame: initialFrame)
        }
        initialPoint = nil
    }

    override func cancelTracking(with event: UIEvent?) {
        super.cancelTracking(with: event)
        initialPoint = nil
        onFingerCancelled?()
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let hitbox = KeyboardPreferences.shared.hitboxMode
        return bounds.insetBy(dx: -hitbox.expansionX, dy: -hitbox.expansionY).contains(point)
    }

    override func accessibilityActivate() -> Bool {
        sendActions(for: .touchDown)
        return true
    }

}

final class KeyPreviewView: UIView {
    private let label = UILabel()

    var text: String {
        get { label.text ?? "" }
        set { label.text = newValue }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = UIColor(white: 0.34, alpha: 1)
        layer.cornerRadius = 10
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.22
        layer.shadowRadius = 3
        layer.shadowOffset = CGSize(width: 0, height: 1)

        label.font = .systemFont(ofSize: 28, weight: .regular)
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            label.heightAnchor.constraint(equalToConstant: 35)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class KeyCanvasView: UIView {
    private var candidates: [TouchResolver.Candidate] = []
    private var keys: [TouchKey] = []

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
        let hitbox = KeyboardPreferences.shared.hitboxMode
        guard let id = TouchResolver.resolve(
            point, candidates: candidates,
            expansion: CGSize(width: hitbox.expansionX, height: hitbox.expansionY)
        ), keys.indices.contains(id) else { return super.hitTest(point, with: event) }
        return keys[id]
    }
}

