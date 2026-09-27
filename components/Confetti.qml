import QtQuick
import QtQuick.Particles

// A short burst of colour when the day is complete. Costs nothing between
// bursts: the system only runs while pieces are in the air.
Item {
  id: root

  readonly property var colors: [Theme.good, Theme.fire, Theme.fireCore, "#0a84ff", "#bf5af2", "#ff375f"]

  function burst() {
    system.running = true
    left.burst(55)
    right.burst(55)
    stop.restart()
  }

  Timer { id: stop; interval: 3200; onTriggered: system.running = false }

  ParticleSystem { id: system; running: false }

  Emitter {
    id: left
    system: system
    x: root.width * 0.2
    y: root.height * 0.35
    enabled: false
    lifeSpan: 2600
    lifeSpanVariation: 500
    velocity: AngleDirection { angle: -70; angleVariation: 30; magnitude: root.height * 0.9; magnitudeVariation: root.height * 0.3 }
  }

  Emitter {
    id: right
    system: system
    x: root.width * 0.8
    y: root.height * 0.35
    enabled: false
    lifeSpan: 2600
    lifeSpanVariation: 500
    velocity: AngleDirection { angle: -110; angleVariation: 30; magnitude: root.height * 0.9; magnitudeVariation: root.height * 0.3 }
  }

  Gravity { system: system; magnitude: root.height * 1.3; angle: 90 }

  ItemParticle {
    system: system
    fade: true
    delegate: Rectangle {
      width: Theme.s(4) + Math.random() * Theme.s(4)
      height: width * (Math.random() > 0.5 ? 0.5 : 1.4)
      radius: Math.random() > 0.6 ? width / 2 : 1
      color: root.colors[Math.floor(Math.random() * root.colors.length)]
      rotation: Math.random() * 360
      RotationAnimation on rotation {
        loops: Animation.Infinite
        from: 0; to: Math.random() > 0.5 ? 360 : -360
        duration: 500 + Math.random() * 900
      }
    }
  }
}
