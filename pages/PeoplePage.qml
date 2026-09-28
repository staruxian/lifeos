import QtQuick
import "../components"

PageBase {
  id: root

  readonly property var people: snap ? snap.people : []
  // Within the month gets its own heading, so the soon ones stand out.
  readonly property var soon: people.filter(function(p) { return p.daysLeft <= 30 })
  readonly property var later: people.filter(function(p) { return p.daysLeft > 30 })

  function focusAdd() { newPerson.openForm() }

  spacing: Theme.s(10)

  SectionHeader { visible: root.soon.length > 0; text: "Coming up"; trailing: "next 30 days" }
  Repeater {
    model: root.soon
    PersonCard { required property var modelData; person: modelData; host: root.host }
  }

  Item { visible: root.soon.length > 0 && root.later.length > 0; width: 1; height: Theme.s(4) }
  SectionHeader { visible: root.later.length > 0; text: root.soon.length ? "Later" : "Birthdays" }
  Repeater {
    model: root.later
    PersonCard { required property var modelData; person: modelData; host: root.host }
  }

  EmptyState {
    visible: root.snap !== null && root.people.length === 0 && !newPerson.expanded
    icon: "\u{f0849}"
    title: "The people who matter"
    hint: "Add someone and their birthday. LifeOS counts down, tells you how old they turn, and reminds you a week, a day, and on the day."
  }

  NewPerson { id: newPerson; host: root.host }
}
