import QtQuick
import "../components"

// "Add a person": a name and a birthday. Given a `person`, it edits them.
Card {
  id: root

  property var host: null
  property var person: null
  property bool expanded: person !== null
  readonly property bool valid: nameField.text.trim() !== "" && bornField.text.trim() !== ""
  signal closed()

  function load() {
    if (!person) return
    nameField.text = person.name
    bornField.text = person.day + "." + person.month + (person.year ? "." + person.year : "")
    Qt.callLater(nameField.focusInput)
  }
  onPersonChanged: load()
  Component.onCompleted: load()

  function openForm() {
    expanded = true
    Qt.callLater(nameField.focusInput)
  }

  function reset() {
    nameField.clear()
    bornField.clear()
    expanded = person !== null
    closed()
  }

  function submit() {
    if (!valid) {
      if (nameField.text.trim() !== "") bornField.focusInput()
      return
    }
    if (person) {
      host.editPerson(person.id, nameField.text.trim(), bornField.text.trim())
      closed()
      return
    }
    host.addPerson(nameField.text.trim(), bornField.text.trim())
    reset()
  }

  width: parent ? parent.width : implicitWidth
  hoverable: !expanded
  padding: expanded ? Theme.pad : Theme.s(4)
  spacing: Theme.s(10)

  Item {
    visible: !root.expanded
    width: parent.width
    height: Theme.rowHeight

    Row {
      anchors.left: parent.left
      anchors.leftMargin: Theme.s(10)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Theme.s(10)
      Text { textFormat: Text.PlainText; anchors.verticalCenter: parent.verticalCenter; text: "\u{f0415}"; color: Theme.good; font.family: Theme.iconFont; font.pixelSize: Theme.headline }
      Text { textFormat: Text.PlainText; anchors.verticalCenter: parent.verticalCenter; text: "Add a person"; color: Theme.good; font.family: Theme.font; font.pixelSize: Theme.body; font.weight: Font.DemiBold }
    }

    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.openForm() }
  }

  Field {
    id: nameField
    visible: root.expanded
    width: parent.width
    icon: "\u{f0004}"
    placeholder: "Name"
    clearOnSubmit: false
    onSubmitted: root.submit()
    onEscaped: root.reset()
  }

  Field {
    id: bornField
    visible: root.expanded
    width: parent.width
    icon: "\u{f00eb}"
    placeholder: "Birthday — 12.10.2001, oct 12 (year optional)"
    clearOnSubmit: false
    onSubmitted: root.submit()
    onEscaped: root.reset()
  }

  Row {
    visible: root.expanded
    anchors.right: parent.right
    spacing: Theme.s(8)
    PillButton { text: "Cancel"; primary: false; onClicked: root.reset() }
    PillButton { text: root.person ? "Save" : "Add"; active: root.valid; onClicked: root.submit() }
  }
}
