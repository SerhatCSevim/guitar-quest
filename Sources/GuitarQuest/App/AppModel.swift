// App shell state: current screen, navigation parameters, toast, keyboard routing.
import SwiftUI
import Observation
import MusicCore

enum Screen: String, CaseIterable, Identifiable {
    case explore, quest, scales, studio, harmony, progress
    var id: String { rawValue }
    var title: String {
        switch self {
        case .explore: return "Fretboard"
        case .quest: return "Note Quest"
        case .scales: return "Scales"
        case .studio: return "Practice Studio"
        case .harmony: return "Chords & Harmony"
        case .progress: return "My Progress"
        }
    }
}

/// Parameters handed to the Studio when opened from Scales ("Practise in the Studio →").
struct StudioParams: Equatable {
    var tonic: String
    var scaleId: ScaleID
    var shapeId: String
}

/// Parameters handed to Chords & Harmony (e.g. "Jam →" from Chord families).
struct HarmonyParams: Equatable {
    var tab: String
    var progId: String? = nil
    var family: Family? = nil
    var key: String? = nil
}

@Observable
@MainActor
final class AppModel {
    var screen: Screen = .explore
    var pendingStudio: StudioParams? = nil
    var pendingHarmony: HarmonyParams? = nil
    var toastMessage: String? = nil
    private var toastWork: DispatchWorkItem?
    /// Screens register a key handler here (Space/Esc in the Studio, letters in Note Quest).
    var keyHandler: ((KeyPress) -> KeyPress.Result)? = nil
    /// Bumped when a setting changes so screens re-render (web: `gq-settings` event).
    var settingsVersion = 0

    func go(_ s: Screen) { screen = s }
    func goStudio(_ p: StudioParams) { pendingStudio = p; screen = .studio }
    func goHarmony(_ p: HarmonyParams) { pendingHarmony = p; screen = .harmony }

    func toast(_ msg: String) {
        toastMessage = msg
        toastWork?.cancel()
        let w = DispatchWorkItem { [weak self] in withAnimation { self?.toastMessage = nil } }
        toastWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: w)
    }
}

/// Everything a screen needs, passed through the environment.
@MainActor
final class Services {
    let store: ProgressStore
    let audio: AudioEngine
    let clock: PracticeClock
    let model: AppModel
    init(store: ProgressStore, audio: AudioEngine, clock: PracticeClock, model: AppModel) {
        self.store = store; self.audio = audio; self.clock = clock; self.model = model
    }
}

extension Settings {
    /// `both` shows "C (Do)" in badges but short labels use letters (web: nm()).
    var namingShort: Naming { naming == .both ? .letters : naming }
    /// Spelling preference for unspelled black-key notes (never `.both`).
    var spellPref: AccidentalPref { accidentals == .flat ? .flat : .sharp }
}
