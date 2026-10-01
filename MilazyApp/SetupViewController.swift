import UIKit
final class SetupViewController: UIViewController {
 override func viewDidLoad(){ super.viewDidLoad(); view.backgroundColor=.systemBackground
  let title=UILabel(); title.text="Milazy Keyboard"; title.font=.systemFont(ofSize:32,weight:.bold)
  let body=UILabel(); body.numberOfLines=0; body.text="Apple-like fast typing + AI Fix + More + Clipboard\n\n1. Settings → General → Keyboard → Keyboards\n2. Add New Keyboard → Milazy Keyboard\n3. Enable Allow Full Access for AI features.\n\nNormal typing stays local and does not wait for AI."
  let stack=UIStackView(arrangedSubviews:[title,body]); stack.axis=.vertical; stack.spacing=18; stack.translatesAutoresizingMaskIntoConstraints=false; view.addSubview(stack)
  NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:view.leadingAnchor,constant:28),stack.trailingAnchor.constraint(equalTo:view.trailingAnchor,constant:-28),stack.topAnchor.constraint(equalTo:view.safeAreaLayoutGuide.topAnchor,constant:42)])
 }
}