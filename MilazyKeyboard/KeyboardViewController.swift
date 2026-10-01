import UIKit

final class KeyboardViewController: UIInputViewController {
 private let root = UIStackView(); private let toolbar = UIStackView(); private let keys = UIStackView()
 private var shift = true
 private let rows = [Array("QWERTYUIOP"),Array("ASDFGHJKL"),Array("ZXCVBNM")]
 override func viewDidLoad(){ super.viewDidLoad(); build(); updateAppearance() }
 override func textDidChange(_ textInput: UITextInput?){ super.textDidChange(textInput); updateAppearance() }
 private func build(){
  root.axis = .vertical; root.spacing = 7; root.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(root)
  NSLayoutConstraint.activate([root.leadingAnchor.constraint(equalTo:view.leadingAnchor,constant:4),root.trailingAnchor.constraint(equalTo:view.trailingAnchor,constant:-4),root.topAnchor.constraint(equalTo:view.topAnchor,constant:5),root.bottomAnchor.constraint(equalTo:view.bottomAnchor,constant:-5)])
  toolbar.axis = .horizontal; toolbar.spacing = 6; toolbar.distribution = .fillEqually
  [tool("Fix",#selector(fix)),tool("More",#selector(more)),tool("Clipboard",#selector(clipboard))].forEach{toolbar.addArrangedSubview($0)}; root.addArrangedSubview(toolbar)
  keys.axis = .vertical; keys.spacing = 7; keys.distribution = .fillEqually; root.addArrangedSubview(keys)
  for (idx,row) in rows.enumerated(){ let s = UIStackView(); s.axis = .horizontal;s.spacing = 5;s.distribution = .fillEqually
   if idx==2{s.addArrangedSubview(key("⇧",#selector(toggleShift)))}
   row.forEach{ s.addArrangedSubview(key(String($0),#selector(letter(_:)))) }
   if idx==2{s.addArrangedSubview(key("⌫",#selector(backspace)))}; keys.addArrangedSubview(s)
  }
  let bottom = UIStackView();bottom.axis = .horizontal;bottom.spacing = 5
  let globe = key("🌐",#selector(nextKeyboard)); globe.widthAnchor.constraint(equalToConstant:46).isActive = true
  let nums = key("123",#selector(numbers)); nums.widthAnchor.constraint(equalToConstant:54).isActive = true
  let space = key("space",#selector(space)); let ret = key("return",#selector(enter)); ret.widthAnchor.constraint(equalToConstant:78).isActive = true
  [nums,globe,space,ret].forEach{bottom.addArrangedSubview($0)}; root.addArrangedSubview(bottom)
 }
 private func key(_ title:String,_ action:Selector)->UIButton{ let b = TouchKey(type:.system); b.setTitle(title,for:.normal); b.titleLabel?.font = .systemFont(ofSize:title.count==1 ? 21:16); b.addTarget(self,action:action,for:.touchDown); b.layer.cornerRadius = 5; return b }
 private func tool(_ title:String,_ action:Selector)->UIButton{ let b = UIButton(type:.system);b.setTitle(title,for:.normal);b.titleLabel?.font = .systemFont(ofSize:15,weight:.semibold);b.addTarget(self,action:action,for:.touchUpInside);b.heightAnchor.constraint(equalToConstant:36).isActive = true;return b }
 private func updateAppearance(){ let dark = textDocumentProxy.keyboardAppearance == .dark || traitCollection.userInterfaceStyle == .dark; view.backgroundColor = dark ? UIColor(white:0.12,alpha:1):UIColor(red:0.82,green:0.83,blue:0.85,alpha:1)
  for case let b as UIButton in allSubviews(view){ if b.superview !== toolbar {b.backgroundColor = dark ? UIColor(white:0.27,alpha:1):.white;b.setTitleColor(dark ? .white:.black,for:.normal)} }
 }
 private func allSubviews(_ v:UIView)->[UIView]{v.subviews+v.subviews.flatMap(allSubviews)}
 @objc private func letter(_ sender:UIButton){ guard let t = sender.currentTitle else{return}; textDocumentProxy.insertText(shift ? t:t.lowercased()); if shift {shift = false} }
 @objc private func backspace(){textDocumentProxy.deleteBackward()}
 @objc private func space(){textDocumentProxy.insertText(" ")}
 @objc private func enter(){textDocumentProxy.insertText("\n")}
 @objc private func toggleShift(){shift.toggle()}
 @objc private func nextKeyboard(){advanceToNextInputMode()}
 @objc private func numbers(){}
 @objc private func fix(){ runAI(.fix) }
 @objc private func more(){
  let a = UIAlertController(title:"More",message:nil,preferredStyle:.actionSheet)
  [("Rewrite",AIAction.rewrite),("Translate",.translate),("Tone",.tone)].forEach{ name,act in a.addAction(UIAlertAction(title:name,style:.default){_ in self.runAI(act)})}; a.addAction(UIAlertAction(title:"Cancel",style:.cancel)); present(a,animated:true)
 }
 @objc private func clipboard(){
  let a = UIAlertController(title:"Clipboard",message:"Paste from the system clipboard",preferredStyle:.actionSheet)
  a.addAction(UIAlertAction(title:"Paste",style:.default){_ in if let s = UIPasteboard.general.string {self.textDocumentProxy.insertText(s)} }); a.addAction(UIAlertAction(title:"Cancel",style:.cancel)); present(a,animated:true)
 }
 private func runAI(_ action:AIAction){
  guard hasFullAccess else { return }
  let context = textDocumentProxy.documentContextBeforeInput ?? ""; guard !context.isEmpty else{return}
  Task { if let replacement = await AIService.shared.transform(context,action:action){ await MainActor.run { for _ in context {self.textDocumentProxy.deleteBackward()}; self.textDocumentProxy.insertText(replacement) } } }
 }
}
final class TouchKey:UIButton { override func point(inside point:CGPoint,with event:UIEvent?)->Bool { bounds.insetBy(dx:-3,dy:-5).contains(point) } }