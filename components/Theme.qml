pragma Singleton
import QtQuick
import qs.Commons

// LifeOS design tokens. Colors come from the active Omarchy theme so the
// panel follows every theme switch; shape, type and motion are LifeOS's own.
QtObject {
  id: root

  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
  function s(px) { return Math.round(px * Style.fontScale) }

  // ---- color
  readonly property color fg: Color.popups.text
  readonly property color bg: Color.popups.background
  readonly property color accent: Color.accent
  readonly property color urgent: Color.urgent

  // Progress reads as green on monochrome themes, as the theme accent on
  // themes that have a real color to offer.
  readonly property color good: accent.hslSaturation > 0.3 && accent.hslLightness > 0.25 ? accent : "#30d158"
  readonly property color fire: "#ff9f0a"
  readonly property color fireCore: "#ffd60a"
  readonly property color danger: urgent.hslSaturation > 0.2 ? urgent : "#ff453a"

  readonly property color label: fg
  readonly property color secondary: alpha(fg, 0.6)
  readonly property color tertiary: alpha(fg, 0.36)
  readonly property color quaternary: alpha(fg, 0.16)
  readonly property color fill: alpha(fg, 0.045)
  readonly property color fillHover: alpha(fg, 0.08)
  readonly property color fillStrong: alpha(fg, 0.12)
  readonly property color separator: alpha(fg, 0.075)

  // ---- type
  readonly property string font: {
    var families = Qt.fontFamilies()
    var wanted = ["Inter", "Inter Variable", "SF Pro Text", "Geist", "Noto Sans"]
    for (var i = 0; i < wanted.length; i++) if (families.indexOf(wanted[i]) >= 0) return wanted[i]
    return Style.font.family
  }
  readonly property string iconFont: Style.font.family
  readonly property string emojiFont: "Noto Color Emoji"

  readonly property int largeTitle: s(26)
  readonly property int title: s(19)
  readonly property int headline: s(14)
  readonly property int body: s(13)
  readonly property int callout: s(12)
  readonly property int footnote: s(11)
  readonly property int caption: s(10)

  // ---- shape
  readonly property int radius: s(14)
  readonly property int radiusControl: s(9)
  readonly property int radiusSmall: s(6)
  readonly property int gap: s(8)
  readonly property int pad: s(14)
  readonly property int rowHeight: s(34)
  readonly property int controlHeight: s(30)

  // ---- motion
  readonly property int fast: 120
  readonly property int normal: 220
  readonly property int slow: 360

  // Text inputs claim the keyboard from the panel's shortcut catcher.
  property var focusedField: null
}
