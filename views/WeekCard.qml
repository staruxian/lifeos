import QtQuick
import "../components"
import "../Model.js" as Model

// A week in one card: the share of promises kept as a ring, then the
// details — perfect days, tasks, pages, the best habit and the one that
// needs attention, and how it compares with the week before.
Card {
  id: root

  property var week: null
  property var previous: null
  property string title: "This week"

  readonly property int percent: week ? Math.round(week.rate * 100) : 0
  readonly property int delta: week && previous && previous.due > 0 && week.due > 0 ? Math.round((week.rate - previous.rate) * 100) : 0

  width: parent ? parent.width : implicitWidth
  spacing: Theme.s(14)

  Item {
    width: parent.width
    height: ring.height

    Ring {
      id: ring
      anchors.left: parent.left
      size: Theme.s(76)
      lineWidth: Theme.s(8)
      value: root.week ? root.week.rate : 0
      color: root.percent >= 80 ? Theme.good : root.percent >= 50 ? Theme.fire : Theme.danger

      Text {
        anchors.centerIn: parent
        text: root.week && root.week.due > 0 ? root.percent + "%" : "—"
        color: Theme.label
        font.family: Theme.font
        font.pixelSize: Theme.headline
        font.weight: Font.Bold
        font.features: ({ "tnum": 1 })
      }
    }

    Column {
      anchors.left: ring.right
      anchors.leftMargin: Theme.s(16)
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Theme.s(3)

      Text {
        text: root.title.toUpperCase()
        color: Theme.tertiary
        font.family: Theme.font
        font.pixelSize: Theme.caption
        font.weight: Font.DemiBold
        font.letterSpacing: 0.9
      }
      Text {
        width: parent.width
        text: !root.week || root.week.due === 0 ? "Nothing promised yet"
          : root.week.kept + " of " + root.week.due + " promises kept"
        color: Theme.label
        font.family: Theme.font
        font.pixelSize: Theme.headline
        font.weight: Font.DemiBold
        wrapMode: Text.WordWrap
      }
      Text {
        visible: root.delta !== 0
        text: (root.delta > 0 ? "▲ " : "▼ ") + Math.abs(root.delta) + "% vs the week before"
        color: root.delta > 0 ? Theme.good : Theme.danger
        font.family: Theme.font
        font.pixelSize: Theme.footnote
        font.weight: Font.Medium
      }
    }
  }

  Row {
    width: parent.width
    spacing: Theme.s(8)

    Repeater {
      model: root.week ? [
        { n: root.week.perfectDays, label: root.week.perfectDays === 1 ? "perfect day" : "perfect days" },
        { n: root.week.tasksDone, label: root.week.tasksDone === 1 ? "task done" : "tasks done" },
        { n: root.week.pages, label: root.week.pages === 1 ? "page read" : "pages read" }
      ] : []

      Rectangle {
        required property var modelData
        width: (parent.width - parent.spacing * 2) / 3
        height: Theme.s(56)
        radius: Theme.radiusControl
        color: Theme.fill

        Column {
          anchors.centerIn: parent
          spacing: Theme.s(1)
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: String(modelData.n)
            color: Theme.label
            font.family: Theme.font
            font.pixelSize: Theme.title
            font.weight: Font.Bold
            font.features: ({ "tnum": 1 })
          }
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: modelData.label
            color: Theme.tertiary
            font.family: Theme.font
            font.pixelSize: Theme.caption
          }
        }
      }
    }
  }

  Text {
    visible: root.week !== null && (root.week.best !== null || root.week.worst !== null)
    width: parent.width
    text: {
      if (!root.week) return ""
      var parts = []
      if (root.week.best) parts.push("Strongest: " + root.week.best.name + " " + Model.percent(root.week.best.rate))
      if (root.week.worst) parts.push("Needs attention: " + root.week.worst.name + " " + Model.percent(root.week.worst.rate))
      return parts.join("   ·   ")
    }
    color: Theme.secondary
    font.family: Theme.font
    font.pixelSize: Theme.footnote
    wrapMode: Text.WordWrap
  }
}
