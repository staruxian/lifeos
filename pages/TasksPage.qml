import QtQuick
import "../components"

PageBase {
  id: root

  readonly property var t: snap ? snap.tasks : null
  readonly property int openCount: t ? t.overdue.length + t.today.length + t.upcoming.length + t.someday.length : 0
  property string due: ""

  readonly property var presets: [
    { key: "", label: "No date" },
    { key: "today", label: "Today" },
    { key: "tomorrow", label: "Tomorrow" },
    { key: "sat", label: "Weekend" },
    { key: "next mon", label: "Next week" }
  ]

  function focusAdd() { field.focusInput() }

  Column {
    width: parent.width
    spacing: Theme.s(8)

    Field {
      id: field
      width: parent.width
      icon: "\u{f0415}"
      placeholder: "New task"
      onSubmitted: function(text) { root.host.addTask(text, root.due) }
    }

    // Due presets appear while you are writing a task.
    Flow {
      width: parent.width
      spacing: Theme.s(6)
      visible: height > 0
      height: field.input.activeFocus || field.text !== "" ? implicitHeight : 0
      clip: true
      Behavior on height { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }

      Repeater {
        model: root.presets
        Chip {
          required property var modelData
          text: modelData.label
          selected: root.due === modelData.key
          onClicked: { root.due = modelData.key; field.focusInput() }
        }
      }
    }
  }

  TaskList { title: "Overdue"; titleColor: Theme.danger; tasks: root.t ? root.t.overdue : []; host: root.host }
  TaskList { title: "Today"; tasks: root.t ? root.t.today : []; host: root.host; showDue: false }
  TaskList { title: "Upcoming"; tasks: root.t ? root.t.upcoming : []; host: root.host }
  TaskList { title: "Someday"; tasks: root.t ? root.t.someday : []; host: root.host }
  TaskList {
    title: "Done today"
    trailing: root.t && root.t.doneToday.length ? String(root.t.doneToday.length) : ""
    tasks: root.t ? root.t.doneToday : []
    host: root.host
    showDue: false
  }

  EmptyState {
    visible: root.t !== null && root.openCount === 0 && root.t.doneToday.length === 0
    icon: "\u{f0134}"
    title: "Nothing on your list"
    hint: "Type a task above and press Enter. Pick a day to see it under Today."
  }
}
