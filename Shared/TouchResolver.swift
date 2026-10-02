import Foundation

enum TouchResolver {
    struct Candidate {
        let id: Int
        let frame: CGRect
        let learningKey: String?
    }

    // Called with cached layout geometry. Scores share the same units for every key.
    static func resolve(_ point: CGPoint, candidates: [Candidate],
                        expansion: CGSize, model: TouchLearningModel = .shared) -> Int? {
        guard let nearest = candidates.min(by: {
            abs($0.frame.midY - point.y) < abs($1.frame.midY - point.y)
        }) else { return nil }
        let row = candidates.filter { abs($0.frame.midY - nearest.frame.midY) < 12 }
        let visible = row.first { $0.frame.contains(point) }

        // Keep taps well inside a cap stable, including shift/delete/space.
        if let visible, visible.frame.insetBy(
            dx: visible.frame.width * 0.18, dy: visible.frame.height * 0.12
        ).contains(point) { return visible.id }

        let eligible = row.filter {
            $0.frame.insetBy(dx: -expansion.width, dy: -expansion.height).contains(point)
        }
        let pool = eligible.isEmpty ? row : eligible
        let ranked = pool.map { key -> (Candidate, CGFloat) in
            let score = model.probabilityScore(
                for: key.learningKey ?? "", point: point, frame: key.frame
            )
            return (key, score)
        }.sorted { $0.1 == $1.1 ? $0.0.id < $1.0.id : $0.1 < $1.1 }
        guard let best = ranked.first else { return nil }
        if let visible, visible.id != best.0.id,
           let visibleScore = ranked.first(where: { $0.0.id == visible.id })?.1,
           visibleScore - best.1 < 0.9 { return visible.id }
        return best.0.id
    }
}
