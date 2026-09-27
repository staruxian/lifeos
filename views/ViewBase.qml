import QtQuick
import "../components"

// Shared shell for the full-panel rituals and settings.
Column {
  id: root

  property var host: null
  property var snap: null
  property bool active: false

  signal finished()

  function focusAdd() {}

  spacing: Theme.s(16)
  enabled: active
  visible: opacity > 0
  opacity: active ? 1 : 0
  Behavior on opacity { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }

  transform: Translate {
    y: root.active ? 0 : Theme.s(8)
    Behavior on y { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }
  }
}
