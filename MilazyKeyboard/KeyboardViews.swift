import UIKit

final class TouchKey: UIButton {
    var referenceRole: KeyboardViewController.KeyRole = .normal
    var learningKey: String?
    var onFingerBegan: ((TouchKey, String) -> Void)?
    var onFingerMoved: ((TouchKey, CGPoint, String) -> Void)?
    var onFingerEnded: ((TouchKey, CGPoint, String) -> Void)?
    var onFingerCancelled: (() -> Void)?
    var onHoldBegan: (() -> Void)?
    var onHoldEnded: (() -> Void)?

    override var isHighlighted: Bool {
        didSet {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.alpha = self.isHighlighted ? 0.86 : 1
            }
        }
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


