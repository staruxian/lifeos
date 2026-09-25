import QtQuick
import "../components"
import "../Model.js" as Model

// One task: check, title, when it is due. Delete shows on hover.
Item {
  id: root

  property var task: null
  property var host: null
  property bool showDue: true

  readonly property bool overdue: task && !task.done && task.daysUntil !== null && task.daysUntil < 0

  width: parent ? parent.width : implicitWidth
  implicitHeight: Theme.rowHeight + Theme.s(2)

  HoverHandler { id: hover }

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
    id: title
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
  }

  Row {
    id: trailing
    anchors.right: parent.right
    anchors.rightMargin: Theme.s(4)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Theme.s(2)

    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: root.showDue && text !== "" && !check.on
      text: root.task ? Model.dueLabel(root.task) : ""
      color: root.overdue ? Theme.danger : (root.task && root.task.daysUntil === 0 ? Theme.secondary : Theme.tertiary)
      font.family: Theme.font
      font.pixelSize: Theme.footnote
      font.weight: root.overdue ? Font.DemiBold : Font.Normal
      rightPadding: Theme.s(6)
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
