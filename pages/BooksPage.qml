import QtQuick
import "../components"
import "../Model.js" as Model

PageBase {
  id: root

  readonly property var reading: snap ? snap.books.reading : []
  readonly property var finished: snap ? snap.books.finished : []

  function focusAdd() {
    if (bookRepeater.count > 0) bookRepeater.itemAt(0).focusLog()
    else newBook.openForm()
  }

  spacing: Theme.s(10)

  Repeater {
    id: bookRepeater
    model: root.reading
    BookCard {
      required property var modelData
      book: modelData
      host: root.host
    }
  }

  EmptyState {
    visible: root.snap !== null && root.reading.length === 0 && !newBook.expanded
    icon: "\u{f00ba}"
    title: root.finished.length ? "Pick your next book" : "What are you reading?"
    hint: "Add a book and its page count, then log the pages you read each day. LifeOS works out when you will finish."
  }

  NewBook { id: newBook; host: root.host }

  Column {
    visible: root.finished.length > 0
    width: parent.width
    spacing: Theme.s(6)
    topPadding: Theme.s(8)

    SectionHeader { text: "Finished"; trailing: String(root.finished.length) }

    Card {
      width: parent.width
      padding: Theme.s(3)
      spacing: 0

      Repeater {
        model: root.finished

        Column {
          required property var modelData
          required property int index
          width: parent.width

          Hairline { visible: index > 0; inset: Theme.s(40) }

          Item {
            width: parent.width
            height: Theme.rowHeight + Theme.s(2)

            HoverHandler { id: rowHover }

            Text {
              id: tick
              anchors.left: parent.left
              anchors.leftMargin: Theme.s(12)
              anchors.verticalCenter: parent.verticalCenter
              text: "\u{f012c}"
              color: Theme.good
              font.family: Theme.iconFont
              font.pixelSize: Theme.body
            }
            Text {
              anchors.left: tick.right
              anchors.leftMargin: Theme.s(14)
              anchors.right: meta.left
              anchors.rightMargin: Theme.s(8)
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.title
              color: Theme.label
              font.family: Theme.font
              font.pixelSize: Theme.body
              elide: Text.ElideRight
            }
            Row {
              id: meta
              anchors.right: parent.right
              anchors.rightMargin: Theme.s(4)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Theme.s(2)
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.total + " p · " + Model.shortDate(modelData.finishedOn, false)
                color: Theme.tertiary
                font.family: Theme.font
                font.pixelSize: Theme.footnote
                rightPadding: Theme.s(6)
              }
              DeleteButton {
                anchors.verticalCenter: parent.verticalCenter
                opacity: rowHover.hovered || armed ? 1 : 0
                onConfirmed: root.host.removeBook(modelData.id)
              }
            }
          }
        }
      }
    }
  }
}
