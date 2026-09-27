import QtQuick
import "../components"

// A time like 21:00; saved on Enter or when the field loses focus.
Field {
  id: root

  property string key: ""
  property string value: ""
  property var host: null

  width: Theme.s(76)
  clearOnSubmit: false
  placeholder: "HH:MM"
  text: value
  onValueChanged: if (!input.activeFocus) text = value
  onSubmitted: function(t) { save(t) }
  Connections {
    target: root.input
    function onActiveFocusChanged() { if (!root.input.activeFocus && root.text.trim() !== root.value) root.save(root.text) }
  }

  function save(t) {
    if (t.trim() === "" ) { text = value; return }
    if (host) host.setSetting(key, t.trim())
  }
}
