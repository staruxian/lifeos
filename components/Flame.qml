import QtQuick
import QtQuick.Particles
import QtQuick.Shapes
import qs.Ui

// A small living flame for habits on a streak: two glyph layers flicker
// out of step, a soft glow breathes behind them, and embers drift up.
// Animations only run while the flame is actually on screen.
Item {
  id: root

  property int size: Theme.s(18)
  property int streak: 0
  property bool running: visible

  implicitWidth: size
  implicitHeight: size

  readonly property string glyph: "\u{f0238}"

  // Soft radial glow: warm at the heart of the flame, gone at the edge.
  Shape {
    id: glow
    anchors.centerIn: parent
    anchors.verticalCenterOffset: root.size * 0.14
    width: root.size * 1.7
    height: width
    preferredRendererType: Shape.CurveRenderer
    opacity: 0.55

    ShapePath {
      strokeColor: "transparent"
      fillGradient: RadialGradient {
        centerX: glow.width / 2; centerY: glow.height / 2
        centerRadius: glow.width / 2
        focalX: centerX; focalY: centerY
        GradientStop { position: 0.0; color: Theme.alpha(Theme.fire, 0.55) }
        GradientStop { position: 0.45; color: Theme.alpha(Theme.fire, 0.16) }
        GradientStop { position: 1.0; color: Theme.alpha(Theme.fire, 0) }
      }
      PathAngleArc {
        centerX: glow.width / 2; centerY: glow.height / 2
        radiusX: glow.width / 2; radiusY: radiusX
        startAngle: 0; sweepAngle: 360
      }
    }

    SequentialAnimation on opacity {
      running: root.running
      loops: Animation.Infinite
      NumberAnimation { to: 0.8; duration: 900; easing.type: Easing.InOutSine }
      NumberAnimation { to: 0.45; duration: 1100; easing.type: Easing.InOutSine }
    }
  }

  ParticleSystem {
    id: sparks
    anchors.fill: parent
    running: root.running
  }

  Emitter {
    system: sparks
    x: root.size * 0.3
    y: root.size * 0.35
    width: root.size * 0.4
    height: 1
    emitRate: 5
    lifeSpan: 700
    lifeSpanVariation: 250
    velocity: PointDirection { y: -root.size * 1.4; yVariation: root.size * 0.5; xVariation: root.size * 0.35 }
  }

  ItemParticle {
    system: sparks
    fade: true
    delegate: Rectangle {
      width: Math.max(1.5, root.size * 0.1)
      height: width
      radius: width / 2
      color: Math.random() > 0.5 ? Theme.fire : Theme.fireCore
    }
  }

  // Outer flame.
  Text {
    id: outer
    anchors.centerIn: parent
    text: root.glyph
    color: Theme.fire
    font.family: Theme.iconFont
    font.pixelSize: root.size
    transformOrigin: Item.Bottom

    SequentialAnimation on scale {
      running: root.running
      loops: Animation.Infinite
      NumberAnimation { to: 1.08; duration: 420; easing.type: Easing.InOutSine }
      NumberAnimation { to: 0.95; duration: 380; easing.type: Easing.InOutSine }
      NumberAnimation { to: 1.03; duration: 300; easing.type: Easing.InOutSine }
      NumberAnimation { to: 1.0; duration: 360; easing.type: Easing.InOutSine }
    }
    SequentialAnimation on rotation {
      running: root.running
      loops: Animation.Infinite
      NumberAnimation { to: -4; duration: 520; easing.type: Easing.InOutSine }
      NumberAnimation { to: 3; duration: 640; easing.type: Easing.InOutSine }
      NumberAnimation { to: 0; duration: 480; easing.type: Easing.InOutSine }
    }
  }

  // Hot core, a beat behind the outer layer.
  Text {
    anchors.horizontalCenter: outer.horizontalCenter
    anchors.bottom: outer.bottom
    anchors.bottomMargin: root.size * 0.1
    text: root.glyph
    color: Theme.fireCore
    font.family: Theme.iconFont
    font.pixelSize: root.size * 0.52
    transformOrigin: Item.Bottom
    opacity: 0.95

    SequentialAnimation on scale {
      running: root.running
      loops: Animation.Infinite
      NumberAnimation { to: 0.9; duration: 340; easing.type: Easing.InOutSine }
      NumberAnimation { to: 1.12; duration: 460; easing.type: Easing.InOutSine }
      NumberAnimation { to: 1.0; duration: 400; easing.type: Easing.InOutSine }
    }
  }

  HoverHandler { id: hover }

  PanelToolTip {
    visible: hover.hovered && root.streak > 0
    text: root.streak + " days in a row"
    fontFamily: Theme.font
  }
}
