import QtQuick
import "../components"
import "../pages"
import "../Model.js" as Model

// Morning: choose at most three things that matter today. The limit is the
// point — everything else can wait.
ViewBase {
  id: root

  readonly property var day: snap ? snap.day : null
  readonly property var priorities: day ? day.priorities : []
  readonly property bool full: priorities.length >= 3
  readonly property var candidates: {
    if (!snap) return []
    var t = snap.tasks
    return t.overdue.concat(t.today).concat(t.upcoming).concat(t.someday).filter(function(x) { return !x.focus && !x.done })
  }
  readonly property var habitsToday: snap ? snap.habits.filter(function(h) { return h.scheduledToday && !h.skipped }) : []

  function focusAdd() { addField.focusInput() }

  Lead {
    title: root.day && root.day.planned ? "Today's priorities" : "What matters most today?"
    subtitle: root.day && root.day.planned ? "Change them any time. Three at most." : "Pick up to three. Everything else can wait."
  }

  // Last week's score, the first Monday morning thing you see.
  WeekCard {
    visible: root.snap !== null && root.snap.review.due
    week: root.snap ? root.snap.review.lastWeek : null
    previous: null
    title: "Last week"
  }

  // Three slots, filled or waiting.
  Column {
    width: parent.width
    spacing: Theme.s(8)

    Repeater {
      model: 3

      Rectangle {
        required property int index
        readonly property var task: index < root.priorities.length ? root.priorities[index] : null
        width: parent.width
        height: Theme.s(46)
        radius: Theme.radius
        color: task ? Theme.alpha(Theme.fire, 0.1) : "transparent"
        border.width: 1
        border.color: task ? Theme.alpha(Theme.fire, 0.35) : Theme.quaternary

        Text {
          id: star
          anchors.left: parent.left
          anchors.leftMargin: Theme.s(14)
          anchors.verticalCenter: parent.verticalCenter
          text: parent.task ? "\u{f04ce}" : String(index + 1)
          color: parent.task ? Theme.fire : Theme.tertiary
          font.family: parent.task ? Theme.iconFont : Theme.font
          font.pixelSize: parent.task ? Theme.headline : Theme.body
          font.weight: Font.DemiBold
        }
        Text {
          anchors.left: star.right
          anchors.leftMargin: Theme.s(12)
          anchors.right: remove.left
          anchors.rightMargin: Theme.s(6)
          anchors.verticalCenter: parent.verticalCenter
          text: parent.task ? parent.task.title : "Pick from below or type one"
          color: parent.task ? (parent.task.done ? Theme.tertiary : Theme.label) : Theme.tertiary
          font.family: Theme.font
          font.pixelSize: Theme.body
          font.weight: parent.task ? Font.Medium : Font.Normal
          font.strikeout: parent.task ? parent.task.done : false
          elide: Text.ElideRight
        }
        IconButton {
          id: remove
          anchors.right: parent.right
          anchors.rightMargin: Theme.s(8)
          anchors.verticalCenter: parent.verticalCenter
          visible: parent.task !== null
          icon: "\u{f0156}"
          tooltip: "Not a priority"
          color: Theme.tertiary
          onClicked: root.host.focusTask(parent.task.id, false)
        }
      }
    }
  }

  Field {
    id: addField
    width: parent.width
    visible: !root.full
    icon: "\u{f04ce}"
    placeholder: "A new priority for today"
    onSubmitted: function(text) { root.host.quick(text + "!") }
  }

  Column {
    visible: root.candidates.length > 0
    width: parent.width
    spacing: Theme.s(6)

    SectionHeader { text: "Your tasks"; trailing: root.full ? "three chosen" : "tap ★ to choose" }

    Card {
      width: parent.width
      padding: Theme.s(3)
      spacing: 0

      Repeater {
        model: root.candidates.slice(0, 12)

        Column {
          required property var modelData
          required property int index
          width: parent.width
          Hairline { visible: index > 0; inset: Theme.s(12) }

          Item {
            width: parent.width
            height: Theme.rowHeight + Theme.s(2)

            Text {
              anchors.left: parent.left
              anchors.leftMargin: Theme.s(12)
              anchors.right: due.left
              anchors.rightMargin: Theme.s(8)
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.title
              color: Theme.label
              font.family: Theme.font
              font.pixelSize: Theme.body
              elide: Text.ElideRight
            }
            Text {
              id: due
              anchors.right: pick.left
              anchors.rightMargin: Theme.s(6)
              anchors.verticalCenter: parent.verticalCenter
              text: Model.dueLabel(modelData)
              color: modelData.daysUntil !== null && modelData.daysUntil < 0 ? Theme.danger : Theme.tertiary
              font.family: Theme.font
              font.pixelSize: Theme.footnote
            }
            IconButton {
              id: pick
              anchors.right: parent.right
              anchors.rightMargin: Theme.s(6)
              anchors.verticalCenter: parent.verticalCenter
              icon: "\u{f04d2}"
              tooltip: root.full ? "Three already — remove one first" : "Make it a priority"
              color: root.full ? Theme.quaternary : Theme.tertiary
              hoverColor: root.full ? Theme.quaternary : Theme.fire
              onClicked: if (!root.full) root.host.focusTask(modelData.id, true)
            }
          }
        }
      }
    }
  }

  Text {
    visible: root.habitsToday.length > 0
    width: parent.width
    leftPadding: Theme.s(4)
    text: "Also today: " + root.habitsToday.map(function(h) { return h.name }).join(" · ")
    color: Theme.tertiary
    font.family: Theme.font
    font.pixelSize: Theme.footnote
    wrapMode: Text.WordWrap
  }

  PillButton {
    anchors.right: parent.right
    text: root.day && root.day.planned ? "Done" : "Start my day"
    icon: root.day && root.day.planned ? "" : "\u{f0e1e}"
    onClicked: {
      if (!(root.day && root.day.planned)) root.host.planDay()
      root.finished()
    }
  }
}
