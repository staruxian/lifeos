import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "components"
import "pages"
import "views"
import "Model.js" as Model

// The LifeOS panel: a greeting and the day's ring, then either the five tabs
// or one of the day's rituals (morning plan, evening shutdown, weekly score)
// or settings, which take the whole panel until they are done. Pages stay
// alive while hidden so a half-typed task survives a peek at another tab.
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
  // "" shows the tabs; otherwise "plan", "shutdown", "week" or "settings".
  property string mode: ""
  readonly property int tabIndex: {
    for (var i = 0; i < tabs.length; i++) if (tabs[i].key === tab) return i
    return 0
  }
  readonly property var pages: [todayPage, tasksPage, habitsPage, booksPage, eventsPage]
  readonly property var views: ({ plan: planView, shutdown: shutdownView, week: weekView, settings: settingsView })
  readonly property var page: mode !== "" ? views[mode] : pages[tabIndex]
  readonly property var modeTitles: ({ plan: "Plan your day", shutdown: "Shut down", week: "Your week", settings: "Settings" })

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
    root.mode = ""
    selectTab(key)
    if (!root.opened) root.open()
    if (focusAdd) Qt.callLater(function() { if (root.page && root.page.focusAdd) root.page.focusAdd() })
  }

  function openMode(key) {
    root.mode = key
    if (!root.opened) root.open()
    scroller.contentY = 0
  }

  function leaveMode() {
    root.mode = ""
    root.releaseKeyboard()
  }

  function selectTab(key) {
    for (var i = 0; i < tabs.length; i++) if (tabs[i].key === key) { root.tab = key; return }
  }

  function stepTab(delta) {
    root.mode = ""
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

  // ---- banners: errors in red; changes in grey with Undo ------------------

  property string toast: ""
  property bool toastIsError: false
  Connections {
    target: root.hostWidget
    function onErrorSerialChanged() {
      root.toast = root.hostWidget.lastError
      root.toastIsError = true
      toastTimer.interval = 3600
      toastTimer.restart()
    }
    function onChangeSerialChanged() {
      if (!root.opened) return
      root.toast = root.hostWidget.lastChange
      root.toastIsError = false
      toastTimer.interval = 5500
      toastTimer.restart()
    }
    function onCelebrateSerialChanged() {
      if (root.opened) confetti.burst()
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
    contentHeight: panel.fittedContentHeight(layout.implicitHeight, Theme.s(740))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: Theme.focusedField !== null

      onCloseRequested: root.mode !== "" ? root.leaveMode() : root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (dx !== 0 && root.mode === "") root.stepTab(dx)
        else if (dy !== 0) scroller.flick(0, -dy * 900)
      }
      onTextKey: function(t) {
        var n = Number(t)
        if (n >= 1 && n <= root.tabs.length) { root.mode = ""; root.tab = root.tabs[n - 1].key }
        else if ((t === "n" || t === "a" || t === "/") && root.page.focusAdd) root.page.focusAdd()
        else if (t === "u" && root.hostWidget) root.hostWidget.undo()
        else if (t === "p") root.openMode("plan")
        else if (t === "s") root.openMode("shutdown")
        else if (t === "w") root.openMode("week")
        else if (t === "," ) root.openMode("settings")
        else if (t === "r" && root.hostWidget) root.hostWidget.refresh()
      }

      // Clicking empty panel space takes the keyboard back from a field.
      TapHandler { onTapped: root.releaseKeyboard() }

      Column {
        id: layout
        width: parent.width
        spacing: Theme.s(16)

        // ---- header: greeting, date, settings, the day's ring
        Item {
          width: parent.width
          height: Math.max(dateColumn.implicitHeight, dayRing.height)

          Column {
            id: dateColumn
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.s(1)

            Text {
              text: root.snap && root.snap.day
                ? (root.snap.day.greeting + "  ·  " + Model.weekdayName(root.snap.today)).toUpperCase()
                : ""
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

          Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.s(10)

            IconButton {
              anchors.verticalCenter: parent.verticalCenter
              icon: "\u{f0493}"
              tooltip: "Settings"
              color: root.mode === "settings" ? Theme.label : Theme.tertiary
              onClicked: root.mode === "settings" ? root.leaveMode() : root.openMode("settings")
            }

            Ring {
              id: dayRing
              anchors.verticalCenter: parent.verticalCenter
              size: Theme.s(46)
              lineWidth: Theme.s(5)
              value: root.hostWidget ? root.hostWidget.progress : 0
              color: root.hostWidget && root.hostWidget.alert === "urgent" ? Theme.danger
                : root.hostWidget && root.hostWidget.alert === "warn" ? Theme.fire : Theme.good

              Text {
                anchors.centerIn: parent
                text: Model.percent(dayRing.value)
                color: Theme.secondary
                font.family: Theme.font
                font.pixelSize: Theme.caption
                font.weight: Font.DemiBold
                font.features: ({ "tnum": 1 })
              }

              HoverHandler { id: ringHover; cursorShape: Qt.PointingHandCursor }
              TapHandler { onTapped: root.mode === "week" ? root.leaveMode() : root.openMode("week") }
              PanelToolTip {
                visible: ringHover.hovered
                text: "Today's habits and tasks — click for your week"
                fontFamily: Theme.font
              }
            }
          }
        }

        // ---- tabs, or the way back from a ritual
        SegmentedControl {
          visible: root.mode === ""
          width: parent.width
          model: root.tabs
          current: root.tab
          onPicked: function(key) { root.tab = key; root.releaseKeyboard() }
        }

        Item {
          visible: root.mode !== ""
          width: parent.width
          height: Theme.s(32)

          Rectangle {
            id: back
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: backRow.implicitWidth + Theme.s(20)
            height: Theme.s(28)
            radius: height / 2
            color: backMouse.containsMouse ? Theme.fillHover : Theme.fill

            Row {
              id: backRow
              anchors.centerIn: parent
              spacing: Theme.s(4)
              Text { anchors.verticalCenter: parent.verticalCenter; text: "\u{f0141}"; color: Theme.secondary; font.family: Theme.iconFont; font.pixelSize: Theme.body }
              Text { anchors.verticalCenter: parent.verticalCenter; text: "Today"; color: Theme.secondary; font.family: Theme.font; font.pixelSize: Theme.callout; font.weight: Font.Medium }
            }
            MouseArea { id: backMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.leaveMode() }
          }

          Text {
            anchors.centerIn: parent
            text: root.modeTitles[root.mode] || ""
            color: Theme.label
            font.family: Theme.font
            font.pixelSize: Theme.headline
            font.weight: Font.DemiBold
          }
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

        // ---- content
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

          TodayPage { id: todayPage; width: scroller.width; host: root.hostWidget; snap: root.snap; active: root.mode === "" && root.tab === "today"; onNavigate: function(key, focusAdd) { key.indexOf("mode:") === 0 ? root.openMode(key.slice(5)) : root.openTab(key, focusAdd) } }
          TasksPage { id: tasksPage; width: scroller.width; host: root.hostWidget; snap: root.snap; active: root.mode === "" && root.tab === "tasks" }
          HabitsPage { id: habitsPage; width: scroller.width; host: root.hostWidget; snap: root.snap; active: root.mode === "" && root.tab === "habits" }
          BooksPage { id: booksPage; width: scroller.width; host: root.hostWidget; snap: root.snap; active: root.mode === "" && root.tab === "books" }
          EventsPage { id: eventsPage; width: scroller.width; host: root.hostWidget; snap: root.snap; active: root.mode === "" && root.tab === "events" }

          PlanView { id: planView; width: scroller.width; host: root.hostWidget; snap: root.snap; active: root.mode === "plan"; onFinished: root.leaveMode() }
          ShutdownView { id: shutdownView; width: scroller.width; host: root.hostWidget; snap: root.snap; active: root.mode === "shutdown"; onFinished: root.leaveMode() }
          WeekView { id: weekView; width: scroller.width; host: root.hostWidget; snap: root.snap; active: root.mode === "week"; onFinished: root.leaveMode() }
          SettingsView { id: settingsView; width: scroller.width; host: root.hostWidget; snap: root.snap; active: root.mode === "settings"; onFinished: root.leaveMode() }

          onContentHeightChanged: if (contentY > Math.max(0, contentHeight - height)) contentY = Math.max(0, contentHeight - height)
        }
      }

      // ---- the banner: a floating pill over the bottom of the panel
      Rectangle {
        id: banner
        readonly property real maxWidth: keyCatcher.width - Theme.s(24)
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.s(4)
        width: Math.min(maxWidth, toastRow.implicitWidth + Theme.s(32))
        height: Theme.s(38)
        radius: height / 2
        // Opaque, and a step lighter than the panel, so it reads as floating.
        color: root.toastIsError ? Theme.danger : Qt.tint(Theme.bg, Theme.alpha(Theme.fg, 0.14))
        border.width: 1
        border.color: root.toastIsError ? "transparent" : Theme.alpha(Theme.fg, 0.12)
        opacity: root.toast !== "" ? 1 : 0
        visible: opacity > 0
        scale: root.toast !== "" ? 1 : 0.94
        Behavior on opacity { NumberAnimation { duration: Theme.normal } }
        Behavior on scale { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }

        // Swallow clicks so they do not fall through to the card underneath.
        MouseArea { anchors.fill: parent }

        Row {
          id: toastRow
          anchors.centerIn: parent
          spacing: Theme.s(14)

          Text {
            id: toastLabel
            readonly property real room: banner.maxWidth - Theme.s(32) - (undoLabel.visible ? undoLabel.implicitWidth + toastRow.spacing : 0)
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, room)
            text: root.toast
            color: root.toastIsError ? "white" : Theme.label
            font.family: Theme.font
            font.pixelSize: Theme.callout
            font.weight: Font.Medium
            elide: Text.ElideRight
          }

          Text {
            id: undoLabel
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.toastIsError && root.toast.indexOf("Undid") !== 0
            text: "Undo"
            color: Theme.good
            font.family: Theme.font
            font.pixelSize: Theme.callout
            font.weight: Font.Bold

            MouseArea {
              anchors.fill: parent
              anchors.margins: -Theme.s(8)
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                root.toast = ""
                if (root.hostWidget) root.hostWidget.undo()
              }
            }
          }
        }
      }

      Confetti { id: confetti; anchors.fill: parent }
    }
  }
}
