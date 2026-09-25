import QtQuick
import "../components"

// "Add a book": a title and how many pages it has.
Card {
  id: root

  property var host: null
  property bool expanded: false
  readonly property bool valid: titleField.text.trim() !== "" && Number(pagesField.text) > 0

  function openForm() {
    expanded = true
    Qt.callLater(titleField.focusInput)
  }

  function reset() {
    titleField.clear()
    pagesField.clear()
    expanded = false
  }

  function submit() {
    if (!valid) {
      if (titleField.text.trim() !== "") pagesField.focusInput()
      return
    }
    host.addBook(titleField.text.trim(), Number(pagesField.text))
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
      Text { anchors.verticalCenter: parent.verticalCenter; text: "\u{f0415}"; color: Theme.good; font.family: Theme.iconFont; font.pixelSize: Theme.headline }
      Text { anchors.verticalCenter: parent.verticalCenter; text: "Add a book"; color: Theme.good; font.family: Theme.font; font.pixelSize: Theme.body; font.weight: Font.DemiBold }
    }

    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.openForm() }
  }

  Row {
    visible: root.expanded
    width: parent.width
    spacing: Theme.s(8)

    Field {
      id: titleField
      width: parent.width - pagesField.width - parent.spacing
      icon: "\u{f00ba}"
      placeholder: "Title"
      clearOnSubmit: false
      onSubmitted: root.submit()
      onEscaped: root.reset()
    }
    Field {
      id: pagesField
      width: Theme.s(96)
      numeric: true
      placeholder: "Pages"
      clearOnSubmit: false
      onSubmitted: root.submit()
      onEscaped: root.reset()
    }
  }

  Row {
    visible: root.expanded
    anchors.right: parent.right
    spacing: Theme.s(8)
    PillButton { text: "Cancel"; primary: false; onClicked: root.reset() }
    PillButton { text: "Start reading"; active: root.valid; onClicked: root.submit() }
  }
}
