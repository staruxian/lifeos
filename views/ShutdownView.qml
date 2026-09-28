import QtQuick
import "../components"
import "../pages"
import "../Model.js" as Model

// Evening: every unfinished task gets a decision — tomorrow, next week,
// done after all, or dropped. Nothing rolls over by itself.
ViewBase {
  id: root

  readonly property var day: snap ? snap.day : null
  readonly property var leftovers: day ? day.leftovers : []
  readonly property var habitsLeft: snap ? snap.habits.filter(function(h) { return h.scheduledToday && !h.done && !h.skipped }) : []
  readonly property var s: snap ? snap.summary : null
  readonly property var book: snap && snap.books.reading.length ? snap.books.reading[0] : null

  Lead {
    title: root.day && root.day.shutdown ? "Day closed. Rest well." : "Close the day"
    subtitle: root.day && root.day.shutdown ? "Everything has a place. See you tomorrow."
      : root.leftovers.length ? "Give every unfinished task a place. Nothing rolls over on its own."
      : "Nothing left undecided."
  }

  // The day in numbers.
  Row {
    width: parent.width
    spacing: Theme.s(8)

    Repeater {
      model: root.s ? [
        { n: root.s.habitsDone + "/" + root.s.habitsDue, label: "habits" },
        { n: String(root.s.tasksDoneToday), label: root.s.tasksDoneToday === 1 ? "task done" : "tasks done" },
        { n: root.s.priorities ? root.s.prioritiesDone + "/" + root.s.priorities : "—", label: "priorities" },
        { n: String(root.book ? root.book.today : 0), label: "pages" }
      ] : []

      Rectangle {
        required property var modelData
        width: (parent.width - parent.spacing * 3) / 4
        height: Theme.s(54)
        radius: Theme.radiusControl
        color: Theme.fill

        Column {
          anchors.centerIn: parent
          Text { textFormat: Text.PlainText; anchors.horizontalCenter: parent.horizontalCenter; text: modelData.n; color: Theme.label; font.family: Theme.font; font.pixelSize: Theme.headline; font.weight: Font.Bold; font.features: ({ "tnum": 1 }) }
          Text { textFormat: Text.PlainText; anchors.horizontalCenter: parent.horizontalCenter; text: modelData.label; color: Theme.tertiary; font.family: Theme.font; font.pixelSize: Theme.caption }
        }
      }
    }
  }

  Column {
    visible: root.leftovers.length > 0
    width: parent.width
    spacing: Theme.s(6)

    SectionHeader { text: "Needs a decision"; trailing: String(root.leftovers.length); color: Theme.fire }

    Repeater {
      model: root.leftovers

      Card {
        required property var modelData
        width: parent.width
        padding: Theme.s(12)
        spacing: Theme.s(10)

        Item {
          width: parent.width
          height: Math.max(titleText.implicitHeight, Theme.s(18))

          Text {
            textFormat: Text.PlainText
            id: titleText
            anchors.left: parent.left
            anchors.right: dueText.left
            anchors.rightMargin: Theme.s(8)
            text: (modelData.focus ? "★ " : "") + modelData.title
            color: Theme.label
            font.family: Theme.font
            font.pixelSize: Theme.body
            font.weight: Font.Medium
            elide: Text.ElideRight
          }
          Text {
            textFormat: Text.PlainText
            id: dueText
            anchors.right: parent.right
            text: Model.dueLabel(modelData)
            color: modelData.daysUntil < 0 ? Theme.danger : Theme.tertiary
            font.family: Theme.font
            font.pixelSize: Theme.footnote
          }
        }

        Flow {
          width: parent.width
          spacing: Theme.s(6)
          Chip { text: "Done"; icon: "\u{f012c}"; tint: Theme.good; onClicked: root.host.toggleTask(modelData.id) }
          Chip { text: "Tomorrow"; onClicked: root.host.setTaskDue(modelData.id, "tomorrow") }
          Chip { text: "Next week"; onClicked: root.host.setTaskDue(modelData.id, "next mon") }
          Chip { text: "Someday"; onClicked: root.host.setTaskDue(modelData.id, "none") }
          Chip { text: "Drop"; icon: "\u{f0156}"; tint: Theme.danger; onClicked: root.host.dropTask(modelData.id) }
        }
      }
    }
  }

  Column {
    visible: root.habitsLeft.length > 0
    width: parent.width
    spacing: Theme.s(6)

    SectionHeader { text: "Still time for"; trailing: String(root.habitsLeft.length) }

    Card {
      width: parent.width
      padding: Theme.s(3)
      spacing: 0

      Repeater {
        model: root.habitsLeft
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

  // ---- check-in: how it felt, in a tap and a line
  property int mood: 0
  readonly property int shownMood: mood > 0 ? mood : (day && day.mood ? day.mood : 0)
  readonly property var faces: ["😞", "😕", "😐", "🙂", "😄"]
  readonly property var words: ["Rough", "Meh", "Okay", "Good", "Great"]
  onActiveChanged: if (active) { mood = 0; noteField.text = day && day.note ? day.note : "" }

  function saveCheckIn() {
    if (root.shownMood > 0) root.host.checkIn(root.shownMood, noteField.text.trim())
  }

  Column {
    width: parent.width
    spacing: Theme.s(8)

    SectionHeader { text: "How did today feel?"; trailing: root.shownMood ? root.words[root.shownMood - 1] : "" }

    Row {
      spacing: Theme.s(8)
      anchors.horizontalCenter: parent.horizontalCenter

      Repeater {
        model: 5
        Rectangle {
          required property int index
          readonly property bool picked: root.shownMood === index + 1
          width: Theme.s(56)
          height: Theme.s(56)
          radius: Theme.radius
          color: picked ? Theme.fillStrong : faceMouse.containsMouse ? Theme.fillHover : Theme.fill
          border.width: picked ? 1 : 0
          border.color: Theme.alpha(Theme.fg, 0.2)
          scale: faceMouse.pressed ? 0.92 : picked ? 1.06 : 1
          Behavior on scale { NumberAnimation { duration: Theme.fast; easing.type: Easing.OutBack } }

          Text {
            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: root.faces[index]
            font.family: Theme.emojiFont
            font.pixelSize: Theme.s(26)
            opacity: parent.picked || root.shownMood === 0 ? 1 : 0.45
          }
          MouseArea { id: faceMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.mood = index + 1 }
        }
      }
    }

    Field {
      id: noteField
      width: parent.width
      icon: "\u{f03eb}"
      placeholder: "One line about today (optional)"
      clearOnSubmit: false
      maxLength: 280
      onSubmitted: if (root.day && root.day.shutdown) root.saveCheckIn()
    }
  }

  PillButton {
    anchors.right: parent.right
    visible: !(root.day && root.day.shutdown)
    text: "Finish the day"
    icon: "\u{f0594}"
    active: root.leftovers.length === 0
    onClicked: { root.saveCheckIn(); root.host.shutdownDay(); root.finished() }
  }

  PillButton {
    anchors.right: parent.right
    visible: root.day !== null && root.day.shutdown && root.shownMood > 0
    text: "Save check-in"
    primary: false
    onClicked: { root.saveCheckIn(); root.finished() }
  }
}
