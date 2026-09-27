import QtQuick

// iOS-style switch: the knob slides, the track fills with colour.
Rectangle {
  id: root

  property bool checked: false
  property color tint: Theme.good
  signal toggled(bool checked)

  implicitWidth: Theme.s(40)
  implicitHeight: Theme.s(24)
  radius: height / 2
  color: checked ? tint : Theme.fillStrong
  Behavior on color { ColorAnimation { duration: Theme.normal } }

  Rectangle {
    width: parent.height - Theme.s(4)
    height: width
    radius: width / 2
    y: Theme.s(2)
    x: root.checked ? parent.width - width - Theme.s(2) : Theme.s(2)
    color: "white"
    Behavior on x { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutBack; easing.overshoot: 0.8 } }
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    // The owner saves the new value; `checked` follows the saved state.
    onClicked: root.toggled(!root.checked)
  }
}
