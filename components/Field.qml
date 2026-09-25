import QtQuick

// Text input with a leading glyph and a quiet focus ring. Enter emits
// `submitted`, Escape hands the keyboard back to the panel.
Rectangle {
  id: root

  property alias text: input.text
  property alias input: input
  property string placeholder: ""
  property string icon: ""
  property bool numeric: false
  property bool clearOnSubmit: true
  property int maxLength: 200

  signal submitted(string text)
  signal escaped()

  function focusInput() { input.forceActiveFocus() }
  function clear() { input.text = "" }

  implicitWidth: Theme.s(200)
  implicitHeight: Theme.controlHeight + Theme.s(4)
  radius: Theme.radiusControl
  color: input.activeFocus ? Theme.fillStrong : (hover.hovered ? Theme.fillHover : Theme.fill)
  border.width: 1
  border.color: input.activeFocus ? Theme.alpha(Theme.accent, 0.55) : "transparent"
  Behavior on color { ColorAnimation { duration: Theme.fast } }
  Behavior on border.color { ColorAnimation { duration: Theme.fast } }

  HoverHandler { id: hover; cursorShape: Qt.IBeamCursor }

  Text {
    id: glyph
    visible: root.icon !== ""
    anchors.left: parent.left
    anchors.leftMargin: Theme.s(10)
    anchors.verticalCenter: parent.verticalCenter
    text: root.icon
    color: input.activeFocus ? Theme.secondary : Theme.tertiary
    font.family: Theme.iconFont
    font.pixelSize: Theme.body
  }

  TextInput {
    id: input
    anchors.left: glyph.visible ? glyph.right : parent.left
    anchors.leftMargin: glyph.visible ? Theme.s(8) : Theme.s(11)
    anchors.right: parent.right
    anchors.rightMargin: Theme.s(11)
    anchors.verticalCenter: parent.verticalCenter
    color: Theme.label
    selectionColor: Theme.alpha(Theme.accent, 0.35)
    selectedTextColor: Theme.label
    font.family: Theme.font
    font.pixelSize: Theme.body
    font.features: root.numeric ? ({ "tnum": 1 }) : ({})
    clip: true
    selectByMouse: true
    maximumLength: root.maxLength
    inputMethodHints: root.numeric ? Qt.ImhDigitsOnly : Qt.ImhNone
    validator: root.numeric ? digits : null

    IntValidator { id: digits; bottom: 0; top: 99999 }

    onActiveFocusChanged: {
      if (activeFocus) Theme.focusedField = input
      else if (Theme.focusedField === input) Theme.focusedField = null
    }
    Component.onDestruction: if (Theme.focusedField === input) Theme.focusedField = null

    Keys.onReturnPressed: root.submit()
    Keys.onEnterPressed: root.submit()
    Keys.onEscapePressed: {
      if (input.text !== "") input.text = ""
      else root.escaped()
    }

    Text {
      anchors.fill: parent
      verticalAlignment: Text.AlignVCenter
      visible: input.text === "" && !input.preeditText
      text: root.placeholder
      color: Theme.tertiary
      font: input.font
      elide: Text.ElideRight
    }
  }

  function submit() {
    var value = input.text.trim()
    if (value === "") return
    root.submitted(value)
    if (root.clearOnSubmit) input.text = ""
  }
}
