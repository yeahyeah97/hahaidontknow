import UIKit

final class TouchLearningModel {
    static let shared = TouchLearningModel()

    private struct Sample: Codable {
        var meanX: Double
        var meanY: Double
        var count: Int
    }

    private let defaults = UserDefaults.standard
    private let storageKey = "milazy.touchBias.v1"
    private var samples: [String: Sample]
    private let lock = NSLock()

    private init() {
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String: Sample].self, from: data) {
            samples = decoded
        } else {
            samples = [:]
        }
    }

    func record(key: String, point: CGPoint, frame: CGRect) {
        guard frame.width > 1, frame.height > 1, !key.isEmpty else { return }

        let nx = max(-0.48, min(0.48, Double((point.x - frame.midX) / frame.width)))
        let ny = max(-0.48, min(0.48, Double((point.y - frame.midY) / frame.height)))

        lock.lock()
        var sample = samples[key] ?? Sample(meanX: 0, meanY: 0, count: 0)
        let newCount = min(sample.count + 1, 600)

        // Learn quickly at first, then settle into a stable personal bias.
        let alpha: Double
        if sample.count < 20 {
            alpha = 1.0 / Double(sample.count + 1)
        } else {
            alpha = 0.035
        }

        sample.meanX += (nx - sample.meanX) * alpha
        sample.meanY += (ny - sample.meanY) * alpha
        sample.count = newCount
        samples[key] = sample

        let snapshot = samples
        lock.unlock()

        // Avoid touching disk on every key once the model is warm.
        if newCount <= 20 || newCount % 12 == 0 {
            if let data = try? JSONEncoder().encode(snapshot) {
                defaults.set(data, forKey: storageKey)
            }
        }
    }

    func adjustedCenter(for key: String, frame: CGRect) -> CGPoint {
        lock.lock()
        let sample = samples[key]
        lock.unlock()

        guard let sample, sample.count >= 4 else {
            return CGPoint(x: frame.midX, y: frame.midY)
        }

        // Shift only part of the way toward the user's average landing point.
        // This improves gap decisions without making the keyboard feel unstable.
        let strength = min(0.70, 0.35 + Double(sample.count) / 500.0)
        return CGPoint(
            x: frame.midX + CGFloat(sample.meanX * strength) * frame.width,
            y: frame.midY + CGFloat(sample.meanY * strength) * frame.height
        )
    }
}
