// Design tokens and note colours (reference: css/style.css :root, js/ui.js LETTER_COLORS).
import SwiftUI
import MusicCore

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

enum Theme {
    static let bg = Color(hex: 0xF6F2EA)
    static let card = Color.white
    static let ink = Color(hex: 0x1E2230)
    static let muted = Color(hex: 0x697083)
    static let line = Color(hex: 0xE6DED1)
    static let soft = Color(hex: 0xF1ECE3)
    static let accent = Color(hex: 0xE0672B)
    static let accentDark = Color(hex: 0xB94E1A)
    static let accentSoft = Color(hex: 0xFCE7DB)
    static let teal = Color(hex: 0x11808A)
    static let tealSoft = Color(hex: 0xDDF1F2)
    static let good = Color(hex: 0x2E9E5B)
    static let goodSoft = Color(hex: 0xE1F4E8)
    static let bad = Color(hex: 0xD64545)
    static let badSoft = Color(hex: 0xFBE4E4)
    static let gold = Color(hex: 0xF2B705)
    static let radius: CGFloat = 14
    static let topbar = Color(hex: 0x1E2230)
    static let segText = Color(hex: 0x4A5163)

    // One colour per note letter (C..B), used on the fretboard, staff and tab.
    static let letterHex: [UInt32] = [0xE53935, 0xF57C00, 0xE8B100, 0x43A047, 0x0097A7, 0x5E35B1, 0xD81B60]
    static let accHex: UInt32 = 0x546E7A
    static let plainNoteHex: UInt32 = 0x37474F   // used when note colours are switched off

    static func letterHex(_ l: Int) -> UInt32 { letterHex[l] }
    static func pcHex(_ pc: Int) -> UInt32 { Theory.isNaturalPc(pc) ? letterHex[Theory.spellPc(pc).letter] : accHex }
    static func spelledHex(_ n: SpelledNote) -> UInt32 { n.alter == 0 ? letterHex[n.letter] : accHex }
    /// Text colour that reads on a note colour (dark on the yellow E).
    static func inkOn(_ hex: UInt32) -> Color { hex == letterHex[2] ? Color(hex: 0x2A2100) : .white }

    static func letterColor(_ l: Int) -> Color { Color(hex: letterHex[l]) }
    static func pcColor(_ pc: Int) -> Color { Color(hex: pcHex(pc)) }
    static func spelledColor(_ n: SpelledNote) -> Color { Color(hex: spelledHex(n)) }

    static let shadow = Color.black.opacity(0.06)
}

extension Font {
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight) }
}
