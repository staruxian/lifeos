import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import "components"
import "Model.js" as Model

// Spotlight-style capture: a shortcut, a sentence, Enter. The line below the
// field shows how LifeOS read it before you commit — "pay rent fri" becomes a
// task due Friday, a trailing "!" makes it one of today's priorities, and
// "read 20" logs pages.
Item {
  id: root

  property var host: null
  property bool opened: false
  property bool done: false
  readonly property var preview: host ? host.preview : null
  readonly property string text: field.text.trim()

  function open() {
    done = false
    field.text = ""
    if (host) host.preview = null
    opened = true
    Qt.callLater(function() { field.forceActiveFocus() })
  }

  function close() { opened = false }
  function toggle() { opened ? close() : open() }

  function submit() {
    if (text === "" || !host) return
    host.quick(text)
    done = true
    closeTimer.restart()
  }

  Timer { id: closeTimer; interval: 650; onTriggered: root.close() }
  Timer { id: previewTimer; interval: 120; onTriggered: if (root.host) root.host.parsePreview(root.text) }

  // An error from the CLI (a bad date, say) keeps the box open to fix it.
  Connections {
    target: root.host
    function onErrorSerialChanged() {
      if (!root.opened) return
      closeTimer.stop()
      root.done = false
      error.text = root.host.lastError
      errorTimer.restart()
    }
  }
  Timer { id: errorTimer; interval: 3500; onTriggered: error.text = "" }

  readonly property string previewText: {
    var p = root.preview
    if (!p || root.text === "") return ""
    if (p.kind === "read") {
      var book = root.host && root.host.state ? root.host.state.summary.reading : null
      return book ? "Log " + Model.plural(p.pages, "page") + " · " + book.title : "No book in progress"
    }
    var parts = ["Task"]
    if (p.due) parts.push(Model.dueLabel({ due: p.due, daysUntil: Math.round((Model.parseDay(p.due) - Model.parseDay(root.host.state.today)) / 86400000) }))
    else parts.push("No date")
    if (p.focus) parts.push("★ Priority")
    return parts.join("  ·  ")
  }

  PanelWindow {
    id: window
    visible: root.opened || card.opacity > 0
    screen: {
      var focused = Hyprland.focusedMonitor
      if (focused) for (var i = 0; i < Quickshell.screens.length; i++)
        if (Quickshell.screens[i].name === focused.name) return Quickshell.screens[i]
      return Quickshell.screens[0]
    }
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "lifeos-quick-add"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, 0.32)
      opacity: root.opened ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: Theme.normal } }
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    Rectangle {
      id: card
      width: Math.min(Theme.s(580), window.width - Theme.s(40))
      height: column.implicitHeight + Theme.s(36)
      x: (window.width - width) / 2
      y: window.height * 0.24
      radius: Theme.s(18)
      color: Theme.bg
      border.width: 1
      border.color: Theme.alpha(Theme.fg, 0.12)
      opacity: root.opened ? 1 : 0
      scale: root.opened ? 1 : 0.96
      Behavior on opacity { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }
      Behavior on scale { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }

      MouseArea { anchors.fill: parent }

      Column {
        id: column
        x: Theme.s(20)
        y: Theme.s(18)
        width: parent.width - Theme.s(40)
        spacing: Theme.s(12)

        Item {
          width: parent.width
          height: Theme.s(34)

          // A plus that turns into a check once added.
          Ring {
            id: badge
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            size: Theme.s(26)
            lineWidth: Theme.s(2.5)
            value: root.done ? 1 : 0
            trackColor: Theme.fillStrong

            Text {
              textFormat: Text.PlainText
              anchors.centerIn: parent
              text: root.done ? "\u{f012c}" : "\u{f0415}"
              color: root.done ? Theme.good : Theme.secondary
              font.family: Theme.iconFont
              font.pixelSize: Theme.s(14)
            }
          }

          TextInput {
            id: field
            anchors.left: badge.right
            anchors.leftMargin: Theme.s(14)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.label
            selectionColor: Theme.alpha(Theme.accent, 0.35)
            font.family: Theme.font
            font.pixelSize: Theme.s(20)
            clip: true
            enabled: !root.done
            onTextChanged: previewTimer.restart()
            Keys.onReturnPressed: root.submit()
            Keys.onEnterPressed: root.submit()
            Keys.onEscapePressed: root.close()

            Text {
              textFormat: Text.PlainText
              anchors.fill: parent
              verticalAlignment: Text.AlignVCenter
              visible: field.text === ""
              text: "Add a task…"
              color: Theme.tertiary
              font: field.font
            }
          }
        }

        Rectangle { width: parent.width; height: 1; color: Theme.separator }

        Item {
          width: parent.width
          height: Theme.s(18)

          Text {
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: error.text !== "" ? "" : root.done ? "Added" : root.previewText !== "" ? root.previewText : "fri · next mon · nov 3 · ! for a priority · read 20"
            color: root.done ? Theme.good : root.previewText !== "" ? Theme.secondary : Theme.tertiary
            font.family: Theme.font
            font.pixelSize: Theme.callout
            font.weight: root.previewText !== "" || root.done ? Font.Medium : Font.Normal
          }

          Text {
            textFormat: Text.PlainText
            id: error
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.danger
            font.family: Theme.font
            font.pixelSize: Theme.callout
          }

          Text {
            textFormat: Text.PlainText
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "↵ add   esc close"
            color: Theme.tertiary
            font.family: Theme.font
            font.pixelSize: Theme.footnote
          }
        }
      }
    }
  }
}
