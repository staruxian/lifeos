import QtQuick
import qs.Ui
import "../components"
import "../Model.js" as Model

// A book in progress: pages read, a progress bar, when you will finish at
// your current pace, the last two weeks of reading, and a box to log today.
Card {
  id: root

  property var book: null
  property var host: null
  property bool compact: false

  function focusLog() { pagesField.focusInput() }

  width: parent ? parent.width : implicitWidth
  hoverable: true
  spacing: Theme.s(10)

  Item {
    width: parent.width
    height: titleColumn.implicitHeight

    Column {
      id: titleColumn
      anchors.left: parent.left
      anchors.right: percentText.left
      anchors.rightMargin: Theme.s(10)
      spacing: Theme.s(2)

      Text {
        width: parent.width
        text: root.book ? root.book.title : ""
        color: Theme.label
        font.family: Theme.font
        font.pixelSize: Theme.headline
        font.weight: Font.DemiBold
        elide: Text.ElideRight
      }

      Text {
        text: root.book ? root.book.read + " of " + root.book.total + " pages" : ""
        color: Theme.secondary
        font.family: Theme.font
        font.pixelSize: Theme.footnote
        font.features: ({ "tnum": 1 })
      }
    }

    DeleteButton {
      anchors.right: percentText.left
      anchors.rightMargin: Theme.s(4)
      anchors.top: parent.top
      visible: !root.compact && (root.hovered || armed)
      onConfirmed: root.host.removeBook(root.book.id)
    }

    Text {
      id: percentText
      anchors.right: parent.right
      anchors.top: parent.top
      text: root.book ? Model.percent(root.book.percent) : ""
      color: Theme.label
      font.family: Theme.font
      font.pixelSize: Theme.title
      font.weight: Font.Bold
      font.features: ({ "tnum": 1 })
    }
  }

  ProgressBar {
    width: parent.width
    value: root.book ? root.book.percent : 0
  }

  // Two weeks of reading as tiny columns; today is the bright one.
  Item {
    id: chart
    visible: !root.compact
    width: parent.width
    height: Theme.s(34)

    readonly property var days: root.book ? root.book.recent : []
    readonly property int maxPages: {
      var m = 1
      for (var i = 0; i < days.length; i++) m = Math.max(m, days[i].pages)
      return m
    }

    Row {
      id: bars
      anchors.bottom: parent.bottom
      spacing: Theme.s(3)
      readonly property real barWidth: (chart.width - spacing * 13) / 14

      Repeater {
        model: chart.days

        Rectangle {
          required property var modelData
          required property int index
          readonly property bool isToday: index === 13
          anchors.bottom: parent.bottom
          width: bars.barWidth
          height: modelData.pages > 0 ? Math.max(Theme.s(3), chart.height * modelData.pages / chart.maxPages) : Theme.s(3)
          radius: Math.min(width / 2, Theme.s(3))
          color: modelData.pages === 0 ? Theme.fillStrong : isToday ? Theme.good : Theme.alpha(Theme.good, 0.45)
          Behavior on height { NumberAnimation { duration: Theme.slow; easing.type: Easing.OutCubic } }

          HoverHandler { id: barHover }
          PanelToolTip {
            visible: barHover.hovered
            text: Model.shortDate(modelData.day, true) + " · " + Model.plural(modelData.pages, "page")
            fontFamily: Theme.font
          }
        }
      }
    }
  }

  Text {
    width: parent.width
    text: root.book ? Model.bookEta(root.book) : ""
    color: Theme.tertiary
    font.family: Theme.font
    font.pixelSize: Theme.footnote
    elide: Text.ElideRight
  }

  Row {
    width: parent.width
    spacing: Theme.s(8)

    Field {
      id: pagesField
      width: parent.width - logButton.width - parent.spacing
      numeric: true
      icon: "\u{f00ba}"
      placeholder: root.book && root.book.today > 0
        ? root.book.today + " pages today — add more"
        : "Pages read today"
      onSubmitted: function(text) { root.log(text) }
    }

    PillButton {
      id: logButton
      anchors.verticalCenter: parent.verticalCenter
      text: "Log"
      active: Number(pagesField.text) > 0
      onClicked: { root.log(pagesField.text); pagesField.clear() }
    }
  }

  function log(text) {
    var pages = Number(text)
    if (pages > 0 && root.host) root.host.logPages(root.book.id, pages)
  }
}
