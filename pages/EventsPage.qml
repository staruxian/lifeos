import QtQuick
import "../components"

PageBase {
  id: root

  readonly property var events: snap ? snap.events : []

  function focusAdd() { newEvent.openForm() }

  spacing: Theme.s(10)

  Repeater {
    model: root.events
    EventCard {
      required property var modelData
      event: modelData
      host: root.host
    }
  }

  EmptyState {
    visible: root.snap !== null && root.events.length === 0 && !newEvent.expanded
    icon: "\u{f00f0}"
    title: "Something to look forward to"
    hint: "A trip, a birthday, a launch. LifeOS counts the days, and it disappears once the day has passed."
  }

  NewEvent { id: newEvent; host: root.host }
}
