import QtQuick
import "../components"

// Label and explanation on the left, the control on the right.
Item {
  id: root

  default property alias control: slot.data
  property string title: ""
  property string detail: ""

  width: parent ? parent.width : implicitWidth
  implicitHeight: Math.max(texts.implicitHeight, slot.childrenRect.height) + Theme.s(18)

  Column {
    id: texts
    anchors.left: parent.left
    anchors.leftMargin: Theme.s(12)
    anchors.right: slot.left
    anchors.rightMargin: Theme.s(12)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Theme.s(2)

    Text { width: parent.width; text: root.title; color: Theme.label; font.family: Theme.font; font.pixelSize: Theme.body; font.weight: Font.Medium }
    Text { width: parent.width; visible: text !== ""; text: root.detail; color: Theme.tertiary; font.family: Theme.font; font.pixelSize: Theme.footnote; wrapMode: Text.WordWrap }
  }

  Item {
    id: slot
    anchors.right: parent.right
    anchors.rightMargin: Theme.s(12)
    anchors.verticalCenter: parent.verticalCenter
    width: childrenRect.width
    height: childrenRect.height
  }
}
