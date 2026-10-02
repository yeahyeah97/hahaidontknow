import Foundation
import CoreGraphics

final class TouchLearningModel {
    static let shared = TouchLearningModel()

    private struct Gaussian: Codable {
        var meanX: Double = 0
        var meanY: Double = 0
        var varX: Double = 0.055
        var varY: Double = 0.075
        var count: Int = 0
    }

    private let defaults: UserDefaults
    private let storageKey = "milazy.touchGaussian.v2"
    private let queue = DispatchQueue(label: "milazy.touch.learning", qos: .utility)
    private let lock = NSLock()
    private var models: [String: Gaussian]
    private var pendingSave: DispatchWorkItem?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        models = defaults.data(forKey: storageKey).flatMap {
            try? JSONDecoder().decode([String: Gaussian].self, from: $0)
        } ?? [:]
    }

    // Only confirmed central touch-down samples train the model. Release jitter and
    // inferred neighboring keys cannot reinforce their own mistakes.
    func record(key: String, point: CGPoint, frame: CGRect) {
        guard frame.width > 1, frame.height > 1, !key.isEmpty,
              frame.insetBy(dx: frame.width * 0.12, dy: frame.height * 0.08).contains(point)
        else { return }
        let nx = Double((point.x - frame.midX) / frame.width)
        let ny = Double((point.y - frame.midY) / frame.height)
        queue.async {
            self.lock.lock()
            var model = self.models[key] ?? Gaussian()
            let alpha = model.count < 24 ? 1 / Double(model.count + 8) : 0.025
            let dx = nx - model.meanX
            let dy = ny - model.meanY
            model.meanX = max(-0.22, min(0.22, model.meanX + dx * alpha))
            model.meanY = max(-0.22, min(0.22, model.meanY + dy * alpha))
            model.varX = min(0.18, max(0.035, model.varX + (dx * dx - model.varX) * alpha))
            model.varY = min(0.22, max(0.045, model.varY + (dy * dy - model.varY) * alpha))
            model.count = min(model.count + 1, 2500)
            self.models[key] = model
            self.lock.unlock()
            self.scheduleSave()
        }
    }

    func probabilityScore(for key: String, point: CGPoint, frame: CGRect) -> CGFloat {
        let nx = Double((point.x - frame.midX) / max(frame.width, 1))
        let ny = Double((point.y - frame.midY) / max(frame.height, 1))
        // Never wait for background learning on the touch-down path.
        let model: Gaussian
        if lock.try() {
            model = models[key] ?? Gaussian()
            lock.unlock()
        } else { model = Gaussian() }
        let reliability = min(1, Double(model.count) / 70)
        let dx = nx - model.meanX * reliability
        let dy = ny - model.meanY * reliability
        let vx = model.varX * reliability + 0.055 * (1 - reliability)
        let vy = model.varY * reliability + 0.075 * (1 - reliability)
        return CGFloat(dx * dx / vx + dy * dy / vy + 0.14 * log(vx * vy))
    }

    private func scheduleSave() {
        guard pendingSave == nil else { return }
        let item = DispatchWorkItem {
            self.lock.lock()
            let snapshot = self.models
            self.lock.unlock()
            if let data = try? JSONEncoder().encode(snapshot) {
                self.defaults.set(data, forKey: self.storageKey)
            }
            self.pendingSave = nil
        }
        pendingSave = item
        queue.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    func reset() {
        queue.async {
            self.pendingSave?.cancel()
            self.pendingSave = nil
            self.lock.lock()
            self.models.removeAll()
            self.lock.unlock()
            self.defaults.removeObject(forKey: self.storageKey)
        }
    }

    func flush() {
        queue.sync {
            self.pendingSave?.cancel()
            self.pendingSave = nil
            self.lock.lock()
            let snapshot = self.models
            self.lock.unlock()
            if let data = try? JSONEncoder().encode(snapshot) {
                self.defaults.set(data, forKey: self.storageKey)
            }
        }
    }
}

