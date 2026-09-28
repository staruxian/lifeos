import QtQuick
import "../components"
import "../Model.js" as Model

// Everything that matters today, on one page.
PageBase {
  id: root

  readonly property var s: snap ? snap.summary : null
  readonly property var habits: snap ? snap.habits.filter(function(h) { return h.scheduledToday }) : []
  readonly property var day: snap ? snap.day : null
  readonly property var priorities: day ? day.priorities : []
  // Priorities have their own section; the task list shows everything else due.
  readonly property var tasks: snap ? snap.tasks.overdue.concat(snap.tasks.today).concat(snap.tasks.doneToday).filter(function(t) { return !t.focus }) : []
  readonly property var book: snap && snap.books.reading.length ? snap.books.reading[0] : null
  readonly property var nextEvent: s ? s.nextEvent : null
  readonly property bool blank: snap !== null && snap.habits.length === 0 && tasks.length === 0 && !book && !nextEvent
    && snap.tasks.upcoming.length === 0 && snap.tasks.someday.length === 0
  readonly property bool allDone: s !== null && !blank && s.dayComplete

  function focusAdd() { taskField.focusInput() }

  spacing: Theme.s(16)

  // ---- the day asking for attention: plan, shut down, or habits left late
  Rectangle {
    id: attention
    readonly property string kind: !root.day ? ""
      : root.day.needsPlan ? "plan"
      : root.day.needsShutdown ? "shutdown"
      : root.day.alert !== "none" ? root.day.alert
      : ""
    visible: kind !== ""
    width: parent.width
    height: cta.implicitHeight + Theme.s(28)
    radius: Theme.radius
    color: kind === "urgent" ? Theme.alpha(Theme.danger, 0.16)
      : kind === "warn" || kind === "shutdown" ? Theme.alpha(Theme.fire, 0.14)
      : Theme.alpha(Theme.good, 0.12)

    Row {
      id: cta
      anchors.left: parent.left
      anchors.leftMargin: Theme.s(16)
      anchors.right: parent.right
      anchors.rightMargin: Theme.s(12)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Theme.s(12)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: attention.kind === "plan" ? "\u{f0599}" : attention.kind === "shutdown" ? "\u{f0594}" : "\u{f0238}"
        color: attention.kind === "urgent" ? Theme.danger : attention.kind === "plan" ? Theme.good : Theme.fire
        font.family: Theme.iconFont
        font.pixelSize: Theme.title
      }

      Column {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - Theme.s(40) - (ctaButton.visible ? ctaButton.width + Theme.s(12) : 0)
        spacing: Theme.s(1)
        Text {
          width: parent.width
          text: {
            var k = attention.kind
            if (k === "plan") return "Plan your day"
            if (k === "shutdown") return "Time to shut down"
            var n = root.day ? root.day.habitsLeft.length : 0
            return n + (n === 1 ? " habit" : " habits") + (k === "urgent" ? " left — don't break the chain" : " still open")
          }
          color: Theme.label
          font.family: Theme.font
          font.pixelSize: Theme.body
          font.weight: Font.DemiBold
          elide: Text.ElideRight
        }
        Text {
          width: parent.width
          text: {
            var k = attention.kind
            if (k === "plan") return "Choose up to three priorities."
            if (k === "shutdown") return root.day.leftovers.length + " unfinished — give each a place."
            return root.day ? root.day.habitsLeft.join(" · ") : ""
          }
          color: Theme.secondary
          font.family: Theme.font
          font.pixelSize: Theme.footnote
          elide: Text.ElideRight
        }
      }

      PillButton {
        id: ctaButton
        anchors.verticalCenter: parent.verticalCenter
        visible: attention.kind === "plan" || attention.kind === "shutdown"
        text: attention.kind === "plan" ? "Plan" : "Close day"
        tint: attention.kind === "plan" ? Theme.good : Theme.fire
        onClicked: root.navigate("mode:" + attention.kind, false)
      }
    }
  }

  // ---- priorities, pinned
  Column {
    visible: root.priorities.length > 0
    width: parent.width
    spacing: Theme.s(6)

    SectionHeader {
      text: "Focus"
      trailing: root.s ? root.s.prioritiesDone + " of " + root.s.priorities : ""
      color: Theme.fire
    }

    Card {
      width: parent.width
      padding: Theme.s(3)
      spacing: 0
      color: Theme.alpha(Theme.fire, 0.07)

      Repeater {
        model: root.priorities
        Column {
          required property var modelData
          required property int index
          width: parent.width
          Hairline { visible: index > 0; inset: Theme.s(40) }
          TaskRow { task: modelData; host: root.host; showDue: false }
        }
      }
    }
  }

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
        text: root.day && root.day.shutdown ? "Day complete and closed. Well done." : "Day complete. Well done."
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
    onActivated: root.navigate(root.nextEvent && root.nextEvent.kind === "birthday" ? "people" : "events", false)
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
