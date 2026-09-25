import QtQuick

// Primary (filled) or plain text button.
Rectangle {
  id: root

  property string text: ""
  property string icon: ""
  property bool primary: true
  property bool active: true
  property color tint: Theme.good

  signal clicked()

  implicitHeight: Theme.controlHeight
  implicitWidth: row.implicitWidth + Theme.s(28)
  radius: height / 2
  opacity: active ? 1 : 0.45
  color: primary
    ? (mouse.containsMouse && active ? Qt.lighter(tint, 1.08) : tint)
    : (mouse.containsMouse && active ? Theme.fillHover : Theme.fill)
  scale: mouse.pressed && active ? 0.96 : 1
  Behavior on color { ColorAnimation { duration: Theme.fast } }
  Behavior on scale { NumberAnimation { duration: Theme.fast; easing.type: Easing.OutCubic } }
  Behavior on opacity { NumberAnimation { duration: Theme.fast } }

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Theme.s(6)

    Text {
      visible: root.icon !== ""
      anchors.verticalCenter: parent.verticalCenter
      text: root.icon
      color: root.primary ? Theme.bg : Theme.label
      font.family: Theme.iconFont
      font.pixelSize: Theme.body
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: root.text
      color: root.primary ? Theme.bg : Theme.label
      font.family: Theme.font
      font.pixelSize: Theme.body
      font.weight: Font.DemiBold
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: root.active ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: if (root.active) root.clicked()
  }
}
