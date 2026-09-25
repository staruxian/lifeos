import QtQuick
import "../components"

// "New habit" row that opens into a small form.
Card {
  id: root

  property var host: null
  property bool expanded: false
  property string kind: "check"
  property int days: 127

  readonly property var kinds: [
    { key: "check", label: "Do it" },
    { key: "count", label: "Count it" },
    { key: "avoid", label: "Avoid it" }
  ]
  readonly property string kindHint: kind === "count"
    ? "Reach a number each day — 8 glasses of water, 20 push-ups."
    : kind === "avoid"
      ? "Something you are staying away from. Every clean day fills a square."
      : "Done or not. One tap a day."
  readonly property bool valid: nameField.text.trim() !== "" && (kind !== "count" || Number(targetField.text) > 0) && (kind === "avoid" || days > 0)

  function openForm() {
    expanded = true
    Qt.callLater(nameField.focusInput)
  }

  function reset() {
    nameField.clear()
    targetField.text = ""
    unitField.clear()
    kind = "check"
    days = 127
    expanded = false
  }

  function daysArg() {
    var names = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
    var out = []
    for (var i = 0; i < 7; i++) if (days & (1 << i)) out.push(names[i])
    return out.join(",")
  }

  function submit() {
    if (!valid) return
    host.addHabit({
      name: nameField.text.trim(),
      kind: kind,
      target: Number(targetField.text) || 1,
      unit: unitField.text.trim(),
      days: kind === "avoid" || days === 127 ? "" : daysArg()
    })
    reset()
  }

  width: parent ? parent.width : implicitWidth
  hoverable: !expanded
  padding: expanded ? Theme.pad : Theme.s(4)
  spacing: Theme.s(12)

  // Collapsed: a single tappable row.
  Item {
    visible: !root.expanded
    width: parent.width
    height: Theme.rowHeight

    Row {
      anchors.left: parent.left
      anchors.leftMargin: Theme.s(10)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Theme.s(10)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "\u{f0415}"
        color: Theme.good
        font.family: Theme.iconFont
        font.pixelSize: Theme.headline
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "New habit"
        color: Theme.good
        font.family: Theme.font
        font.pixelSize: Theme.body
        font.weight: Font.DemiBold
      }
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: root.openForm()
    }
  }

  Field {
    id: nameField
    visible: root.expanded
    width: parent.width
    placeholder: "Name — Meditate, Drink water, No sugar…"
    clearOnSubmit: false
    onSubmitted: root.submit()
    onEscaped: root.reset()
  }

  Column {
    visible: root.expanded
    width: parent.width
    spacing: Theme.s(6)

    SegmentedControl {
      width: parent.width
      compact: true
      model: root.kinds
      current: root.kind
      onPicked: function(key) { root.kind = key }
    }

    Text {
      width: parent.width
      leftPadding: Theme.s(4)
      text: root.kindHint
      color: Theme.tertiary
      font.family: Theme.font
      font.pixelSize: Theme.footnote
      wrapMode: Text.WordWrap
    }
  }

  Row {
    visible: root.expanded && root.kind === "count"
    width: parent.width
    spacing: Theme.s(8)

    Field {
      id: targetField
      width: Theme.s(90)
      numeric: true
      placeholder: "Goal"
      clearOnSubmit: false
      onSubmitted: root.submit()
      onEscaped: root.reset()
    }
    Field {
      id: unitField
      width: parent.width - targetField.width - parent.spacing
      placeholder: "Unit — glasses, pages, minutes"
      clearOnSubmit: false
      onSubmitted: root.submit()
      onEscaped: root.reset()
    }
  }

  Column {
    visible: root.expanded && root.kind !== "avoid"
    width: parent.width
    spacing: Theme.s(6)

    SectionHeader { text: "Repeat"; trailing: root.days === 127 ? "Every day" : root.days === 31 ? "Weekdays" : "" }

    Row {
      spacing: Theme.s(6)
      Repeater {
        model: ["M", "T", "W", "T", "F", "S", "S"]
        Chip {
          required property string modelData
          required property int index
          round: true
          text: modelData
          selected: (root.days & (1 << index)) !== 0
          tint: Theme.good
          onClicked: root.days ^= (1 << index)
        }
      }
    }
  }

  Row {
    visible: root.expanded
    anchors.right: parent.right
    spacing: Theme.s(8)

    PillButton { text: "Cancel"; primary: false; onClicked: root.reset() }
    PillButton { text: "Add habit"; active: root.valid; onClicked: root.submit() }
  }
}
