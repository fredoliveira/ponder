import Foundation

/// A draft event as emitted by `ponder-feed` (and by recall's archive, which shares the format).
enum DraftEvent {
    case pack(Pack)
    case pick(pack: Int, pick: Int)
    case draftComplete

    init?(line: String) {
        guard let data = line.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let event = obj["event"] as? String
        else { return nil }
        let pack = (obj["pack_number"] as? NSNumber)?.intValue ?? 0
        let pick = (obj["pick_number"] as? NSNumber)?.intValue ?? 0
        switch event {
        case "draft_pack":
            // LogBusiness packs are logged together with the pick: too late to be useful.
            guard obj["source"] as? String != "LogBusiness",
                let name = obj["event_name"] as? String,
                let ids = obj["card_ids"] as? [Any]
            else { return nil }
            // Card ids are integers in human drafts and strings in bot drafts.
            let cardIds = ids.compactMap { ($0 as? NSNumber)?.intValue ?? Int($0 as? String ?? "") }
            self = .pack(Pack(eventName: name, pack: pack, pick: pick, cardIds: cardIds))
        case "draft_pick": self = .pick(pack: pack, pick: pick)
        case "event_course": self = .draftComplete
        default: return nil
        }
    }
}

struct Pack: Equatable {
    let eventName: String
    let pack: Int
    let pick: Int
    let cardIds: [Int]

    /// "PremierDraft_HOB_20260811" -> ("PremierDraft", "HOB")
    var formatAndSet: (format: String, set: String)? {
        let parts = eventName.split(separator: "_")
        guard parts.count >= 2 else { return nil }
        return (String(parts[0]), String(parts[1]))
    }
}

/// Runs `ponder-feed` and delivers its events on the main queue.
final class LiveFeed {
    private let process = Process()

    init?(onEvent: @escaping (DraftEvent) -> Void) {
        guard let binary = LiveFeed.locate() else { return nil }
        process.executableURL = binary
        let pipe = Pipe()
        process.standardOutput = pipe
        do { try process.run() } catch { return nil }

        Thread.detachNewThread {
            var buffer = Data()
            while true {
                let chunk = pipe.fileHandleForReading.availableData
                if chunk.isEmpty { break }
                buffer.append(chunk)
                while let newline = buffer.firstIndex(of: 0x0A) {
                    let line = String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self)
                    buffer.removeSubrange(buffer.startIndex...newline)
                    if let event = DraftEvent(line: line) {
                        DispatchQueue.main.async { onEvent(event) }
                    }
                }
            }
        }
    }

    func stop() { if process.isRunning { process.terminate() } }

    private static func locate() -> URL? {
        let fm = FileManager.default
        var candidates: [URL] = []
        if let env = ProcessInfo.processInfo.environment["PONDER_FEED"] {
            candidates.append(URL(fileURLWithPath: env))
        }
        if let exe = Bundle.main.executableURL {
            candidates.append(exe.deletingLastPathComponent().appendingPathComponent("ponder-feed"))
        }
        candidates.append(
            URL(fileURLWithPath: fm.currentDirectoryPath)
                .appendingPathComponent("feed/target/release/ponder-feed"))
        return candidates.first { fm.isExecutableFile(atPath: $0.path) }
    }
}

/// Test feed: steps through the packs recorded in a JSONL file (recall archive or saved
/// `ponder-feed` output), one every `interval` seconds, or shows only pack `at` if given.
final class ReplayFeed {
    private var timer: Timer?

    init?(path: String, interval: TimeInterval, at: Int?, onEvent: @escaping (DraftEvent) -> Void) {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        let packs: [DraftEvent] = text.split(separator: "\n").compactMap {
            guard let event = DraftEvent(line: String($0)), case .pack = event else { return nil }
            return event
        }
        guard !packs.isEmpty else { return nil }
        if let at {
            onEvent(packs[min(max(at, 0), packs.count - 1)])
            return
        }
        var index = 0
        onEvent(packs[0])
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            index = (index + 1) % packs.count
            onEvent(packs[index])
        }
    }
}
