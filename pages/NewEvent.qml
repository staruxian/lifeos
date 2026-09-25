import QtQuick
import "../components"
import "../Model.js" as Model

// "Add a countdown": what, when, and a face for it.
Card {
  id: root

  property var host: null
  property bool expanded: false
  property string emoji: ""
  readonly property string shownEmoji: emoji !== "" ? emoji : Model.guessEmoji(titleField.text)
  readonly property bool valid: titleField.text.trim() !== "" && dateField.text.trim() !== ""

  function openForm() {
    expanded = true
    Qt.callLater(titleField.focusInput)
  }

  function reset() {
    titleField.clear()
    dateField.clear()
    emoji = ""
    expanded = false
  }

  function submit() {
    if (!valid) {
      if (titleField.text.trim() !== "") dateField.focusInput()
      return
    }
    host.addEvent(titleField.text.trim(), dateField.text.trim(), shownEmoji)
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
      Text { anchors.verticalCenter: parent.verticalCenter; text: "Add a countdown"; color: Theme.good; font.family: Theme.font; font.pixelSize: Theme.body; font.weight: Font.DemiBold }
    }

    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.openForm() }
  }

  Field {
    id: titleField
    visible: root.expanded
    width: parent.width
    placeholder: "Something to look forward to"
    clearOnSubmit: false
    onSubmitted: root.submit()
    onEscaped: root.reset()
  }

  Field {
    id: dateField
    visible: root.expanded
    width: parent.width
    icon: "\u{f00ed}"
    placeholder: "When — nov 3, 12.10, next fri, in 3 weeks"
    clearOnSubmit: false
    onSubmitted: root.submit()
    onEscaped: root.reset()
  }

  Flow {
    visible: root.expanded
    width: parent.width
    spacing: Theme.s(6)

    Repeater {
      model: Model.EMOJI_CHOICES
      Rectangle {
        required property string modelData
        readonly property bool picked: root.shownEmoji === modelData
        width: Theme.s(32)
        height: width
        radius: width / 2
        color: picked ? Theme.fillStrong : (emojiMouse.containsMouse ? Theme.fillHover : "transparent")
        border.width: picked ? 1 : 0
        border.color: Theme.separator
        scale: emojiMouse.pressed ? 0.9 : 1
        Behavior on scale { NumberAnimation { duration: Theme.fast } }

        Text {
          anchors.centerIn: parent
          text: modelData
          font.family: Theme.emojiFont
          font.pixelSize: Theme.s(17)
        }
        MouseArea {
          id: emojiMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.emoji = parent.picked && root.emoji !== "" ? "" : modelData
        }
      }
    }
  }

  Row {
    visible: root.expanded
    anchors.right: parent.right
    spacing: Theme.s(8)
    PillButton { text: "Cancel"; primary: false; onClicked: root.reset() }
    PillButton { text: "Start countdown"; active: root.valid; onClicked: root.submit() }
  }
}
