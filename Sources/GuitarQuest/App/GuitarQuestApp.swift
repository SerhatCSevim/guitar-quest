// App shell: top bar with tabs, settings popover, screen routing, practice clock. Port of index.html + js/app.js.
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import MusicCore

@main
struct GuitarQuestApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var services: Services

    init() {
        let store = ProgressStore()
        let audio = AudioEngine(volume: store.settings.volume)
        let model = AppModel()
        let clock = PracticeClock(store: store)
        let services = Services(store: store, audio: audio, clock: clock, model: model)
        _services = State(initialValue: services)
        AppDelegate.shared = (store, clock)
        Snapshots.runIfRequested(services)
        AudioCheck.runIfRequested(services)
    }

    var body: some Scene {
        WindowGroup("Guitar Quest") {
            RootView()
                .environment(services.store)
                .environment(services.model)
                .environment(\.services, services)
                .frame(minWidth: 1100, minHeight: 750)
        }
        .defaultSize(width: 1280, height: 880)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    nonisolated(unsafe) static var shared: (ProgressStore, PracticeClock)?
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            AppDelegate.shared?.1.stopAll()
            AppDelegate.shared?.0.flush()
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

private struct ServicesKey: EnvironmentKey {
    nonisolated(unsafe) static var defaultValue: Services? = nil
}
extension EnvironmentValues {
    var services: Services? {
        get { self[ServicesKey.self] }
        set { self[ServicesKey.self] = newValue }
    }
}

// MARK: - root

struct RootView: View {
    @Environment(\.services) private var services
    @Environment(AppModel.self) private var model
    @Environment(ProgressStore.self) private var store
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ZStack(alignment: .bottom) {
                ScrollView(.vertical) {
                    screenView
                        .padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 60)
                        .frame(maxWidth: 1280)
                        .frame(maxWidth: .infinity)
                }
                .id(model.screen) // fresh scroll position per screen
                if let msg = model.toastMessage {
                    ToastView(message: msg).padding(.bottom, 26).transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .background(Theme.bg)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress { press in model.keyHandler?(press) ?? .ignored }
        .onChange(of: model.screen) { _, _ in
            services?.clock.stopAll()
            model.keyHandler = nil
        }
    }

    @ViewBuilder private var screenView: some View {
        switch model.screen {
        case .explore: ExploreView()
        case .quest: QuestView()
        case .scales: ScalesView()
        case .studio: StudioView()
        case .harmony: HarmonyView()
        case .progress: ProgressView_()
        }
    }

    private var topBar: some View {
        HStack(spacing: 18) {
            HStack(spacing: 9) {
                BrandPick().frame(width: 30, height: 30)
                Text("Guitar Quest").font(.system(size: 19, weight: .heavy)).foregroundStyle(.white)
            }
            .onTapGesture { model.go(.explore) }
            HStack(spacing: 4) {
                ForEach(Screen.allCases) { s in
                    let on = model.screen == s
                    Button { model.go(s) } label: {
                        Text(s.title).font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(on ? .white : Color(hex: 0xC9CEDB))
                            .padding(.vertical, 8).padding(.horizontal, 13)
                            .background(on ? Theme.accent : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
            Button { showSettings.toggle() } label: {
                Image(systemName: "gearshape.fill").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 40, height: 40).background(Color.white.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .help("Settings")
            .popover(isPresented: $showSettings, arrowEdge: .bottom) { SettingsPanel() }
        }
        .padding(.vertical, 10).padding(.horizontal, 22)
        .background(Theme.topbar)
        .shadow(color: .black.opacity(0.15), radius: 5, y: 2)
        .zIndex(1)
    }
}

/// The orange guitar pick logo (index.html .brand-pick).
struct BrandPick: View {
    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 64
            var p = Path()
            p.move(to: CGPoint(x: 32 * s, y: 4 * s))
            p.addCurve(to: CGPoint(x: 8 * s, y: 24 * s), control1: CGPoint(x: 18 * s, y: 4 * s), control2: CGPoint(x: 8 * s, y: 12 * s))
            p.addCurve(to: CGPoint(x: 32 * s, y: 60 * s), control1: CGPoint(x: 8 * s, y: 38 * s), control2: CGPoint(x: 22 * s, y: 54 * s))
            p.addCurve(to: CGPoint(x: 56 * s, y: 24 * s), control1: CGPoint(x: 42 * s, y: 54 * s), control2: CGPoint(x: 56 * s, y: 38 * s))
            p.addCurve(to: CGPoint(x: 32 * s, y: 4 * s), control1: CGPoint(x: 56 * s, y: 12 * s), control2: CGPoint(x: 46 * s, y: 4 * s))
            ctx.fill(p, with: .color(Theme.accent))
            var l = Path()
            l.move(to: CGPoint(x: 22 * s, y: 26 * s)); l.addLine(to: CGPoint(x: 42 * s, y: 26 * s))
            l.move(to: CGPoint(x: 24 * s, y: 34 * s)); l.addLine(to: CGPoint(x: 40 * s, y: 34 * s))
            l.move(to: CGPoint(x: 28 * s, y: 42 * s)); l.addLine(to: CGPoint(x: 36 * s, y: 42 * s))
            ctx.stroke(l, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: 3.5 * s, lineCap: .round))
        }
    }
}

// MARK: - settings

struct SettingsPanel: View {
    @Environment(ProgressStore.self) private var store
    @Environment(AppModel.self) private var model
    @Environment(\.services) private var services
    @State private var importPending: ProgressData? = nil
    @State private var askReplace = false
    @State private var errorText: String? = nil

    var body: some View {
        let s = store.settings
        VStack(alignment: .leading, spacing: 10) {
            Text("Settings").font(.system(size: 16, weight: .bold))
            row("Note names") {
                Segmented(options: [SegOption(Naming.letters, "C D E"), SegOption(.solfege, "Do Re Mi"), SegOption(.both, "Both")],
                          selection: Binding(get: { s.naming }, set: { v in store.update { $0.naming = v }; model.settingsVersion += 1 }))
            }
            row("Black-key notes") {
                Segmented(options: [SegOption(AccidentalPref.sharp, "C♯"), SegOption(.flat, "D♭"), SegOption(.both, "C♯/D♭")],
                          selection: Binding(get: { s.accidentals }, set: { v in store.update { $0.accidentals = v }; model.settingsVersion += 1 }))
            }
            row("Note colours") {
                Segmented(options: [SegOption(true, "On"), SegOption(false, "Off")],
                          selection: Binding(get: { s.colors }, set: { v in store.update { $0.colors = v }; model.settingsVersion += 1 }))
            }
            row("Volume") {
                Slider(value: Binding(get: { s.volume }, set: { v in store.update { $0.volume = v }; services?.audio.setVolume(v) }), in: 0...1, step: 0.05)
                    .frame(width: 170).tint(Theme.accent)
            }
            Divider().padding(.vertical, 4)
            HStack(spacing: 8) {
                GQButton("Import progress…", small: true) { importProgress() }
                GQButton("Export progress…", small: true) { exportProgress() }
            }
            if let errorText { Text(errorText).font(.system(size: 12)).foregroundStyle(Theme.bad) }
            Text("Progress is saved on this Mac only.").font(.system(size: 12)).foregroundStyle(Theme.muted).padding(.top, 6)
        }
        .padding(18)
        .frame(width: 360)
        .alert("Replace the progress on this Mac?", isPresented: $askReplace) {
            Button("Replace", role: .destructive) { if let p = importPending { store.replace(with: p); model.settingsVersion += 1 } }
            Button("Keep Mac progress", role: .cancel) { importPending = nil }
        } message: {
            Text("This Mac already has stars and practice time. Importing replaces them with the file's progress.")
        }
    }

    private func row<C: View>(_ label: String, @ViewBuilder _ control: () -> C) -> some View {
        HStack { Text(label).font(.system(size: 14)); Spacer(); control() }
    }

    private func importProgress() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a guitarquest-progress.json file"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try ProgressStore.readProgress(from: url)
            errorText = nil
            if store.hasProgress { importPending = data; askReplace = true }
            else { store.replace(with: data); model.settingsVersion += 1; model.toast("Progress imported.") }
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func exportProgress() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "guitarquest-progress.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try store.export(to: url); model.toast("Progress exported.") } catch { errorText = error.localizedDescription }
    }
}
