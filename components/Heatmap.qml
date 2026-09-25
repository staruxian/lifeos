import QtQuick
import qs.Ui
import "../Model.js" as Model

// GitHub-style contribution grid: one column per week, Monday on top, the
// current week at the right. A single hover region drives one tooltip so a
// panel full of habits stays cheap.
Item {
  id: root

  property var habit: null
  property color tint: Theme.good
  property int cell: Theme.s(11)
  property int gap: Theme.s(3)

  readonly property var weeks: habit ? habit.heat : []
  readonly property int pitch: cell + gap
  readonly property int labelWidth: Theme.s(18)
  readonly property int monthHeight: Theme.s(14)

  implicitWidth: labelWidth + weeks.length * pitch - gap
  implicitHeight: monthHeight + 7 * pitch - gap

  function cellColor(c) {
    switch (c.state) {
      case "future": return "transparent"
      case "before": return Theme.alpha(Theme.fg, 0.025)
      case "off": return Theme.alpha(Theme.fg, 0.035)
      case "empty": return Theme.alpha(Theme.fg, 0.07)
      case "slip": return Theme.alpha(Theme.danger, 0.85)
      case "clean": return Theme.alpha(root.tint, 0.75)
    }
    return Theme.alpha(root.tint, [0.07, 0.3, 0.5, 0.72, 1][c.level])
  }

  // Month names over the first week that starts in a new month.
  Repeater {
    model: root.weeks.length

    Text {
      required property int index
      readonly property var first: root.weeks[index][0]
      readonly property var date: Model.parseDay(first.day)
      readonly property bool starts: date && (index === 0 ? date.getDate() <= 21 : date.getDate() <= 7)
      visible: starts && index < root.weeks.length - 1
      x: root.labelWidth + index * root.pitch
      y: 0
      text: date ? Model.MONTHS[date.getMonth()] : ""
      color: Theme.tertiary
      font.family: Theme.font
      font.pixelSize: Theme.caption
    }
  }

  Repeater {
    model: [["Mon", 0], ["Wed", 2], ["Fri", 4]]

    Text {
      required property var modelData
      x: 0
      y: root.monthHeight + modelData[1] * root.pitch + (root.cell - height) / 2
      text: modelData[0].charAt(0)
      color: Theme.tertiary
      font.family: Theme.font
      font.pixelSize: Theme.caption
    }
  }

  Row {
    x: root.labelWidth
    y: root.monthHeight
    spacing: root.gap

    Repeater {
      model: root.weeks

      Column {
        required property var modelData
        spacing: root.gap

        Repeater {
          model: modelData

          Rectangle {
            required property var modelData
            width: root.cell
            height: root.cell
            radius: Math.max(2, root.cell * 0.24)
            color: root.cellColor(modelData)
            Behavior on color { ColorAnimation { duration: Theme.slow } }
          }
        }
      }
    }
  }

  // Today gets a hairline ring so "now" is findable at a glance.
  Rectangle {
    readonly property int week: root.weeks.length - 1
    readonly property int day: {
      if (week < 0) return -1
      var w = root.weeks[week]
      for (var i = 6; i >= 0; i--) if (w[i].state !== "future") return i
      return -1
    }
    visible: day >= 0
    x: root.labelWidth + week * root.pitch - Theme.s(2)
    y: root.monthHeight + day * root.pitch - Theme.s(2)
    width: root.cell + Theme.s(4)
    height: width
    radius: Math.max(3, width * 0.28)
    color: "transparent"
    border.width: 1
    border.color: Theme.secondary
  }

  MouseArea {
    id: hover
    x: root.labelWidth
    y: root.monthHeight
    width: root.weeks.length * root.pitch
    height: 7 * root.pitch
    hoverEnabled: true
    acceptedButtons: Qt.NoButton

    readonly property int col: Math.floor(mouseX / root.pitch)
    readonly property int row: Math.floor(mouseY / root.pitch)
    readonly property var hit: containsMouse && col >= 0 && col < root.weeks.length && row >= 0 && row < 7
      ? root.weeks[col][row] : null
  }

  PanelToolTip {
    visible: hover.hit !== null && hover.hit.state !== "future"
    text: hover.hit ? Model.cellTooltip(root.habit, hover.hit) : ""
    fontFamily: Theme.font
    delay: 150
    x: root.labelWidth + hover.col * root.pitch - width / 2 + root.cell / 2
    y: root.monthHeight + hover.row * root.pitch - height - Theme.s(6)
  }
}
