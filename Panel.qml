import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "components"
import "pages"
import "Model.js" as Model

// The LifeOS panel: a date header with the day's ring, a segmented control,
// and one page per area. Pages stay alive while hidden so a half-typed task
// survives a peek at another tab.
Panel {
  id: root
  moduleName: "staruxian.lifeos"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  readonly property var snap: hostWidget ? hostWidget.state : null

  readonly property var tabs: [
    { key: "today", label: "Today" },
    { key: "tasks", label: "Tasks" },
    { key: "habits", label: "Habits" },
    { key: "books", label: "Reading" },
    { key: "events", label: "Countdowns" }
  ]
  property string tab: "today"
  readonly property int tabIndex: {
    for (var i = 0; i < tabs.length; i++) if (tabs[i].key === tab) return i
    return 0
  }
  readonly property var pages: [todayPage, tasksPage, habitsPage, booksPage, eventsPage]
  readonly property var page: pages[tabIndex]

  function open() {
    root.controller.show()
    if (hostWidget) hostWidget.refresh()
  }

  function close() {
    Theme.focusedField = null
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function openTab(key, focusAdd) {
    selectTab(key)
    if (!root.opened) root.open()
    if (focusAdd) Qt.callLater(function() { if (root.page && root.page.focusAdd) root.page.focusAdd() })
  }

  function selectTab(key) {
    for (var i = 0; i < tabs.length; i++) if (tabs[i].key === key) { root.tab = key; return }
  }

  function stepTab(delta) {
    root.tab = tabs[(tabIndex + delta + tabs.length) % tabs.length].key
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function releaseKeyboard() {
    Theme.focusedField = null
    keyCatcher.forceActiveFocus()
  }

  // ---- errors surface as a small banner that fades on its own -------------

  property string toast: ""
  Connections {
    target: root.hostWidget
    function onErrorSerialChanged() {
      root.toast = root.hostWidget.lastError
      toastTimer.restart()
    }
  }
  Timer { id: toastTimer; interval: 3600; onTriggered: root.toast = "" }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    padding: Theme.s(18)
    contentWidth: panel.fittedContentWidth(Theme.s(456))
    contentHeight: panel.fittedContentHeight(layout.implicitHeight, Theme.s(720))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: Theme.focusedField !== null

      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (dx !== 0) root.stepTab(dx)
        else scroller.flick(0, -dy * 900)
      }
      onTextKey: function(t) {
        var n = Number(t)
        if (n >= 1 && n <= root.tabs.length) root.tab = root.tabs[n - 1].key
        else if ((t === "n" || t === "a" || t === "/") && root.page.focusAdd) root.page.focusAdd()
        else if (t === "r" && root.hostWidget) root.hostWidget.refresh()
      }

      // Clicking empty panel space takes the keyboard back from a field.
      TapHandler { onTapped: root.releaseKeyboard() }

      Column {
        id: layout
        width: parent.width
        spacing: Theme.s(16)

        // ---- header
        Item {
          width: parent.width
          height: Math.max(dateColumn.implicitHeight, dayRing.height)

          Column {
            id: dateColumn
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.s(1)

            Text {
              text: root.snap ? Model.weekdayName(root.snap.today).toUpperCase() : ""
              color: Theme.accent.hslSaturation > 0.3 ? Theme.accent : Theme.tertiary
              font.family: Theme.font
              font.pixelSize: Theme.footnote
              font.weight: Font.DemiBold
              font.letterSpacing: 1.1
            }

            Text {
              text: root.snap ? Model.longDate(root.snap.today) : "LifeOS"
              color: Theme.label
              font.family: Theme.font
              font.pixelSize: Theme.largeTitle
              font.weight: Font.Bold
              font.letterSpacing: -0.4
            }
          }

          Ring {
            id: dayRing
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            size: Theme.s(46)
            lineWidth: Theme.s(5)
            value: root.hostWidget ? root.hostWidget.progress : 0

            Text {
              anchors.centerIn: parent
              text: Model.percent(dayRing.value)
              color: Theme.secondary
              font.family: Theme.font
              font.pixelSize: Theme.caption
              font.weight: Font.DemiBold
              font.features: ({ "tnum": 1 })
            }

            HoverHandler { id: ringHover }
            PanelToolTip {
              visible: ringHover.hovered
              text: "Today's habits and tasks"
              fontFamily: Theme.font
            }
          }
        }

        SegmentedControl {
          width: parent.width
          model: root.tabs
          current: root.tab
          onPicked: function(key) { root.tab = key; root.releaseKeyboard() }
        }

        // ---- first run without Bun: one button away from working
        Card {
          visible: root.hostWidget !== null && root.hostWidget.cliMissing
          width: parent.width
          padding: Theme.s(20)
          spacing: Theme.s(12)

          Text {
            width: parent.width
            text: "One more step"
            color: Theme.label
            font.family: Theme.font
            font.pixelSize: Theme.title
            font.weight: Font.Bold
          }
          Text {
            width: parent.width
            text: "LifeOS keeps your data in a small local database, run by Bun. Install it and this panel comes alive — nothing else to set up."
            color: Theme.secondary
            font.family: Theme.font
            font.pixelSize: Theme.body
            wrapMode: Text.WordWrap
            lineHeight: 1.15
          }
          Rectangle {
            width: parent.width
            height: cmdText.implicitHeight + Theme.s(16)
            radius: Theme.radiusControl
            color: Theme.fillStrong
            Text {
              id: cmdText
              anchors.centerIn: parent
              text: root.hostWidget ? root.hostWidget.setupCommand : ""
              color: Theme.label
              font.family: Theme.iconFont
              font.pixelSize: Theme.callout
            }
          }
          PillButton {
            anchors.right: parent.right
            text: "Install Bun"
            onClicked: root.hostWidget.setup()
          }
        }

        // ---- pages
        Flickable {
          id: scroller
          visible: !(root.hostWidget && root.hostWidget.cliMissing)
          width: parent.width
          height: Math.min(contentHeight, Theme.s(560))
          contentWidth: width
          contentHeight: root.page ? root.page.implicitHeight : 0
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height
          flickDeceleration: 2600
          Behavior on height { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }

          TodayPage { id: todayPage; width: scroller.width; host: root.hostWidget; snap: root.snap; active: root.tab === "today"; onNavigate: function(key, focusAdd) { root.openTab(key, focusAdd) } }
          TasksPage { id: tasksPage; width: scroller.width; host: root.hostWidget; snap: root.snap; active: root.tab === "tasks" }
          HabitsPage { id: habitsPage; width: scroller.width; host: root.hostWidget; snap: root.snap; active: root.tab === "habits" }
          BooksPage { id: booksPage; width: scroller.width; host: root.hostWidget; snap: root.snap; active: root.tab === "books" }
          EventsPage { id: eventsPage; width: scroller.width; host: root.hostWidget; snap: root.snap; active: root.tab === "events" }

          onContentHeightChanged: if (contentY > Math.max(0, contentHeight - height)) contentY = Math.max(0, contentHeight - height)
        }
      }

      // ---- error banner
      Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        width: Math.min(parent.width, toastText.implicitWidth + Theme.s(32))
        height: toastText.implicitHeight + Theme.s(16)
        radius: height / 2
        color: Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.92)
        opacity: root.toast !== "" ? 1 : 0
        visible: opacity > 0
        y: root.toast !== "" ? 0 : Theme.s(8)
        Behavior on opacity { NumberAnimation { duration: Theme.normal } }

        Text {
          id: toastText
          anchors.centerIn: parent
          width: Math.min(implicitWidth, root.width - Theme.s(64))
          text: root.toast
          color: "white"
          font.family: Theme.font
          font.pixelSize: Theme.callout
          font.weight: Font.Medium
          elide: Text.ElideRight
        }
      }
    }
  }
}
