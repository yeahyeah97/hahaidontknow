import Foundation

// Tracks our own edits in memory. Delayed host echoes cannot erase a rapidly
// typed final character just before Space. No proxy access is needed per letter.
struct TypingContextBuffer {
    private(set) var context: String?
    private(set) var document: UUID?
    private var echoes: [(String?, TimeInterval)] = []

    mutating func reconcile(context host: String?, document: UUID,
                            now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        if self.document != document {
            self.document = document
            context = host
            echoes.removeAll()
            return true
        }
        echoes.removeAll { now - $0.1 > 0.3 }
        if host == context {
            echoes.removeAll()
            return false
        }
        if echoes.contains(where: { $0.0 == host }) { return false }
        context = host
        echoes.removeAll()
        return true
    }

    mutating func setAfterEdit(_ value: String?,
                              now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        echoes.append((context, now))
        if echoes.count > 24 { echoes.removeFirst(echoes.count - 24) }
        context = value.map { String($0.suffix(512)) }
    }

    mutating func append(_ text: String, now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        setAfterEdit(context.map { $0 + text }, now: now)
    }
}
