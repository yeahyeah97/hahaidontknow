import UIKit

// Built only as a simulator test application, never embedded in the IPA.
@main
final class TouchHarnessAppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = TouchHarnessController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}

private final class TouchHarnessController: UIViewController {
    private let proxy = TypingProxy("")
    private let keyboard = KeyboardViewController()
    private let output = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        proxy.autocapitalizationType = .none
        proxy.autocorrectionType = .no
        keyboard.testingProxy = proxy
        output.accessibilityIdentifier = "milazy.touchOutput"
        output.text = ""
        output.numberOfLines = 0
        output.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(output)
        addChild(keyboard)
        keyboard.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(keyboard.view)
        keyboard.didMove(toParent: self)
        NSLayoutConstraint.activate([
            output.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            output.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            output.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            keyboard.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboard.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keyboard.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            keyboard.view.heightAnchor.constraint(equalToConstant: 248)
        ])
        proxy.onInsert = { [weak self] in
            guard let self else { return }
            self.output.text = self.proxy.text
            self.output.accessibilityValue = self.proxy.text
        }
    }
}
