import QtQuick
import "../components"
import "../Model.js" as Model

// Compact habit line for the Today page.
Item {
  id: root

  property var habit: null
  property var host: null

  width: parent ? parent.width : implicitWidth
  implicitHeight: Theme.s(46)

  Column {
    anchors.left: parent.left
    anchors.leftMargin: Theme.s(10)
    anchors.right: control.left
    anchors.rightMargin: Theme.s(10)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Theme.s(1)

    Row {
      width: parent.width
      spacing: Theme.s(6)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, parent.width - (flame.visible ? flame.width + parent.spacing : 0))
        text: root.habit ? root.habit.name : ""
        color: Theme.label
        font.family: Theme.font
        font.pixelSize: Theme.body
        font.weight: Font.Medium
        elide: Text.ElideRight
      }

      Flame {
        id: flame
        anchors.verticalCenter: parent.verticalCenter
        visible: root.habit ? root.habit.onFire : false
        streak: root.habit ? root.habit.streak : 0
        size: Theme.s(14)
      }
    }

    Text {
      width: parent.width
      text: root.habit ? Model.habitDetail(root.habit) : ""
      color: Theme.tertiary
      font.family: Theme.font
      font.pixelSize: Theme.footnote
      elide: Text.ElideRight
    }
  }

  HabitControl {
    id: control
    anchors.right: parent.right
    anchors.rightMargin: Theme.s(8)
    anchors.verticalCenter: parent.verticalCenter
    habit: root.habit
    host: root.host
  }
}
