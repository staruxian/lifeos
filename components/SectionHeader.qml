import QtQuick

// Small uppercase label above a group, with an optional trailing note.
Item {
  id: root

  property string text: ""
  property string trailing: ""
  property color color: Theme.tertiary

  width: parent ? parent.width : implicitWidth
  implicitHeight: label.implicitHeight + Theme.s(2)

  Text {
    id: label
    anchors.left: parent.left
    anchors.leftMargin: Theme.s(4)
    anchors.bottom: parent.bottom
    text: root.text.toUpperCase()
    color: root.color
    font.family: Theme.font
    font.pixelSize: Theme.caption
    font.weight: Font.DemiBold
    font.letterSpacing: 0.9
  }

  Text {
    anchors.right: parent.right
    anchors.rightMargin: Theme.s(4)
    anchors.baseline: label.baseline
    text: root.trailing
    color: Theme.tertiary
    font.family: Theme.font
    font.pixelSize: Theme.footnote
    font.features: ({ "tnum": 1 })
  }
}
