import QtQuick
import "../components"
import "../Model.js" as Model

// A person: their initials in a coloured circle, the age they turn and when,
// and the days until then — or a celebration when it is today.
Card {
  id: root

  property var person: null
  property var host: null
  property bool editing: false
  property var editTarget: null

  readonly property bool isToday: person && person.daysLeft === 0
  readonly property color tint: person ? Model.avatarColor(person.name) : Theme.accent

  width: parent ? parent.width : implicitWidth
  hoverable: true
  padding: Theme.s(12)
  spacing: Theme.s(10)
  color: isToday ? Theme.alpha(Theme.fire, hovered ? 0.2 : 0.14) : (hovered ? Theme.fillHover : Theme.fill)

  Item {
    width: parent.width
    height: Theme.s(44)

    Rectangle {
      id: avatar
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: Theme.s(40)
      height: width
      radius: width / 2
      color: Theme.alpha(root.tint, 0.22)
      border.width: 1
      border.color: Theme.alpha(root.tint, 0.5)

      Text {
        anchors.centerIn: parent
        text: root.person ? Model.initials(root.person.name) : ""
        color: root.tint
        font.family: Theme.font
        font.pixelSize: Theme.body
        font.weight: Font.Bold
      }
    }

    Column {
      anchors.left: avatar.right
      anchors.leftMargin: Theme.s(12)
      anchors.right: tools.left
      anchors.rightMargin: Theme.s(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Theme.s(2)

      Text {
        width: parent.width
        text: root.person ? root.person.name : ""
        color: Theme.label
        font.family: Theme.font
        font.pixelSize: Theme.headline
        font.weight: Font.DemiBold
        elide: Text.ElideRight
      }
      Text {
        width: parent.width
        text: root.person ? Model.birthdayLine(root.person) : ""
        color: Theme.secondary
        font.family: Theme.font
        font.pixelSize: Theme.footnote
        elide: Text.ElideRight
      }
    }

    Row {
      id: tools
      anchors.right: count.left
      anchors.rightMargin: Theme.s(4)
      anchors.verticalCenter: parent.verticalCenter
      opacity: (root.hovered || remove.armed) && !root.editing ? 1 : 0
      visible: opacity > 0
      Behavior on opacity { NumberAnimation { duration: Theme.fast } }

      IconButton {
        icon: "\u{f03eb}"
        tooltip: "Edit"
        color: Theme.tertiary
        onClicked: { root.editTarget = root.person; root.editing = true }
      }
      DeleteButton {
        id: remove
        onConfirmed: root.host.removePerson(root.person.id)
      }
    }

    Column {
      id: count
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter

      Text {
        anchors.right: parent.right
        text: !root.person ? "" : root.isToday ? "🎂" : String(root.person.daysLeft)
        color: Theme.label
        font.family: root.isToday ? Theme.emojiFont : Theme.font
        font.pixelSize: root.isToday ? Theme.s(24) : Theme.s(24)
        font.weight: Font.Bold
        font.features: ({ "tnum": 1 })
      }
      Text {
        anchors.right: parent.right
        text: !root.person ? "" : root.isToday ? "TODAY" : root.person.daysLeft === 1 ? "DAY" : "DAYS"
        color: root.isToday ? Theme.fire : Theme.tertiary
        font.family: Theme.font
        font.pixelSize: Theme.caption
        font.weight: Font.DemiBold
        font.letterSpacing: 1
      }
    }
  }

  NewPerson {
    visible: root.editing
    width: parent.width
    host: root.host
    person: root.editing ? root.editTarget : null
    color: "transparent"
    padding: 0
    onClosed: root.editing = false
  }
}
