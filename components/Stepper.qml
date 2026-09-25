import QtQuick

// − value + for count habits. The number rolls as it changes.
Rectangle {
  id: root

  property int value: 0
  property int target: 1
  property bool done: value >= target

  signal step(int delta)

  // Optimistic count while the CLI catches up.
  property int shown: value
  onValueChanged: shown = value

  implicitHeight: Theme.s(28)
  implicitWidth: minus.width + label.width + plus.width
  radius: height / 2
  color: done ? Theme.alpha(Theme.good, 0.18) : Theme.fill
  Behavior on color { ColorAnimation { duration: Theme.normal } }

  IconButton {
    id: minus
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    size: root.height
    icon: "\u{f0374}"
    iconSize: Theme.callout
    opacity: root.shown > 0 ? 1 : 0.35
    onClicked: if (root.shown > 0) { root.shown--; root.step(-1) }
  }

  Text {
    id: label
    anchors.left: minus.right
    anchors.verticalCenter: parent.verticalCenter
    width: Math.max(Theme.s(34), implicitWidth)
    horizontalAlignment: Text.AlignHCenter
    text: root.shown + "/" + root.target
    color: root.done ? Theme.good : Theme.label
    font.family: Theme.font
    font.pixelSize: Theme.callout
    font.weight: Font.DemiBold
    font.features: ({ "tnum": 1 })
  }

  IconButton {
    id: plus
    anchors.left: label.right
    anchors.verticalCenter: parent.verticalCenter
    size: root.height
    icon: "\u{f0415}"
    iconSize: Theme.callout
    color: root.done ? Theme.good : Theme.secondary
    onClicked: { root.shown++; root.step(1) }
  }
}
