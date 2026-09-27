import QtQuick
import "../components"

// A ritual's opening line and a quieter sentence under it.
Column {
  property string title: ""
  property string subtitle: ""
  width: parent ? parent.width : implicitWidth
  spacing: Theme.s(4)

  Text {
    width: parent.width
    text: parent.title
    color: Theme.label
    font.family: Theme.font
    font.pixelSize: Theme.title
    font.weight: Font.Bold
    wrapMode: Text.WordWrap
  }
  Text {
    width: parent.width
    visible: text !== ""
    text: parent.subtitle
    color: Theme.secondary
    font.family: Theme.font
    font.pixelSize: Theme.body
    wrapMode: Text.WordWrap
    lineHeight: 1.12
  }
}
