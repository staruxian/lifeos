import QtQuick
import "../components"
import "../pages"

ViewBase {
  id: root

  readonly property var st: snap ? snap.settings : null
  function on(key) { return root.st ? root.st[key] === "on" : false }

  Column {
    width: parent.width
    spacing: Theme.s(6)

    SectionHeader { text: "Discipline" }
    Card {
      width: parent.width
      padding: Theme.s(3)
      spacing: 0

      SettingRow {
        title: "Strict mode"
        detail: "Only today and yesterday can be logged. The evening shutdown opens on its own. Deleting a habit with a streak asks you to type its name."
        Switch { checked: root.on("strict"); tint: Theme.fire; onToggled: function(v) { root.host.setSetting("strict", v ? "on" : "off") } }
      }
    }
  }

  Column {
    width: parent.width
    spacing: Theme.s(6)

    SectionHeader { text: "Rituals" }
    Card {
      width: parent.width
      padding: Theme.s(3)
      spacing: 0

      SettingRow {
        title: "Plan my day"
        detail: "Ask for up to three priorities each morning. Opens at login until the day is planned."
        Switch { checked: root.on("plan"); onToggled: function(v) { root.host.setSetting("plan", v ? "on" : "off") } }
      }
      Hairline { inset: Theme.s(12) }
      SettingRow {
        title: "Morning"
        detail: "Plan reminder and countdown news."
        TimeSetting { key: "morning"; value: root.st ? root.st.morning : ""; host: root.host }
      }
      Hairline { inset: Theme.s(12) }
      SettingRow {
        title: "Shutdown"
        detail: "Time to give unfinished tasks a place."
        TimeSetting { key: "shutdown"; value: root.st ? root.st.shutdown : ""; host: root.host }
      }
    }
  }

  Column {
    width: parent.width
    spacing: Theme.s(6)

    SectionHeader { text: "Reminders" }
    Card {
      width: parent.width
      padding: Theme.s(3)
      spacing: 0

      // How the notifications talk.
      Column {
        width: parent.width
        topPadding: Theme.s(12)
        bottomPadding: Theme.s(12)
        spacing: Theme.s(8)

        Text {
          textFormat: Text.PlainText
          x: Theme.s(12)
          text: "Tone"
          color: Theme.label
          font.family: Theme.font
          font.pixelSize: Theme.body
          font.weight: Font.Medium
        }
        SegmentedControl {
          x: Theme.s(12)
          width: parent.width - Theme.s(24)
          compact: true
          model: [{ key: "gentle", label: "Gentle" }, { key: "coach", label: "Coach" }, { key: "savage", label: "Savage 🔥" }]
          current: root.st ? root.st.tone : "coach"
          onPicked: function(key) { root.host.setSetting("tone", key) }
        }
        Text {
          textFormat: Text.PlainText
          x: Theme.s(12)
          width: parent.width - Theme.s(24)
          text: {
            var t = root.st ? root.st.tone : "coach"
            if (t === "savage") return "“Get your freaking ass up and go touch some grass. Gym won't do itself.” — and it keeps asking every 45 minutes until you do."
            if (t === "gentle") return "“Time for Gym.” Calm and short."
            return "“Ten minutes in and you'll be glad you went. Gym, let's go.”"
          }
          color: Theme.tertiary
          font.family: Theme.font
          font.pixelSize: Theme.footnote
          font.italic: true
          wrapMode: Text.WordWrap
        }
      }
      Hairline { inset: Theme.s(12) }

      SettingRow {
        title: "Notifications"
        detail: "Plan, habits left, shutdown, and countdowns."
        Switch { checked: root.on("notify"); onToggled: function(v) { root.host.setSetting("notify", v ? "on" : "off") } }
      }
      Hairline { inset: Theme.s(12) }
      SettingRow {
        title: "Habit reminder"
        detail: "If habits are still open. Two hours later the ring turns orange."
        TimeSetting { key: "remind"; value: root.st ? root.st.remind : ""; host: root.host }
      }
      Hairline { inset: Theme.s(12) }
      SettingRow {
        title: "Bedtime"
        detail: "An hour before, a last call — and the ring pulses red."
        TimeSetting { key: "bedtime"; value: root.st ? root.st.bedtime : ""; host: root.host }
      }
    }
  }

  Text {
    textFormat: Text.PlainText
    width: parent.width
    leftPadding: Theme.s(4)
    text: "Keys: n add · p plan · s shutdown · w week · u undo · 1–5 tabs\nQuick add from anywhere: bind  omarchy-shell staruxian.lifeos quickadd"
    color: Theme.tertiary
    font.family: Theme.font
    font.pixelSize: Theme.footnote
    lineHeight: 1.3
    wrapMode: Text.WordWrap
  }
}
