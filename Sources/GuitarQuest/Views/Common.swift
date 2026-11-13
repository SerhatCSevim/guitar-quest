// Shared controls styled after css/style.css: cards, segmented control, chips, buttons, badges, toast.
import SwiftUI
import MusicCore

// MARK: - card

struct Card<Content: View>: View {
    var padding: EdgeInsets = EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18)
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).stroke(Color.black.opacity(0.03), lineWidth: 1))
            .shadow(color: Theme.shadow, radius: 9, y: 6)
            .shadow(color: Theme.shadow, radius: 1, y: 1)
    }
}

extension Theme {
    /// The tighter padding the web app uses for fretboard cards (.fb-card).
    static let fretboardCardPadding = EdgeInsets(top: 12, leading: 10, bottom: 6, trailing: 10)
}

// MARK: - headings

struct ViewHead: View {
    let title: String
    let lead: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 28, weight: .heavy)).foregroundStyle(Theme.ink)
            Text(lead).font(.system(size: 15.5)).foregroundStyle(Theme.muted).frame(maxWidth: 820, alignment: .leading)
        }
        .padding(.top, 4).padding(.bottom, 16)
    }
}

struct H3: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.ink).padding(.bottom, 8) }
}

struct SmallText: View {
    let text: String
    var muted = false
    init(_ text: String, muted: Bool = false) { self.text = text; self.muted = muted }
    var body: some View { Text(text).font(.system(size: 13)).foregroundStyle(muted ? Theme.muted : Theme.ink) }
}

struct TipText: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 14)).foregroundStyle(Color(hex: 0x0B5C63))
            .padding(.vertical, 9).padding(.horizontal, 12)
            .background(Theme.tealSoft).clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - field (label above a control)

struct Field<Content: View>: View {
    let label: String
    @ViewBuilder var content: () -> Content
    init(_ label: String, @ViewBuilder content: @escaping () -> Content) { self.label = label; self.content = content }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).font(.system(size: 12, weight: .bold)).kerning(0.6).foregroundStyle(Theme.muted)
            content()
        }
    }
}

/// Flow layout for toolbars (wraps like CSS flex-wrap).
struct Toolbar<Content: View>: View {
    var spacing: CGFloat = 22
    @ViewBuilder var content: () -> Content
    var body: some View {
        FlowLayout(hSpacing: spacing, vSpacing: 14, alignment: .bottom) { content() }
    }
}

struct FlowLayout: Layout {
    var hSpacing: CGFloat = 8
    var vSpacing: CGFloat = 8
    var alignment: VerticalAlignment = .center

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = layoutRows(proposal.width ?? .infinity, subviews)
        let h = rows.reduce(0) { $0 + $1.height } + CGFloat(max(0, rows.count - 1)) * vSpacing
        let w = rows.map { $0.width }.max() ?? 0
        return CGSize(width: proposal.width ?? w, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in layoutRows(bounds.width, subviews) {
            var x = bounds.minX
            for (i, size) in row.items {
                let dy: CGFloat
                switch alignment {
                case .bottom: dy = row.height - size.height
                case .top: dy = 0
                default: dy = (row.height - size.height) / 2
                }
                subviews[i].place(at: CGPoint(x: x, y: y + dy), proposal: ProposedViewSize(size))
                x += size.width + hSpacing
            }
            y += row.height + vSpacing
        }
    }

