// Practice clock: counts seconds while something is actively practised (Note Quest round, Studio player, Jam player).
// Ticks every 5 s; adds to today's entry each time ≥ 15 s have accumulated and when everything stops.
import Foundation

@MainActor
final class PracticeClock {
    private let store: ProgressStore
    private var active = Set<String>()
    private var last: Date? = nil
    private var acc: Double = 0
    private var timer: Timer?

    init(store: ProgressStore) { self.store = store }

    private func tick() {
        let t = Date()
        if !active.isEmpty, let l = last { acc += t.timeIntervalSince(l) }
        last = t
        if acc >= 15 { store.addPractice(acc); acc = 0 }
    }

    func start(_ who: String) {
        tick()
        active.insert(who)
        last = Date()
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
        }
    }

    func stop(_ who: String) {
        tick()
        active.remove(who)
        if active.isEmpty { store.addPractice(acc); acc = 0; timer?.invalidate(); timer = nil }
    }

    func stopAll() {
        tick()
        active.removeAll()
        store.addPractice(acc); acc = 0
        timer?.invalidate(); timer = nil
    }

    var isRunning: Bool { !active.isEmpty }
}
