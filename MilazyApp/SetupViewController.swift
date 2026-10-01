import UIKit

final class SetupViewController: UIViewController, UITextFieldDelegate {
    private let statusLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let title = UILabel()
        title.text = "Milazy Keyboard"
        title.font = .systemFont(ofSize: 34, weight: .bold)
        title.textAlignment = .center

        let subtitle = UILabel()
        subtitle.text = "Enable it once, then use it anywhere."
        subtitle.font = .systemFont(ofSize: 17, weight: .medium)
        subtitle.textColor = .secondaryLabel
        subtitle.textAlignment = .center

        let steps = UILabel()
        steps.numberOfLines = 0
        steps.font = .systemFont(ofSize: 17)
        steps.text = """
        1. Open Settings
        2. General → Keyboard → Keyboards
        3. Add New Keyboard…
        4. Choose Milazy Keyboard
        5. Tap Milazy Keyboard again
        6. Enable Allow Full Access for Fix / Rewrite / Translate / Tone

        Normal typing itself stays local.
        """

        let settingsButton = UIButton(type: .system)
        settingsButton.configuration = .filled()
        settingsButton.configuration?.title = "Open Settings"
        settingsButton.addTarget(self, action: #selector(openSettings), for: .touchUpInside)

        statusLabel.numberOfLines = 0
        statusLabel.text = "After enabling Milazy, tap the field below and hold 🌐 to select it."
        statusLabel.font = .systemFont(ofSize: 15)
        statusLabel.textColor = .secondaryLabel

        let testField = UITextField()
        testField.borderStyle = .roundedRect
        testField.placeholder = "Tap here to test Milazy Keyboard"
        testField.autocapitalizationType = .sentences
        testField.autocorrectionType = .yes
        testField.spellCheckingType = .yes
        testField.returnKeyType = .done
        testField.delegate = self
        testField.heightAnchor.constraint(equalToConstant: 48).isActive = true

        let stack = UIStackView(arrangedSubviews: [
            title, subtitle, steps, settingsButton, statusLabel, testField
        ])
        stack.axis = .vertical
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 30)
        ])
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
