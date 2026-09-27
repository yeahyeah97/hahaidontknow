import Foundation
import AVFoundation
import Speech
import UserNotifications

@MainActor
final class PermissionCenter: ObservableObject {
    @Published var microphone = "NOT CHECKED"
    @Published var speech = "NOT CHECKED"
    @Published var notifications = "NOT CHECKED"

    func requestStartupPermissions() {
        requestMicrophone()
        requestSpeechFallback()
        requestNotifications()
    }

    private func requestMicrophone() {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:
            microphone = "ALLOWED"
        case .denied:
            microphone = "DENIED"
        case .undetermined:
            AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async {
                    self?.microphone = granted ? "ALLOWED" : "DENIED"
                }
            }
        @unknown default:
            microphone = "UNKNOWN"
        }
    }

    private func requestSpeechFallback() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                switch status {
                case .authorized: self?.speech = "ALLOWED"
                case .denied: self?.speech = "DENIED"
                case .restricted: self?.speech = "RESTRICTED"
                case .notDetermined: self?.speech = "NOT CHECKED"
                @unknown default: self?.speech = "UNKNOWN"
                }
            }
        }
    }

    private func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.notifications = granted ? "ALLOWED" : "DENIED"
            }
        }
    }
}
