import QtQuick
import "../components"

// Today's input for a habit, whatever its kind: a check, a counter, or a
// "slipped" toggle for things you are staying away from.
Item {
  id: root

  property var habit: null
  property var host: null

  implicitWidth: loader.item ? loader.item.implicitWidth : 0
  implicitHeight: loader.item ? loader.item.implicitHeight : 0

  Loader {
    id: loader
    anchors.centerIn: parent
    sourceComponent: !root.habit ? null : root.habit.kind === "count" ? counter : root.habit.kind === "avoid" ? avoid : check
  }

  Component {
    id: check
    CheckCircle {
      size: Theme.s(24)
      checked: root.habit.done
      onToggled: root.host.toggleHabit(root.habit.id)
    }
  }

  Component {
    id: counter
    Stepper {
      value: root.habit.value
      target: root.habit.target
      onStep: function(delta) { root.host.stepHabit(root.habit.id, delta) }
    }
  }

  Component {
    id: avoid
    Chip {
      readonly property bool slipped: root.habit.value > 0
      text: slipped ? "Slipped" : "Clean"
      icon: slipped ? "\u{f0156}" : "\u{f012c}"
      selected: true
      tint: slipped ? Theme.danger : Theme.good
      onClicked: root.host.toggleHabit(root.habit.id)
    }
  }
}
