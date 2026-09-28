import QtQuick
import qs.Ui
import "../components"
import "../Model.js" as Model

// What your history says: a few plain sentences, the last month of
// check-ins, how each weekday goes, and every habit's best run.
ViewBase {
  id: root

  readonly property var ins: snap ? snap.insights : null
  readonly property var moodFaces: ["", "😞", "😕", "😐", "🙂", "😄"]
  readonly property var moodColors: ["", "#ff453a", "#ff9f0a", "#8e8e93", "#64d2ff", "#30d158"]
  readonly property var icons: ({ calendar: "\u{f00ed}", up: "\u{f0737}", down: "\u{f0734}", book: "\u{f00ba}", mood: "\u{f0785}", fire: "\u{f0238}", check: "\u{f012c}" })

  Lead {
    title: "What your days say"
    subtitle: root.ins && root.ins.lines.length ? "Patterns from the last twelve weeks." : "Keep logging for a couple of weeks and patterns will show up here."
  }

  Card {
    visible: root.ins !== null && root.ins.lines.length > 0
    width: parent.width
    padding: Theme.s(4)
    spacing: 0

    Repeater {
      model: root.ins ? root.ins.lines : []
      Column {
        required property var modelData
        required property int index
        width: parent.width
        Rectangle { visible: index > 0; x: Theme.s(44); width: parent.width - x; height: 1; color: Theme.separator }
        Item {
          width: parent.width
          height: line.implicitHeight + Theme.s(22)
          Text {
            textFormat: Text.PlainText
            id: glyph
            anchors.left: parent.left
            anchors.leftMargin: Theme.s(14)
            anchors.verticalCenter: parent.verticalCenter
            text: root.icons[modelData.icon] || "\u{f02fc}"
            color: modelData.icon === "down" ? Theme.danger : modelData.icon === "fire" ? Theme.fire : Theme.good
            font.family: Theme.iconFont
            font.pixelSize: Theme.headline
          }
          Text {
            textFormat: Text.PlainText
            id: line
            anchors.left: parent.left
            anchors.leftMargin: Theme.s(44)
            anchors.right: parent.right
            anchors.rightMargin: Theme.s(14)
            anchors.verticalCenter: parent.verticalCenter
            text: modelData.text
            color: Theme.label
            font.family: Theme.font
            font.pixelSize: Theme.body
            wrapMode: Text.WordWrap
            lineHeight: 1.12
          }
        }
      }
    }
  }

  // Thirty days of check-ins as a strip of coloured dots.
  Column {
    width: parent.width
    spacing: Theme.s(6)

    SectionHeader {
      text: "How the days felt"
      trailing: {
        if (!root.ins) return ""
        var rated = root.ins.mood.filter(function(m) { return m.mood !== null })
        if (!rated.length) return "check in at shutdown"
        var sum = 0
        for (var i = 0; i < rated.length; i++) sum += rated[i].mood
        return "average " + (sum / rated.length).toFixed(1) + " · " + rated.length + " days"
      }
    }

    Card {
      width: parent.width
      padding: Theme.s(14)

      Row {
        id: strip
        spacing: Theme.s(3)
        readonly property real dot: (parent.width - spacing * 29) / 30

        Repeater {
          model: root.ins ? root.ins.mood : []
          Rectangle {
            required property var modelData
            width: strip.dot
            height: Theme.s(28)
            radius: Math.min(width / 2, Theme.s(4))
            anchors.bottom: parent.bottom
            color: modelData.mood ? root.moodColors[modelData.mood] : Theme.fillStrong
            opacity: modelData.mood ? 0.35 + modelData.mood * 0.13 : 1

            HoverHandler { id: moodHover }
            PanelToolTip {
              visible: moodHover.hovered && modelData.mood !== null
              text: Model.shortDate(modelData.day, true) + "  " + (modelData.mood ? root.moodFaces[modelData.mood] : "") + (modelData.note ? "  " + modelData.note : "")
              fontFamily: Theme.font
            }
          }
        }
      }
    }
  }

  // Habits by weekday.
  Column {
    visible: root.ins !== null && root.ins.weekdays.some(function(w) { return w.due > 0 })
    width: parent.width
    spacing: Theme.s(6)

    SectionHeader { text: "Habits by weekday"; trailing: "last 12 weeks" }

    Card {
      width: parent.width
      padding: Theme.s(14)

      Row {
        id: bars
        spacing: Theme.s(8)
        readonly property real barWidth: (parent.width - spacing * 6) / 7

        Repeater {
          model: root.ins ? root.ins.weekdays : []
          Column {
            required property var modelData
            required property int index
            width: bars.barWidth
            spacing: Theme.s(6)

            Item {
              width: parent.width
              height: Theme.s(64)
              Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: Math.max(Theme.s(3), parent.height * modelData.rate)
                radius: Math.min(width / 2, Theme.s(5))
                color: modelData.due === 0 ? Theme.fillStrong : Theme.alpha(Theme.good, 0.35 + modelData.rate * 0.65)
                Behavior on height { NumberAnimation { duration: Theme.slow; easing.type: Easing.OutCubic } }
              }
            }
            Text {
              textFormat: Text.PlainText
              anchors.horizontalCenter: parent.horizontalCenter
              text: Model.WEEKDAYS[index].charAt(0)
              color: Theme.tertiary
              font.family: Theme.font
              font.pixelSize: Theme.caption
              font.weight: Font.DemiBold
            }
          }
        }
      }
    }
  }

  // Best runs.
  Column {
    visible: root.ins !== null && root.ins.records.length > 0
    width: parent.width
    spacing: Theme.s(6)

    SectionHeader { text: "Best runs" }
    Card {
      width: parent.width
      padding: Theme.s(3)
      spacing: 0
      Repeater {
        model: root.ins ? root.ins.records : []
        Column {
          required property var modelData
          required property int index
          width: parent.width
          Rectangle { visible: index > 0; x: Theme.s(12); width: parent.width - x; height: 1; color: Theme.separator }
          Item {
            width: parent.width
            height: Theme.rowHeight + Theme.s(2)
            Text { textFormat: Text.PlainText; anchors.left: parent.left; anchors.leftMargin: Theme.s(12); anchors.verticalCenter: parent.verticalCenter; text: modelData.name; color: Theme.label; font.family: Theme.font; font.pixelSize: Theme.body }
            Row {
              anchors.right: parent.right
              anchors.rightMargin: Theme.s(12)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Theme.s(8)
              Text {
                textFormat: Text.PlainText
                anchors.verticalCenter: parent.verticalCenter
                visible: modelData.current > 0
                text: "now " + modelData.current
                color: Theme.tertiary
                font.family: Theme.font
                font.pixelSize: Theme.footnote
              }
              Text {
                textFormat: Text.PlainText
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.best + (modelData.best === 1 ? " day" : " days")
                color: modelData.current >= modelData.best ? Theme.fire : Theme.label
                font.family: Theme.font
                font.pixelSize: Theme.body
                font.weight: Font.DemiBold
                font.features: ({ "tnum": 1 })
              }
            }
          }
        }
      }
    }
  }
}
