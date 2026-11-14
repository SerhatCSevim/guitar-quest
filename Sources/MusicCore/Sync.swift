// Tempo map → nominal seconds, and the anchor-based mapping between a backing track's clock and score ticks.
import Foundation

/// Nominal time of a score (seconds at the written tempi) from its tempo map.
public struct TempoTimeline: Sendable {
    public let tpb: Int
    public let marks: [TempoMark]        // sorted, first at tick 0
    private let secondsAtMark: [Double]  // nominal seconds at each mark
    public let totalTicks: Int

    public init(score: Score) {
        self.init(tpb: score.tpb, tempo: Double(score.tempo), tempoMap: score.tempoMap, totalTicks: score.totalTicks)
    }
    public init(tpb: Int, tempo: Double, tempoMap: [TempoMark], totalTicks: Int) {
        self.tpb = tpb
        self.totalTicks = totalTicks
        var m = tempoMap.filter { $0.bpm > 0 }.sorted { $0.tick < $1.tick }
        if m.first?.tick != 0 { m.insert(TempoMark(tick: 0, bpm: m.first?.bpm ?? max(1, tempo)), at: 0) }
        // collapse duplicates at the same tick (last wins)
        var dedup: [TempoMark] = []
        for x in m { if dedup.last?.tick == x.tick { dedup[dedup.count - 1] = x } else { dedup.append(x) } }
        marks = dedup
        var secs: [Double] = [0]
        for k in 1..<max(1, dedup.count) {
            let dt = Double(dedup[k].tick - dedup[k - 1].tick) / Double(tpb) * 60 / dedup[k - 1].bpm
            secs.append(secs[k - 1] + dt)
        }
        secondsAtMark = secs
    }

    /// Tempo in force at `tick`.
    public func bpm(atTick tick: Int) -> Double {
        var i = 0
        while i + 1 < marks.count && marks[i + 1].tick <= tick { i += 1 }
        return marks[i].bpm
    }

    public func seconds(atTick tick: Double) -> Double {
        var i = 0
        while i + 1 < marks.count && Double(marks[i + 1].tick) <= tick { i += 1 }
        return secondsAtMark[i] + (tick - Double(marks[i].tick)) / Double(tpb) * 60 / marks[i].bpm
    }
    public func seconds(atTick tick: Int) -> Double { seconds(atTick: Double(tick)) }

    public func tick(atSeconds s: Double) -> Double {
        var i = 0
        while i + 1 < marks.count && secondsAtMark[i + 1] <= s { i += 1 }
        return Double(marks[i].tick) + (s - secondsAtMark[i]) * marks[i].bpm / 60 * Double(tpb)
    }

    public var totalSeconds: Double { seconds(atTick: totalTicks) }
}

/// One "the recording is at this second when the score is at this tick" point.
public struct SyncAnchor: Hashable, Codable, Sendable {
    public var mediaTime: Double
    public var tick: Int
    public init(mediaTime: Double, tick: Int) { self.mediaTime = mediaTime; self.tick = tick }
}

/// Maps a backing track's clock to score ticks and back. Between two anchors the nominal (tempo-map) time is
/// stretched linearly, so written tempo changes are honoured and small drifts of a live recording are absorbed.
/// Outside the anchors the nominal tempo is used unchanged. With no anchors, second 0 = tick 0.
public struct SyncMap: Sendable {
    public let timeline: TempoTimeline
    public let anchors: [SyncAnchor]          // sorted by mediaTime, strictly increasing ticks
    private let nominal: [Double]             // nominal seconds at each anchor

    public init(timeline: TempoTimeline, anchors: [SyncAnchor]) {
        self.timeline = timeline
        var a = anchors.sorted { $0.mediaTime < $1.mediaTime }
        // drop anchors that would run backwards in score time
        var clean: [SyncAnchor] = []
        for x in a { if let l = clean.last, x.tick <= l.tick || x.mediaTime <= l.mediaTime { continue }; clean.append(x) }
        if clean.isEmpty { clean = [SyncAnchor(mediaTime: 0, tick: 0)] }
        a = clean
        self.anchors = a
        nominal = a.map { timeline.seconds(atTick: $0.tick) }
    }

    /// Score tick for a media time (may be < 0 before the music starts, or > totalTicks after it ends).
    public func tick(atMediaTime m: Double) -> Double {
        let n = nominalSeconds(atMediaTime: m)
        return timeline.tick(atSeconds: n)
    }

    /// Media time at which the score reaches `tick`.
    public func mediaTime(atTick tick: Double) -> Double {
        let n = timeline.seconds(atTick: tick)
        return mediaTime(atNominal: n)
    }

    func nominalSeconds(atMediaTime m: Double) -> Double {
        if anchors.count == 1 || m <= anchors[0].mediaTime { return nominal[0] + (m - anchors[0].mediaTime) }
        for k in 1..<anchors.count where m <= anchors[k].mediaTime {
            let (m0, m1) = (anchors[k - 1].mediaTime, anchors[k].mediaTime)
            let (n0, n1) = (nominal[k - 1], nominal[k])
            return n0 + (m - m0) * (n1 - n0) / (m1 - m0)
        }
        let last = anchors.count - 1
        return nominal[last] + (m - anchors[last].mediaTime)
    }

    func mediaTime(atNominal n: Double) -> Double {
        if anchors.count == 1 || n <= nominal[0] { return anchors[0].mediaTime + (n - nominal[0]) }
        for k in 1..<anchors.count where n <= nominal[k] {
            let (m0, m1) = (anchors[k - 1].mediaTime, anchors[k].mediaTime)
            let (n0, n1) = (nominal[k - 1], nominal[k])
            return m0 + (n - n0) * (m1 - m0) / (n1 - n0)
        }
        let last = anchors.count - 1
        return anchors[last].mediaTime + (n - nominal[last])
    }
}
