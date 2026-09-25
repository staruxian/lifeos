import QtQuick
import "../components"
import "../Model.js" as Model

// A countdown: the emoji, what and when, and the days left set large.
// The hairline along the bottom fills as the day comes closer.
Card {
  id: root

  property var event: null
  property var host: null
  property bool removable: true

  signal activated()

  readonly property bool isToday: event && event.daysLeft === 0

  width: parent ? parent.width : implicitWidth
  hoverable: true
  spacing: Theme.s(12)
  color: isToday ? Theme.alpha(Theme.fire, hovered ? 0.2 : 0.14) : (hovered ? Theme.fillHover : Theme.fill)

  Item {
    width: parent.width
    height: Math.max(badge.height, count.implicitHeight)

    Rectangle {
      id: badge
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: Theme.s(44)
      height: width
      radius: Theme.s(12)
      color: Theme.fillStrong

      Text {
        anchors.centerIn: parent
        text: root.event && root.event.emoji ? root.event.emoji : "\u{f00f0}"
        color: Theme.secondary
        font.family: root.event && root.event.emoji ? Theme.emojiFont : Theme.iconFont
        font.pixelSize: Theme.s(22)
      }
    }

    Column {
      anchors.left: badge.right
      anchors.leftMargin: Theme.s(12)
      anchors.right: tools.left
      anchors.rightMargin: Theme.s(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Theme.s(2)

      Text {
        width: parent.width
        text: root.event ? root.event.title : ""
        color: Theme.label
        font.family: Theme.font
        font.pixelSize: Theme.headline
        font.weight: Font.DemiBold
        elide: Text.ElideRight
      }
      Text {
        width: parent.width
        text: root.event ? Model.shortDate(root.event.day, true) : ""
        color: Theme.secondary
        font.family: Theme.font
        font.pixelSize: Theme.footnote
      }
    }

    DeleteButton {
      id: tools
      anchors.right: count.left
      anchors.rightMargin: Theme.s(6)
      anchors.verticalCenter: parent.verticalCenter
      visible: root.removable && (root.hovered || armed)
      width: visible ? implicitWidth : 0
      onConfirmed: root.host.removeEvent(root.event.id)
    }

    Column {
      id: count
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter

      Text {
        anchors.right: parent.right
        text: !root.event ? "" : root.isToday ? "Today" : String(root.event.daysLeft)
        color: root.isToday ? Theme.fire : Theme.label
        font.family: Theme.font
        font.pixelSize: root.isToday ? Theme.title : Theme.s(28)
        font.weight: Font.Bold
        font.letterSpacing: -0.6
        font.features: ({ "tnum": 1 })
      }
      Text {
        anchors.right: parent.right
        visible: root.event && !root.isToday
        text: root.event && root.event.daysLeft === 1 ? "DAY" : "DAYS"
        color: Theme.tertiary
        font.family: Theme.font
        font.pixelSize: Theme.caption
        font.weight: Font.DemiBold
        font.letterSpacing: 1
      }
    }
  }

  ProgressBar {
    width: parent.width
    barHeight: Theme.s(3)
    value: root.event ? root.event.progress : 0
    fillColor: root.isToday ? Theme.fire : Theme.alpha(Theme.fg, 0.35)
    color: Theme.fill
  }

  TapHandler { onTapped: root.activated() }
}
