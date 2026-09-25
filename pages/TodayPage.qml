import QtQuick
import "../components"
import "../Model.js" as Model

// Everything that matters today, on one page.
PageBase {
  id: root

  readonly property var s: snap ? snap.summary : null
  readonly property var habits: snap ? snap.habits.filter(function(h) { return h.scheduledToday }) : []
  readonly property var tasks: snap ? snap.tasks.overdue.concat(snap.tasks.today).concat(snap.tasks.doneToday) : []
  readonly property var book: snap && snap.books.reading.length ? snap.books.reading[0] : null
  readonly property var nextEvent: s ? s.nextEvent : null
  readonly property bool blank: snap !== null && snap.habits.length === 0 && tasks.length === 0 && !book && !nextEvent
    && snap.tasks.upcoming.length === 0 && snap.tasks.someday.length === 0
  readonly property bool allDone: s !== null && !blank && s.habitsDone === s.habitsDue && s.tasksLeft === 0
    && (s.habitsDue + s.tasksDoneToday) > 0

  function focusAdd() { taskField.focusInput() }

  spacing: Theme.s(16)

  // ---- all clear
  Rectangle {
    visible: root.allDone
    width: parent.width
    height: Theme.s(44)
    radius: Theme.radius
    color: Theme.alpha(Theme.good, 0.14)

    Row {
      anchors.centerIn: parent
      spacing: Theme.s(8)
      Text { anchors.verticalCenter: parent.verticalCenter; text: "\u{f0e1e}"; color: Theme.good; font.family: Theme.iconFont; font.pixelSize: Theme.headline }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "Everything done for today"
        color: Theme.good
        font.family: Theme.font
        font.pixelSize: Theme.body
        font.weight: Font.DemiBold
      }
    }
  }

  // ---- next countdown
  EventCard {
    visible: root.nextEvent !== null
    event: root.nextEvent
    host: root.host
    removable: false
    onActivated: root.navigate("events", false)
  }

  // ---- habits due today
  Column {
    visible: root.habits.length > 0
    width: parent.width
    spacing: Theme.s(6)

    SectionHeader { text: "Habits"; trailing: root.s ? root.s.habitsDone + " of " + root.s.habitsDue : "" }

    Card {
      width: parent.width
      padding: Theme.s(3)
      spacing: 0

      Repeater {
        model: root.habits
        Column {
          required property var modelData
          required property int index
          width: parent.width
          Hairline { visible: index > 0; inset: Theme.s(10) }
          HabitRow { habit: modelData; host: root.host }
        }
      }
    }
  }

  // ---- today's tasks, with a quick add that lands on today
  Column {
    visible: root.snap !== null && !root.blank
    width: parent.width
    spacing: Theme.s(6)

    SectionHeader {
      text: "Tasks"
      trailing: !root.s ? "" : root.s.tasksLeft > 0 ? root.s.tasksLeft + " left" : root.s.tasksDoneToday > 0 ? "all done" : ""
      color: root.s && root.s.overdue > 0 ? Theme.danger : Theme.tertiary
    }

    Card {
      width: parent.width
      padding: Theme.s(3)
      spacing: 0

      Repeater {
        model: root.tasks
        Column {
          required property var modelData
          required property int index
          width: parent.width
          Hairline { visible: index > 0; inset: Theme.s(40) }
          TaskRow { task: modelData; host: root.host; showDue: modelData.daysUntil !== 0 }
        }
      }

      Hairline { visible: root.tasks.length > 0; inset: Theme.s(40) }

      Item {
        width: parent.width
        height: Theme.rowHeight + Theme.s(2)

        Text {
          id: plus
          anchors.left: parent.left
          anchors.leftMargin: Theme.s(11)
          anchors.verticalCenter: parent.verticalCenter
          text: "\u{f0415}"
          color: taskField.input.activeFocus ? Theme.good : Theme.tertiary
          font.family: Theme.iconFont
          font.pixelSize: Theme.headline
        }

        Field {
          id: taskField
          anchors.left: plus.right
          anchors.leftMargin: Theme.s(4)
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          color: "transparent"
          border.width: 0
          placeholder: "Add a task for today"
          onSubmitted: function(text) { root.host.addTask(text, "today") }
        }
      }
    }
  }

  // ---- the book on the nightstand
  Column {
    visible: root.book !== null
    width: parent.width
    spacing: Theme.s(6)

    SectionHeader { text: "Reading"; trailing: root.book && root.book.today > 0 ? "+" + root.book.today + " today" : "" }
    BookCard { book: root.book; host: root.host; compact: true }
  }

  // ---- first run
  Column {
    visible: root.blank
    width: parent.width
    spacing: Theme.s(14)

    EmptyState {
      icon: "\u{f0cae}"
      title: "Welcome to LifeOS"
      hint: "Your tasks, habits, reading and countdowns live here. Start with one:"
    }

    Grid {
      anchors.horizontalCenter: parent.horizontalCenter
      columns: 2
      spacing: Theme.s(8)

      Repeater {
        model: [
          { key: "tasks", icon: "\u{f0134}", label: "Add a task" },
          { key: "habits", icon: "\u{f0e74}", label: "Build a habit" },
          { key: "books", icon: "\u{f00ba}", label: "Track a book" },
          { key: "events", icon: "\u{f00f0}", label: "Count down" }
        ]
        PillButton {
          required property var modelData
          width: Theme.s(170)
          primary: false
          icon: modelData.icon
          text: modelData.label
          onClicked: root.navigate(modelData.key, true)
        }
      }
    }
  }
}
