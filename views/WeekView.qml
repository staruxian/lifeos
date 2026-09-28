import QtQuick
import "../components"

ViewBase {
  id: root

  readonly property var review: snap ? snap.review : null
  signal insights()

  Lead {
    title: "Promises kept"
    subtitle: "Every scheduled habit and every priority is a promise to yourself. Here is how many you kept."
  }

  WeekCard { week: root.review ? root.review.thisWeek : null; previous: root.review ? root.review.lastWeek : null; title: "This week" }
  WeekCard { week: root.review ? root.review.lastWeek : null; previous: null; title: "Last week" }

  Row {
    anchors.right: parent.right
    spacing: Theme.s(8)

    PillButton {
      text: "Insights"
      icon: "\u{f02fc}"
      primary: false
      onClicked: root.insights()
    }

    PillButton {
      text: root.review && root.review.due ? "Got it" : "Done"
      onClicked: {
        if (root.review && root.review.due) root.host.reviewSeen()
        root.finished()
      }
    }
  }
}
