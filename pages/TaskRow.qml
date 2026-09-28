import QtQuick
import qs.Ui
import "../components"
import "../Model.js" as Model

// One task: check, title, when it is due. Double-click the title to rename;
// click the date to move it; the star makes it one of today's priorities.
Item {
  id: root

  property var task: null
  property var host: null
  property bool showDue: true

  property bool editing: false
  property bool moving: false

  readonly property bool overdue: task && !task.done && task.daysUntil !== null && task.daysUntil < 0
  readonly property var presets: [
    { key: "today", label: "Today" },
    { key: "tomorrow", label: "Tomorrow" },
    { key: "sat", label: "Weekend" },
    { key: "next mon", label: "Next week" },
    { key: "none", label: "No date" }
  ]

  function startEdit() {
    editing = true
    Qt.callLater(function() { editor.text = root.task.title; editor.selectAll(); editor.forceActiveFocus() })
  }

  function commitEdit() {
    var text = editor.text.trim()
    if (text !== "" && text !== root.task.title) root.host.renameTask(root.task.id, text)
    editing = false
  }

  function move(key) {
    root.host.setTaskDue(root.task.id, key)
    moving = false
  }

  width: parent ? parent.width : implicitWidth
  implicitHeight: line.height + (moving ? moveBox.implicitHeight + Theme.s(8) : 0)
  clip: true
  Behavior on implicitHeight { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }

  HoverHandler { id: hover }

  Item {
    id: line
    width: parent.width
    height: Theme.rowHeight + Theme.s(2)

    CheckCircle {
      id: check
      anchors.left: parent.left
      anchors.leftMargin: Theme.s(8)
      anchors.verticalCenter: parent.verticalCenter
      size: Theme.s(20)
      checked: root.task ? root.task.done : false
      onToggled: if (root.host) root.host.toggleTask(root.task.id)
    }

    Text {
      textFormat: Text.PlainText
      id: title
      visible: !root.editing
      anchors.left: check.right
      anchors.leftMargin: Theme.s(12)
      anchors.right: trailing.left
      anchors.rightMargin: Theme.s(8)
      anchors.verticalCenter: parent.verticalCenter
      text: root.task ? root.task.title : ""
      color: check.on ? Theme.tertiary : Theme.label
      font.family: Theme.font
      font.pixelSize: Theme.body
      font.strikeout: check.on
      elide: Text.ElideRight
      Behavior on color { ColorAnimation { duration: Theme.normal } }

      TapHandler { onDoubleTapped: root.startEdit() }
    }

    TextInput {
      id: editor
      visible: root.editing
      anchors.left: check.right
      anchors.leftMargin: Theme.s(12)
      anchors.right: trailing.left
      anchors.rightMargin: Theme.s(8)
      anchors.verticalCenter: parent.verticalCenter
      color: Theme.label
      selectionColor: Theme.alpha(Theme.accent, 0.35)
      font.family: Theme.font
      font.pixelSize: Theme.body
      clip: true
      onActiveFocusChanged: {
        if (activeFocus) Theme.focusedField = editor
        else {
          if (Theme.focusedField === editor) Theme.focusedField = null
          if (root.editing) root.commitEdit()
        }
      }
      Keys.onReturnPressed: root.commitEdit()
      Keys.onEnterPressed: root.commitEdit()
      Keys.onEscapePressed: root.editing = false

      Rectangle {
        anchors.fill: parent
        anchors.margins: -Theme.s(4)
        z: -1
        radius: Theme.radiusSmall
        color: Theme.fillStrong
      }
    }

    Row {
      id: trailing
      anchors.right: parent.right
      anchors.rightMargin: Theme.s(4)
      anchors.verticalCenter: parent.verticalCenter
      spacing: 0

      // The due date doubles as the "move" button.
      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        visible: !check.on && (dueText.text !== "" || hover.hovered || root.moving)
        width: dueText.implicitWidth + Theme.s(14)
        height: Theme.s(22)
        radius: height / 2
        color: root.moving || dueMouse.containsMouse ? Theme.fillHover : "transparent"

        Text {
          textFormat: Text.PlainText
          id: dueText
          anchors.centerIn: parent
          text: {
            var label = root.showDue && root.task ? Model.dueLabel(root.task) : ""
            return label !== "" ? label : hover.hovered || root.moving ? "\u{f00ed}" : ""
          }
          color: root.overdue ? Theme.danger : (root.task && root.task.daysUntil === 0 ? Theme.secondary : Theme.tertiary)
          font.family: text.length <= 2 ? Theme.iconFont : Theme.font
          font.pixelSize: Theme.footnote
          font.weight: root.overdue ? Font.DemiBold : Font.Normal
        }

        MouseArea {
          id: dueMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.moving = !root.moving
        }

        PanelToolTip {
          visible: dueMouse.containsMouse && !root.moving
          text: "Move"
          fontFamily: Theme.font
        }
      }

      IconButton {
        anchors.verticalCenter: parent.verticalCenter
        visible: !check.on && (hover.hovered || (root.task && root.task.focus))
        icon: root.task && root.task.focus ? "\u{f04ce}" : "\u{f04d2}"
        tooltip: root.task && root.task.focus ? "Not a priority" : "Make it a priority today"
        color: root.task && root.task.focus ? Theme.fire : Theme.tertiary
        hoverColor: Theme.fire
        onClicked: root.host.focusTask(root.task.id, !root.task.focus)
      }

      DeleteButton {
        anchors.verticalCenter: parent.verticalCenter
        opacity: hover.hovered || armed ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Theme.fast } }
        onConfirmed: if (root.host) root.host.removeTask(root.task.id)
      }
    }
  }

  // Where to move it.
  Flow {
    id: moveBox
    anchors.top: line.bottom
    anchors.topMargin: Theme.s(2)
    x: Theme.s(40)
    width: parent.width - Theme.s(48)
    spacing: Theme.s(6)
    visible: root.moving
    opacity: root.moving ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Theme.fast } }

    Repeater {
      model: root.presets
      Chip {
        required property var modelData
        text: modelData.label
        onClicked: root.move(modelData.key)
      }
    }

    Field {
      width: Theme.s(118)
      height: Theme.s(26)
      placeholder: "or: nov 3"
      onSubmitted: function(text) { root.move(text) }
      onEscaped: root.moving = false
    }
  }
}
