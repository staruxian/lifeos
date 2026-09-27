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
  property bool editing: false
  // The habit as it was when editing began, so a refresh cannot reset the form.
  property var editTarget: null
  // Strict mode: a habit with a streak is only deleted by typing its name.
  property bool confirmingDelete: false

  function requestDelete() {
    if (root.host && root.host.strict && root.habit.streak > 0) {
      root.confirmingDelete = true
      Qt.callLater(confirmField.focusInput)
    } else root.host.removeHabit(root.habit.id)
  }

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
      opacity: (root.hovered || remove.armed) && !root.editing ? 1 : 0
      visible: opacity > 0
      Behavior on opacity { NumberAnimation { duration: Theme.fast } }

      IconButton {
        visible: root.habit && root.habit.scheduledToday && root.habit.canSkip && !root.habit.done && !root.habit.skipped
        icon: "\u{f04ad}"
        tooltip: "Skip today — once a week, keeps the streak"
        color: Theme.tertiary
        onClicked: root.host.skipHabit(root.habit.id)
      }
      IconButton {
        icon: "\u{f03eb}"
        tooltip: "Edit"
        color: Theme.tertiary
        onClicked: { root.editTarget = root.habit; root.editing = true }
      }
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
        onConfirmed: root.requestDelete()
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

  // Strict delete: type the name to let a streak go.
  Column {
    visible: root.confirmingDelete
    width: parent.width
    spacing: Theme.s(8)

    Text {
      width: parent.width
      text: "This habit is on a " + (root.habit ? root.habit.streak : 0) + "-day streak. Type “" + (root.habit ? root.habit.name : "") + "” to delete it."
      color: Theme.danger
      font.family: Theme.font
      font.pixelSize: Theme.footnote
      wrapMode: Text.WordWrap
    }
    Field {
      id: confirmField
      width: parent.width
      placeholder: root.habit ? root.habit.name : ""
      clearOnSubmit: false
      onSubmitted: function(text) {
        if (text.trim().toLowerCase() === root.habit.name.trim().toLowerCase()) {
          root.confirmingDelete = false
          root.host.removeHabit(root.habit.id)
        }
      }
      onEscaped: { clear(); root.confirmingDelete = false }
    }
  }

  NewHabit {
    visible: root.editing
    width: parent.width
    host: root.host
    habit: root.editing ? root.editTarget : null
    color: "transparent"
    padding: 0
    onClosed: root.editing = false
  }

  Heatmap {
    visible: !root.editing
    anchors.horizontalCenter: parent.horizontalCenter
    habit: root.habit
    // The largest square that fits every week, capped so it stays delicate.
    cell: Math.max(Theme.s(8), Math.min(Theme.s(15), Math.floor((parent.width - labelWidth - gap * (weeks.length - 1)) / Math.max(1, weeks.length))))
  }
}
