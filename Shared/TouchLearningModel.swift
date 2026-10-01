import UIKit

final class TouchLearningModel {
    static let shared = TouchLearningModel()

    private struct Gaussian: Codable {
        var meanX: Double = 0
        var meanY: Double = 0
        var varX: Double = 0.045
        var varY: Double = 0.055
        var count: Int = 0
    }

    private let defaults = UserDefaults.standard
    private let storageKey = "milazy.touchGaussian.v2"
    private var models: [String: Gaussian]
    private let lock = NSLock()

    private init() {
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String: Gaussian].self, from: data) {
            models = decoded
        } else {
            models = [:]
        }
    }

    func record(key: String, point: CGPoint, frame: CGRect) {
        guard frame.width > 1, frame.height > 1, !key.isEmpty else { return }

        let nx = max(-0.80, min(0.80, Double((point.x - frame.midX) / frame.width)))
        let ny = max(-0.80, min(0.80, Double((point.y - frame.midY) / frame.height)))

        lock.lock()
        var model = models[key] ?? Gaussian()

        let alpha: Double
        if model.count < 24 {
            alpha = 1.0 / Double(model.count + 1)
        } else {
            alpha = 0.025
        }

        let oldMeanX = model.meanX
        let oldMeanY = model.meanY

        model.meanX += (nx - model.meanX) * alpha
        model.meanY += (ny - model.meanY) * alpha

        let dx = nx - oldMeanX
        let dy = ny - oldMeanY
        model.varX += ((dx * dx) - model.varX) * alpha
        model.varY += ((dy * dy) - model.varY) * alpha

        // Keep the model forgiving. We want adaptation, not overfitting.
        model.varX = min(max(model.varX, 0.018), 0.18)
        model.varY = min(max(model.varY, 0.022), 0.22)
        model.count = min(model.count + 1, 2500)

        models[key] = model
        let snapshot = models
        let count = model.count
        lock.unlock()

        if count <= 24 || count % 16 == 0 {
            if let data = try? JSONEncoder().encode(snapshot) {
                defaults.set(data, forKey: storageKey)
            }
        }
    }

    func adjustedCenter(for key: String, frame: CGRect) -> CGPoint {
        lock.lock()
        let model = models[key]
        lock.unlock()

        guard let model, model.count >= 4 else {
            return CGPoint(x: frame.midX, y: frame.midY)
        }

        let strength = min(0.82, 0.42 + Double(model.count) / 850.0)
        return CGPoint(
            x: frame.midX + CGFloat(model.meanX * strength) * frame.width,
            y: frame.midY + CGFloat(model.meanY * strength) * frame.height
        )
    }

    func probabilityScore(for key: String, point: CGPoint, frame: CGRect) -> CGFloat {
        let nx = Double((point.x - frame.midX) / max(frame.width, 1))
        let ny = Double((point.y - frame.midY) / max(frame.height, 1))

        lock.lock()
        let model = models[key]
        lock.unlock()

        guard let model, model.count >= 6 else {
            let dx = nx
            let dy = ny
            return CGFloat(dx * dx / 0.055 + dy * dy / 0.075)
        }

        let reliability = min(1.0, Double(model.count) / 70.0)
        let meanX = model.meanX * reliability
        let meanY = model.meanY * reliability
        let vx = model.varX + (1.0 - reliability) * 0.030
        let vy = model.varY + (1.0 - reliability) * 0.040

        let dx = nx - meanX
        let dy = ny - meanY

        // Negative-log-likelihood-like score. Lower is a better match.
        let mahalanobis = (dx * dx / vx) + (dy * dy / vy)
        let spreadPenalty = 0.14 * log(vx * vy)
        return CGFloat(mahalanobis + spreadPenalty)
    }

    func reset() {
        lock.lock()
        models.removeAll()
        lock.unlock()
        defaults.removeObject(forKey: storageKey)
    }
}
