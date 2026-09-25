import QtQuick

// Grouped surface, like an inset list on iOS: a soft fill, no hard border.
Rectangle {
  id: root

  default property alias content: inner.data
  property int padding: Theme.pad
  property int spacing: Theme.s(10)
  property bool hoverable: false
  readonly property bool hovered: hover.hovered

  implicitHeight: inner.implicitHeight + padding * 2
  radius: Theme.radius
  color: hoverable && hover.hovered ? Theme.fillHover : Theme.fill
  Behavior on color { ColorAnimation { duration: Theme.fast } }

  HoverHandler { id: hover }

  Column {
    id: inner
    x: root.padding
    y: root.padding
    width: root.width - root.padding * 2
    spacing: root.spacing
  }
}
