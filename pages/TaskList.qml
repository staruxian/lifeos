import QtQuick
import "../components"

// A titled, inset group of tasks separated by hairlines.
Column {
  id: root

  property string title: ""
  property string trailing: ""
  property color titleColor: Theme.tertiary
  property var tasks: []
  property var host: null
  property bool showDue: true

  width: parent ? parent.width : implicitWidth
  spacing: Theme.s(6)
  visible: tasks.length > 0

  SectionHeader {
    visible: root.title !== ""
    text: root.title
    trailing: root.trailing
    color: root.titleColor
  }

  Card {
    width: parent.width
    padding: Theme.s(3)
    spacing: 0

    Repeater {
      model: root.tasks

      Column {
        required property var modelData
        required property int index
        width: parent.width

        Hairline { visible: index > 0; inset: Theme.s(40) }
        TaskRow { task: modelData; host: root.host; showDue: root.showDue }
      }
    }
  }
}
