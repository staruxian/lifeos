import QtQuick

// Capsule progress track. The fill springs to its new width.
Rectangle {
  id: root

  property real value: 0
  property color fillColor: Theme.good
  property int barHeight: Theme.s(6)

  implicitWidth: Theme.s(200)
  implicitHeight: barHeight
  radius: height / 2
  color: Theme.fillStrong

  Rectangle {
    height: parent.height
    radius: parent.radius
    color: root.fillColor
    width: root.value <= 0 ? 0 : Math.max(parent.height, parent.width * Math.min(1, root.value))
    Behavior on width { NumberAnimation { duration: Theme.slow; easing.type: Easing.OutCubic } }
  }
}
