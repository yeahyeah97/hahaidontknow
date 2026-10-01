import Foundation
enum AIAction { case fix,rewrite,translate,tone }
final class AIService {
 static let shared=AIService(); private init(){}
 func transform(_ text:String,action:AIAction) async -> String? {
  return nil
 }
}