import QtQuick

// iOS-style segmented control: a sliding thumb under equal-width labels.
Rectangle {
  id: root

  // [{ key, label }]
  property var model: []
  property string current: model.length ? model[0].key : ""
  property bool compact: false

  signal picked(string key)

  readonly property int index: {
    for (var i = 0; i < model.length; i++) if (model[i].key === current) return i
    return 0
  }
  readonly property real segment: model.length ? (width - inset * 2) / model.length : 0
  readonly property int inset: Theme.s(2)

  implicitWidth: Theme.s(360)
  implicitHeight: compact ? Theme.s(28) : Theme.s(32)
  radius: Theme.radiusControl
  color: Theme.fill

  Rectangle {
    id: thumb
    y: root.inset
    height: root.height - root.inset * 2
    width: root.segment
    x: root.inset + root.segment * root.index
    radius: root.radius - root.inset
    color: Theme.fillStrong
    border.width: 1
    border.color: Theme.separator
    Behavior on x { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutBack; easing.overshoot: 0.7 } }
  }

  Row {
    x: root.inset
    y: root.inset
    height: root.height - root.inset * 2

    Repeater {
      model: root.model

      Item {
        required property var modelData
        required property int index
        width: root.segment
        height: parent.height

        Text {
          anchors.centerIn: parent
          text: modelData.label
          color: index === root.index ? Theme.label : (mouse.containsMouse ? Theme.secondary : Theme.tertiary)
          font.family: Theme.font
          font.pixelSize: root.compact ? Theme.footnote : Theme.callout
          font.weight: index === root.index ? Font.DemiBold : Font.Medium
          Behavior on color { ColorAnimation { duration: Theme.fast } }
        }

        MouseArea {
          id: mouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          // The owner decides: `current` stays bound to its state.
          onClicked: root.picked(modelData.key)
        }
      }
    }
  }
}
