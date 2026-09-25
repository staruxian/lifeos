import QtQuick

// Friendly placeholder: a large glyph, a line, and a hint.
Item {
  id: root

  property string icon: ""
  property string title: ""
  property string hint: ""

  width: parent ? parent.width : implicitWidth
  implicitHeight: column.implicitHeight + Theme.s(36)

  Column {
    id: column
    anchors.centerIn: parent
    width: parent.width - Theme.s(40)
    spacing: Theme.s(6)

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: root.icon
      color: Theme.quaternary
      font.family: Theme.iconFont
      font.pixelSize: Theme.s(34)
      bottomPadding: Theme.s(4)
    }

    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      text: root.title
      color: Theme.secondary
      font.family: Theme.font
      font.pixelSize: Theme.headline
      font.weight: Font.DemiBold
      wrapMode: Text.WordWrap
    }

    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      visible: root.hint !== ""
      text: root.hint
      color: Theme.tertiary
      font.family: Theme.font
      font.pixelSize: Theme.callout
      wrapMode: Text.WordWrap
      lineHeight: 1.15
    }
  }
}
