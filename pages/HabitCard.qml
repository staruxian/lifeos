import QtQuick
import "../components"
import "../Model.js" as Model

// A habit with its history: name, flame when on a streak, today's control,
// and eighteen weeks of GitHub-style squares.
Card {
  id: root

  property var habit: null
  property var host: null
  property bool first: false
  property bool last: false

  width: parent ? parent.width : implicitWidth
  hoverable: true
  spacing: Theme.s(12)

  Item {
    width: parent.width
    height: Math.max(heading.implicitHeight, control.implicitHeight)

    Column {
      id: heading
      anchors.left: parent.left
      anchors.right: tools.left
      anchors.rightMargin: Theme.s(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Theme.s(2)

      Row {
        spacing: Theme.s(6)
        width: parent.width

        Text {
          id: name
          anchors.verticalCenter: parent.verticalCenter
          width: Math.min(implicitWidth, parent.width - (flame.visible ? flame.width + parent.spacing : 0))
          text: root.habit ? root.habit.name : ""
          color: Theme.label
          font.family: Theme.font
          font.pixelSize: Theme.headline
          font.weight: Font.DemiBold
          elide: Text.ElideRight
        }

        Flame {
          id: flame
          anchors.verticalCenter: parent.verticalCenter
          anchors.verticalCenterOffset: -Theme.s(1)
          visible: root.habit ? root.habit.onFire : false
          streak: root.habit ? root.habit.streak : 0
          size: Theme.s(16)
        }
      }

      Text {
        width: parent.width
        text: {
          if (!root.habit) return ""
          var parts = [Model.habitDetail(root.habit)]
          if (root.habit.rate30 > 0) parts.push(Model.percent(root.habit.rate30) + " this month")
          return parts.join("  ·  ")
        }
        color: Theme.secondary
        font.family: Theme.font
        font.pixelSize: Theme.footnote
        elide: Text.ElideRight
      }
    }

    Row {
      id: tools
      anchors.right: control.left
      anchors.rightMargin: Theme.s(6)
      anchors.verticalCenter: parent.verticalCenter
      spacing: 0
      opacity: root.hovered || remove.armed ? 1 : 0
      visible: opacity > 0
      Behavior on opacity { NumberAnimation { duration: Theme.fast } }

      IconButton {
        visible: !root.first
        icon: "\u{f005d}"
        tooltip: "Move up"
        color: Theme.tertiary
        onClicked: root.host.moveHabit(root.habit.id, -1)
      }
      IconButton {
        visible: !root.last
        icon: "\u{f0045}"
        tooltip: "Move down"
        color: Theme.tertiary
        onClicked: root.host.moveHabit(root.habit.id, 1)
      }
      DeleteButton {
        id: remove
        onConfirmed: root.host.removeHabit(root.habit.id)
      }
    }

    HabitControl {
      id: control
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      habit: root.habit
      host: root.host
    }
  }

  Heatmap {
    anchors.horizontalCenter: parent.horizontalCenter
    habit: root.habit
    // The largest square that fits every week, capped so it stays delicate.
    cell: Math.max(Theme.s(8), Math.min(Theme.s(15), Math.floor((parent.width - labelWidth - gap * (weeks.length - 1)) / Math.max(1, weeks.length))))
  }
}
