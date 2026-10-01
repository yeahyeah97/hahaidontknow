import UIKit
@main final class AppDelegate: UIResponder, UIApplicationDelegate {
 func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool { true }
 func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration { UISceneConfiguration(name: "Default", sessionRole: connectingSceneSession.role) }
}
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
 var window: UIWindow?
 func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
  guard let ws = scene as? UIWindowScene else { return }; let w = UIWindow(windowScene:ws); w.rootViewController = SetupViewController(); w.makeKeyAndVisible(); window = w
 }
}