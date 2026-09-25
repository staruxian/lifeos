import QtQuick
import QtQuick.Shapes

// Activity-style ring. Anything declared inside sits in the middle.
Item {
  id: root

  default property alias content: center.data
  property real value: 0
  property real lineWidth: Math.max(2, size * 0.12)
  property int size: Theme.s(28)
  property color color: Theme.good
  property color trackColor: Theme.fillStrong

  property real shown: Math.max(0, Math.min(1, value))
  Behavior on shown { NumberAnimation { duration: Theme.slow; easing.type: Easing.OutCubic } }

  implicitWidth: size
  implicitHeight: size

  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      strokeColor: root.trackColor
      strokeWidth: root.lineWidth
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      PathAngleArc {
        centerX: root.size / 2; centerY: root.size / 2
        radiusX: (root.size - root.lineWidth) / 2; radiusY: radiusX
        startAngle: 0; sweepAngle: 360
      }
    }

    ShapePath {
      strokeColor: root.shown > 0 ? root.color : "transparent"
      strokeWidth: root.lineWidth
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      PathAngleArc {
        centerX: root.size / 2; centerY: root.size / 2
        radiusX: (root.size - root.lineWidth) / 2; radiusY: radiusX
        startAngle: -90; sweepAngle: 360 * Math.max(0.001, root.shown)
      }
    }
  }

  Item { id: center; anchors.fill: parent }
}
