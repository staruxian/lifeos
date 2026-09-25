import QtQuick
import "../components"

// Two-step delete: the first click arms it, the second one removes.
// It disarms itself after a few seconds.
IconButton {
  id: root

  property bool armed: false
  signal confirmed()

  icon: armed ? "\u{f01b4}" : "\u{f0a7a}"
  tooltip: armed ? "Click again to delete" : "Delete"
  color: armed ? Theme.danger : Theme.tertiary
  hoverColor: Theme.danger
  onClicked: {
    if (armed) { armed = false; confirmed() }
    else { armed = true; disarm.restart() }
  }

  Timer { id: disarm; interval: 3000; onTriggered: root.armed = false }
}
