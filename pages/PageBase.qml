import QtQuick
import "../components"

// Shared page shell: fades and settles into place when its tab is picked.
Column {
  id: root

  property var host: null
  property var snap: null
  property bool active: false

  // Ask the panel for another tab, optionally with its add field focused.
  signal navigate(string key, bool focusAdd)

  function focusAdd() {}

  spacing: Theme.s(18)
  enabled: active
  visible: opacity > 0
  opacity: active ? 1 : 0
  Behavior on opacity { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }

  transform: Translate {
    y: root.active ? 0 : Theme.s(6)
    Behavior on y { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }
  }
}
