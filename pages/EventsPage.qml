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
      // Birthdays belong to a person; they are edited over there.
      removable: modelData.kind === "event"
      onActivated: if (modelData.kind === "birthday") root.navigate("people", false)
    }
  }

  EmptyState {
    visible: root.snap !== null && root.events.length === 0 && !newEvent.expanded
    icon: "\u{f00f0}"
    title: "Something to look forward to"
    hint: "A trip, an exam, a launch. LifeOS counts the days, and it disappears once the day has passed. Birthdays come from People."
  }

  NewEvent { id: newEvent; host: root.host }
}
