import QtQuick
import "../components"

PageBase {
  id: root

  readonly property var habits: snap ? snap.habits : []

  function focusAdd() { newHabit.openForm() }

  spacing: Theme.s(10)

  Repeater {
    model: root.habits
    HabitCard {
      required property var modelData
      required property int index
      habit: modelData
      host: root.host
      first: index === 0
      last: index === root.habits.length - 1
    }
  }

  EmptyState {
    visible: root.snap !== null && root.habits.length === 0 && !newHabit.expanded
    icon: "\u{f0e74}"
    title: "Build a habit"
    hint: "Something to do, a number to reach, or something to avoid. Keep it going for three days and it catches fire."
  }

  NewHabit { id: newHabit; host: root.host }
}
