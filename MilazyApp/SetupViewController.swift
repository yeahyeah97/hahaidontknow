import UIKit

final class SetupViewController: UIViewController, UITextFieldDelegate {
    private let gradient = CAGradientLayer()

    override func viewDidLoad() {
        super.viewDidLoad()
        configureBackground()
        buildUI()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        gradient.frame = view.bounds
    }

    private func configureBackground() {
        view.backgroundColor = .black
        gradient.colors = [
            UIColor(red: 0.035, green: 0.025, blue: 0.055, alpha: 1).cgColor,
            UIColor(red: 0.070, green: 0.030, blue: 0.115, alpha: 1).cgColor,
            UIColor(red: 0.018, green: 0.018, blue: 0.022, alpha: 1).cgColor
        ]
        gradient.startPoint = CGPoint(x: 0.1, y: 0)
        gradient.endPoint = CGPoint(x: 0.9, y: 1)
        view.layer.insertSublayer(gradient, at: 0)
    }

    private func buildUI() {
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        view.addSubview(scroll)

        let content = UIStackView()
        content.axis = .vertical
        content.spacing = 14
        content.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(content)

        let icon = UILabel()
        icon.text = "⌨︎"
        icon.font = .systemFont(ofSize: 44, weight: .bold)
        icon.textAlignment = .center

        let title = UILabel()
        title.text = "Milazy Keyboard"
        title.font = .systemFont(ofSize: 34, weight: .bold)
        title.textColor = .white
        title.textAlignment = .center

        let version = UILabel()
        version.text = "3.1.0 · Adaptive Touch Engine"
        version.font = .systemFont(ofSize: 14, weight: .semibold)
        version.textColor = UIColor.white.withAlphaComponent(0.58)
        version.textAlignment = .center

        content.addArrangedSubview(icon)
        content.addArrangedSubview(title)
        content.addArrangedSubview(version)
        content.setCustomSpacing(24, after: version)

        let enableCard = makeCard(
            title: "Enable Milazy",
            body: "Settings → General → Keyboard → Keyboards → Add New Keyboard → Milazy Keyboard. Enable Full Access for Deaf AI, GIF providers and clipboard tools.",
            symbol: "keyboard"
        )

        let settingsButton = UIButton(type: .system)
        var config = UIButton.Configuration.filled()
        config.title = "Open iOS Settings"
        config.image = UIImage(systemName: "gearshape.fill")
        config.imagePadding = 8
        config.baseForegroundColor = .white
        config.baseBackgroundColor = UIColor(red: 0.48, green: 0.20, blue: 0.86, alpha: 1)
        config.cornerStyle = .large
        settingsButton.configuration = config
        settingsButton.heightAnchor.constraint(equalToConstant: 48).isActive = true
        settingsButton.addTarget(self, action: #selector(openSettings), for: .touchUpInside)
        enableCard.addArrangedSubview(settingsButton)
        content.addArrangedSubview(wrapCard(enableCard))

        let typing = makeCard(
            title: "Typing Engine",
            body: "Adaptive hitboxes, per-key touch learning, bilingual IT/EN correction, personal word memory, learned corrections, key popups, haptics and custom iOS/Wide/Compact layouts.",
            symbol: "sparkles"
        )
        content.addArrangedSubview(wrapCard(typing))

        let ai = makeCard(
            title: "Deaf AI",
            body: "Semantic Fix reconstructs fragmented meaning before grammar. Rewrite, Translate and Tone stay opt-in. Fast mode uses one request for normal text and deeper reasoning only when needed.",
            symbol: "brain.head.profile"
        )
        content.addArrangedSubview(wrapCard(ai))

        let tools = makeCard(
            title: "Keyboard Tools",
            body: "Use the grid button inside the keyboard for Emoji, GIF, Clipboard, Translator, language, layout, hitbox and settings. Deaf AI Fix stays on the left of the prediction bar.",
            symbol: "slider.horizontal.3"
        )
        content.addArrangedSubview(wrapCard(tools))

        let testTitle = UILabel()
        testTitle.text = "Test Milazy"
        testTitle.font = .systemFont(ofSize: 17, weight: .semibold)
        testTitle.textColor = .white

        let testField = UITextField()
        testField.backgroundColor = UIColor.white.withAlphaComponent(0.10)
        testField.textColor = .white
        testField.tintColor = UIColor(red: 0.64, green: 0.38, blue: 1.0, alpha: 1)
        testField.attributedPlaceholder = NSAttributedString(
            string: "Tap here, then hold 🌐 to choose Milazy",
            attributes: [.foregroundColor: UIColor.white.withAlphaComponent(0.42)]
        )
        testField.layer.cornerRadius = 13
        testField.layer.borderWidth = 1
        testField.layer.borderColor = UIColor.white.withAlphaComponent(0.10).cgColor
        testField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 1))
        testField.leftViewMode = .always
        testField.autocapitalizationType = .sentences
        testField.autocorrectionType = .yes
        testField.spellCheckingType = .yes
        testField.returnKeyType = .done
        testField.delegate = self
        testField.heightAnchor.constraint(equalToConstant: 52).isActive = true

        let testStack = UIStackView(arrangedSubviews: [testTitle, testField])
        testStack.axis = .vertical
        testStack.spacing = 10
        content.addArrangedSubview(wrapCard(testStack))

        let note = UILabel()
        note.text = "Typing stays local. Network access is used only when you explicitly use Deaf AI or GIF tools."
        note.font = .systemFont(ofSize: 12.5)
        note.textColor = UIColor.white.withAlphaComponent(0.45)
        note.textAlignment = .center
        note.numberOfLines = 0
        content.addArrangedSubview(note)

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 18),
            content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -18),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 24),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -28),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -36)
        ])
    }

    private func makeCard(title: String, body: String, symbol: String) -> UIStackView {
        let symbolView = UIImageView(image: UIImage(systemName: symbol))
        symbolView.tintColor = UIColor(red: 0.73, green: 0.50, blue: 1.0, alpha: 1)
        symbolView.contentMode = .scaleAspectFit
        symbolView.widthAnchor.constraint(equalToConstant: 28).isActive = true
        symbolView.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 19, weight: .semibold)
        titleLabel.textColor = .white

        let header = UIStackView(arrangedSubviews: [symbolView, titleLabel])
        header.axis = .horizontal
        header.spacing = 10
        header.alignment = .center

        let bodyLabel = UILabel()
        bodyLabel.text = body
        bodyLabel.font = .systemFont(ofSize: 14.5)
        bodyLabel.textColor = UIColor.white.withAlphaComponent(0.68)
        bodyLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [header, bodyLabel])
        stack.axis = .vertical
        stack.spacing = 10
        return stack
    }

    private func wrapCard(_ stack: UIStackView) -> UIView {
        let card = UIView()
        card.backgroundColor = UIColor.white.withAlphaComponent(0.075)
        card.layer.cornerRadius = 20
        card.layer.borderWidth = 1
        card.layer.borderColor = UIColor.white.withAlphaComponent(0.08).cgColor

        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])
        return card
    }

    @objc private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
