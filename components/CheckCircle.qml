import QtQuick
import QtQuick.Shapes

// Round checkbox. The tap flips it at once, before the CLI confirms, so the
// check draws itself under your finger; the real value takes over when the
// new state lands. `slip` paints it as a broken promise (avoid habits).
Item {
  id: root

  property bool checked: false
  property bool slip: false
  property int size: Theme.s(22)
  property color color: slip ? Theme.danger : Theme.good

  signal toggled()

  // -1 = follow `checked`, 0/1 = optimistic value until data arrives.
  property int pending: -1
  readonly property bool on: pending >= 0 ? pending === 1 : checked
  onCheckedChanged: pending = -1

  implicitWidth: size
  implicitHeight: size

  property real drawn: on ? 1 : 0
  Behavior on drawn { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }

  Rectangle {
    id: disc
    anchors.centerIn: parent
    width: root.size
    height: root.size
    radius: width / 2
    color: root.on ? root.color : (mouse.containsMouse ? Theme.fill : "transparent")
    border.width: root.on ? 0 : Math.max(1.5, root.size * 0.075)
    border.color: mouse.containsMouse ? Theme.secondary : Theme.tertiary
    scale: mouse.pressed ? 0.86 : 1
    Behavior on color { ColorAnimation { duration: Theme.fast } }
    Behavior on scale { NumberAnimation { duration: Theme.fast; easing.type: Easing.OutBack; easing.overshoot: 3 } }
  }

  // Check (or cross for a slip), drawn as a stroke so it can animate in.
  Shape {
    id: mark
    anchors.fill: parent
    visible: root.drawn > 0
    preferredRendererType: Shape.CurveRenderer
    scale: disc.scale

    readonly property real w: root.size
    readonly property real t1: Math.min(1, root.drawn / 0.4)
    readonly property real t2: Math.max(0, (root.drawn - 0.4) / 0.6)

    // A check is a short leg then a long one; a cross is two strokes.
    readonly property point a: root.slip ? Qt.point(w * 0.34, w * 0.34) : Qt.point(w * 0.29, w * 0.52)
    readonly property point b: root.slip ? Qt.point(w * 0.66, w * 0.66) : Qt.point(w * 0.44, w * 0.67)
    readonly property point c: root.slip ? Qt.point(w * 0.66, w * 0.34) : Qt.point(w * 0.44, w * 0.67)
    readonly property point d: root.slip ? Qt.point(w * 0.34, w * 0.66) : Qt.point(w * 0.72, w * 0.36)

    ShapePath {
      strokeColor: Theme.bg
      strokeWidth: Math.max(1.6, root.size * 0.1)
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      startX: mark.a.x; startY: mark.a.y
      PathLine { x: mark.a.x + (mark.b.x - mark.a.x) * mark.t1; y: mark.a.y + (mark.b.y - mark.a.y) * mark.t1 }
      PathMove { x: mark.c.x; y: mark.c.y }
      PathLine { x: mark.c.x + (mark.d.x - mark.c.x) * mark.t2; y: mark.c.y + (mark.d.y - mark.c.y) * mark.t2 }
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    anchors.margins: -Theme.s(4)
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: {
      root.pending = root.on ? 0 : 1
      root.toggled()
    }
  }
}
