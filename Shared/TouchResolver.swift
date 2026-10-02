import Foundation
import CoreGraphics

enum TouchResolver {
    struct Candidate {
        let id: Int
        let frame: CGRect
        let learningKey: String?
    }

    // Called with cached layout geometry. Scores share the same units for every key.
    static func resolve(_ point: CGPoint, candidates: [Candidate],
                        expansion: CGSize, model: TouchLearningModel = .shared) -> Int? {
        let usable = candidates.filter { $0.frame.width > 1 && $0.frame.height > 1 }
        // A painted keycap always owns its taps. Adaptation only resolves gaps.
        if let visible = usable.first(where: { $0.frame.contains(point) }) { return visible.id }
        guard let nearest = usable.min(by: {
            abs($0.frame.midY - point.y) < abs($1.frame.midY - point.y)
        }) else { return nil }
        let row = usable.filter { abs($0.frame.midY - nearest.frame.midY) < 12 }
        let eligible = usable.filter {
            $0.frame.insetBy(dx: -expansion.width, dy: -expansion.height).contains(point)
        }
        let pool = eligible.isEmpty ? row : eligible
        let scores: [(Candidate, CGFloat)] = pool.map { key -> (Candidate, CGFloat) in
            let closest = CGPoint(x: min(max(point.x, key.frame.minX), key.frame.maxX),
                                  y: min(max(point.y, key.frame.minY), key.frame.maxY))
            let dx = point.x - closest.x, dy = point.y - closest.y
            let likelihood = model.probabilityScore(
                for: key.learningKey ?? "", point: point, frame: key.frame
            )
            let boundaryLikelihood = model.probabilityScore(
                for: key.learningKey ?? "", point: closest, frame: key.frame
            )
            // Distance from the cap edge avoids favoring wide Shift/Return keys.
            // Learned likelihood adjusts close gap decisions without moving caps.
            let score = dx * dx + dy * dy + max(0, likelihood - boundaryLikelihood)
                * min(expansion.width, expansion.height) * 0.75
            return (key, score)
        }
        let ranked = scores.sorted { lhs, rhs in
            if lhs.1 == rhs.1 { return lhs.0.id < rhs.0.id }
            return lhs.1 < rhs.1
        }
        guard let best = ranked.first else { return nil }
        return best.0.id
    }
}

