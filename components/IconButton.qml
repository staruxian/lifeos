import QtQuick
import qs.Ui

// Round glyph button with a hover wash and an optional tooltip.
Item {
  id: root

  property string icon: ""
  property string tooltip: ""
  property color color: Theme.secondary
  property color hoverColor: Theme.label
  property int size: Theme.s(26)
  property real iconSize: Theme.body

  signal clicked()

  implicitWidth: size
  implicitHeight: size

  Rectangle {
    anchors.fill: parent
    radius: width / 2
    color: mouse.containsMouse ? Theme.fillHover : "transparent"
    scale: mouse.pressed ? 0.9 : 1
    Behavior on color { ColorAnimation { duration: Theme.fast } }
    Behavior on scale { NumberAnimation { duration: Theme.fast; easing.type: Easing.OutCubic } }

    Text {
      anchors.centerIn: parent
      text: root.icon
      color: mouse.containsMouse ? root.hoverColor : root.color
      font.family: Theme.iconFont
      font.pixelSize: root.iconSize
      Behavior on color { ColorAnimation { duration: Theme.fast } }
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }

  PanelToolTip {
    visible: root.tooltip !== "" && mouse.containsMouse
    text: root.tooltip
    fontFamily: Theme.font
  }
}
