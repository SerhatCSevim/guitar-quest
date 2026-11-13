// ScoreView: lays out a score for the width it is given and draws every system in one Canvas.
// The height is computed synchronously from the proposed width (custom Layout), so it works inside stacks,
// scroll views and ImageRenderer alike.
import SwiftUI
import MusicCore

struct NotationOptions: Equatable {
    var showStaff = true
    var showTab = true
    var showNames = false
    var colors = true
    var naming: Naming = .letters
    var minWidth: CGFloat = 520

    func layoutOptions(width: CGFloat) -> LayoutOptions {
        // at least one of staff/tab is always shown (web: if (!showStaff && !showTab) showTab = true)
        LayoutOptions(width: width, showStaff: showStaff, showTab: showTab || !showStaff, showNames: showNames, colors: colors, naming: naming)
    }
}

struct ScoreView: View {
    var score: Score?
    var options: NotationOptions
    var active: Int? = nil
    var next: Int? = nil
    var onSeek: ((Int) -> Void)? = nil
    /// Pass a ScrollViewReader proxy to scroll the active system into view.
    var scrollProxy: ScrollViewProxy? = nil

    var body: some View {
        ScoreFrame(score: score, options: options) {
            ScoreCanvas(score: score, options: options, active: active, next: next, onSeek: onSeek, scrollProxy: scrollProxy)
        }
    }
}

/// Sizes its single child: full proposed width, height = systems × system height for that width.
struct ScoreFrame: Layout {
    var score: Score?
    var options: NotationOptions

    static func layoutWidth(_ proposed: CGFloat?, _ options: NotationOptions) -> CGFloat {
        max(options.minWidth, floor((proposed ?? options.minWidth) - 4))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = Self.layoutWidth(proposal.width, options)
        guard let score else { return CGSize(width: max(proposal.width ?? width, width), height: 60) }
        let L = Notation.layout(score, options.layoutOptions(width: width))
        return CGSize(width: max(proposal.width ?? width, width), height: L.height * CGFloat(L.systems.count))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for s in subviews { s.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size)) }
    }
}

struct ScoreCanvas: View {
    var score: Score?
    var options: NotationOptions
    var active: Int?
    var next: Int?
    var onSeek: ((Int) -> Void)?
    var scrollProxy: ScrollViewProxy?

    var body: some View {
        GeometryReader { geo in
            let width = ScoreFrame.layoutWidth(geo.size.width, options)
            if let score {
                let L = Notation.layout(score, options.layoutOptions(width: width))
                let single = L.systems.count == 1
                let W = single ? min(width, ceil(L.systems[0].right + 10)) : width
                let dx = single ? max(0, (geo.size.width - W) / 2) : 0
                ZStack(alignment: .topLeading) {
                    Canvas(rendersAsynchronously: false) { ctx, _ in
                        let drawer = NotationDrawer(L: L, active: active, next: next)
                        for si in L.systems.indices {
                            var c = ctx
                            c.translateBy(x: dx, y: CGFloat(si) * L.height)
                            drawer.drawSystem(&c, si)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { loc in
                        guard let onSeek else { return }
                        let si = Int(loc.y / L.height)
                        guard si >= 0, si < L.systems.count else { return }
                        let x = loc.x - dx
                        for i in L.systems[si].events where x >= L.prep[i].slot0 && x <= L.prep[i].slot1 { onSeek(i); return }
                    }
                    // invisible anchors for auto-scroll
                    ForEach(L.systems.indices, id: \.self) { si in
                        Color.clear.frame(width: 1, height: 1).offset(y: CGFloat(si) * L.height).id("sys\(si)")
                    }
                }
                .onChange(of: active) { _, a in
                    guard let a, a >= 0, a < L.prep.count, let proxy = scrollProxy else { return }
                    withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo("sys\(L.prep[a].system)", anchor: .top) }
                }
            }
        }
    }
}