    private struct Row { var items: [(Int, CGSize)] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func layoutRows(_ maxWidth: CGFloat, _ subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for (i, sv) in subviews.enumerated() {
            let size = sv.sizeThatFits(.unspecified)
            var row = rows[rows.count - 1]
            let needed = row.items.isEmpty ? size.width : row.width + hSpacing + size.width
            if !row.items.isEmpty && needed > maxWidth {
                rows.append(Row(items: [(i, size)], width: size.width, height: size.height))
            } else {
                row.items.append((i, size))
                row.width = needed
                row.height = max(row.height, size.height)
                rows[rows.count - 1] = row
            }
        }
        return rows
    }
}

// MARK: - segmented control

struct SegOption<T: Hashable>: Identifiable {
    let value: T
    let label: String
    var id: T { value }
    init(_ value: T, _ label: String) { self.value = value; self.label = label }
}

struct Segmented<T: Hashable>: View {
    let options: [SegOption<T>]
    @Binding var selection: T
    var big = false
    var onChange: ((T) -> Void)? = nil

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { o in
                let on = o.value == selection
                Button {
                    selection = o.value
                    onChange?(o.value)
                } label: {
                    Text(o.label)
                        .font(.system(size: big ? 15 : 13, weight: .semibold))
                        .foregroundStyle(on ? Theme.ink : Theme.segText)
                        .padding(.vertical, big ? 10 : 7).padding(.horizontal, big ? 16 : 12)
                        .background(on ? Color.white : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                        .shadow(color: on ? .black.opacity(0.12) : .clear, radius: 1.5, y: 1)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Theme.soft)
        .clipShape(RoundedRectangle(cornerRadius: 11))
    }
}

// MARK: - buttons

enum GQButtonStyle { case primary, normal, ghost }

struct GQButton: View {
    let title: String
    var icon: String? = nil
    var style: GQButtonStyle = .normal
    var small = false
    var disabled = false
    let action: () -> Void

    init(_ title: String, icon: String? = nil, style: GQButtonStyle = .normal, small: Bool = false, disabled: Bool = false, action: @escaping () -> Void) {
        self.title = title; self.icon = icon; self.style = style; self.small = small; self.disabled = disabled; self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.system(size: small ? 12 : 14, weight: .bold)) }
                Text(title).font(.system(size: small ? 13 : 15, weight: .semibold))
            }
            .padding(.vertical, small ? 6 : 9).padding(.horizontal, small ? 11 : 15)
            .foregroundStyle(style == .primary ? .white : (style == .ghost ? Theme.segText : Theme.ink))
            .background(style == .primary ? Theme.accent : (style == .ghost ? Color.clear : Color.white))
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(style == .primary ? Theme.accent : (style == .ghost ? Color.clear : Theme.line), lineWidth: 1))
            .opacity(disabled ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

struct Chip: View {
    let text: String
    var on = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(text).font(.system(size: 13, weight: .semibold)).foregroundStyle(on ? .white : Theme.ink)
                .padding(.vertical, 5).padding(.horizontal, 10)
                .background(on ? Theme.ink : Color.white)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Key chips (`.key-btn`): white, dark when selected.
struct KeyButton: View {
    let text: String
    var on: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(text).font(.system(size: 14, weight: .bold)).foregroundStyle(on ? .white : Theme.ink)
                .frame(minWidth: 42).padding(.vertical, 7).padding(.horizontal, 8)
                .background(on ? Theme.ink : Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(on ? Theme.ink : Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct KeyChips: View {
    let keys: [String]
    let value: String
    var suffix = ""
    var naming: Naming = .letters
    let onPick: (String) -> Void
    var body: some View {
        FlowLayout(hSpacing: 4, vSpacing: 4) {
            ForEach(keys, id: \.self) { k in
                KeyButton(text: Theory.noteLabel(Theory.parseNote(k), naming) + suffix, on: k == value) { onPick(k) }
            }
        }
    }
}

/// Tag pill (`.tag`).
struct Tag: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.teal)
            .padding(.vertical, 2).padding(.horizontal, 8).background(Theme.tealSoft).clipShape(Capsule())
    }
}

// MARK: - note badge

struct NoteBadge: View {
    let label: String
    let hex: UInt32
    var small = false

    init(spelled: SpelledNote, settings: Settings, small: Bool = false) {
        label = Theory.noteLabel(spelled, settings.naming)
        hex = Theme.spelledHex(spelled)
        self.small = small
    }
    init(pc: Int, settings: Settings, small: Bool = false) {
        label = Theory.pcLabel(pc, settings.naming, settings.accidentals)
        hex = Theme.pcHex(pc)
        self.small = small
    }
    init(label: String, hex: UInt32, small: Bool = false) { self.label = label; self.hex = hex; self.small = small }

    var body: some View {
        Text(label).font(.system(size: small ? 13 : 15, weight: .heavy)).foregroundStyle(Theme.inkOn(hex))
            .frame(minWidth: small ? 24 : 30, minHeight: small ? 22 : 28)
            .padding(.horizontal, small ? 6 : 8)
            .background(Color(hex: hex))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// The big coloured note (`.big-note`).
struct BigNote: View {
    let label: String
    let hex: UInt32
    var body: some View {
        Text(label).font(.system(size: 38, weight: .black)).foregroundStyle(Theme.inkOn(hex))
            .frame(minWidth: 84, minHeight: 84).padding(.horizontal, 16)
            .background(Color(hex: hex))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).inset(by: 2).stroke(Color.black.opacity(0.12), lineWidth: 0).offset(y: 2))
    }
}

/// Answer pad button (`.pad-btn`).
struct PadButton: View {
    let label: String
    let hex: UInt32
    var sharp = false
    var state: PadState = .none
    let action: () -> Void
    enum PadState { case none, good, bad }
    var body: some View {
        Button(action: action) {
            Text(label).font(.system(size: sharp ? 15 : 22, weight: .black)).foregroundStyle(Theme.inkOn(hex))
                .frame(minWidth: sharp ? 76 : 62, minHeight: 58).padding(.horizontal, 12)
                .background(Color(hex: hex))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(state == .good ? Theme.good : (state == .bad ? Theme.bad : .clear), lineWidth: 4).padding(-4))
                .opacity(state == .bad ? 0.6 : 1)
                .shadow(color: .black.opacity(0.08), radius: 3, y: 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - stars

struct Stars: View {
    let count: Int
    var size: CGFloat = 20
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { k in
                Image(systemName: "star.fill").font(.system(size: size * 0.85)).foregroundStyle(k < count ? Theme.gold : Color(hex: 0xDCD5C8))
            }
        }
    }
}

struct HudStat: View {
    let icon: String
    let value: String
    var color: Color = Color(hex: 0xB88A00)
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 18, weight: .bold))
            Text(value).font(.system(size: 18, weight: .black))
        }
        .foregroundStyle(color)
    }
}

/// Feedback banner (`.feedback`).
struct FeedbackText: View {
    enum Kind { case none, good, bad, hint }
    let text: String
    let kind: Kind
    var body: some View {
        Group {
            if text.isEmpty {
                Color.clear.frame(height: 30)
            } else {
                Text(text).font(.system(size: 16, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(kind == .good ? Color(hex: 0x1B6B3C) : kind == .bad ? Color(hex: 0x9B2C2C) : kind == .hint ? Color(hex: 0x7A5B00) : Theme.ink)
                    .padding(.vertical, 8).padding(.horizontal, 12)
                    .frame(maxWidth: 900)
                    .background(kind == .good ? Theme.goodSoft : kind == .bad ? Theme.badSoft : kind == .hint ? Color(hex: 0xFFF6D8) : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - transport buttons

struct TransportButton: View {
    var icon: String? = nil
    var label: String? = nil
    var on = false
    var isToggle = false
    var play = false
    var small = false
    var help = ""
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.system(size: play ? 22 : (small ? 12 : 14), weight: .bold)) }
                if let label { Text(label).font(.system(size: small ? 13 : 14, weight: .semibold)) }
            }
            .frame(minWidth: play ? 52 : nil, minHeight: play ? 46 : (small ? 32 : 38))
            .padding(.horizontal, play ? 0 : (small ? 9 : 12))
            .foregroundStyle(play ? .white : (isToggle ? (on ? Theme.teal : Color(hex: 0x8A90A0)) : Theme.ink))
            .background(play ? (on ? Theme.ink : Theme.accent) : (isToggle && on ? Theme.tealSoft : Color.white))
            .clipShape(RoundedRectangle(cornerRadius: play ? 14 : 10))
            .overlay(RoundedRectangle(cornerRadius: play ? 14 : 10).stroke(play ? .clear : (isToggle && on ? Color(hex: 0xA7DADD) : Theme.line), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - toast

struct ToastView: View {
    let message: String
    var body: some View {
        Text(message).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
            .padding(.vertical, 10).padding(.horizontal, 18)
            .background(Theme.ink).clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - helpers

extension View {
    /// Grid of equal columns (CSS grid-template-columns: repeat(n, 1fr)).
    func columns(_ n: Int, spacing: CGFloat = 16) -> [GridItem] { Array(repeating: GridItem(.flexible(), spacing: spacing), count: n) }
}

struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
