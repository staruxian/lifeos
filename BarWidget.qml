import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "components"
import "Model.js" as Model

// The bar end of LifeOS: today's progress ring plus one short label, and the
// owner of the data. Every change goes through the `lifeos` CLI, which
// rewrites ~/.local/state/lifeos/state.json; that file is watched, so edits
// made from a terminal show up here too.
BarWidget {
  id: root
  moduleName: "staruxian.lifeos"

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string pluginDir: {
    var url = String(Qt.resolvedUrl("."))
    var path = url.indexOf("file://") === 0 ? decodeURIComponent(url.slice(7)) : url
    return path.replace(/\/$/, "")
  }
  readonly property string statePath: Quickshell.env("LIFEOS_STATE")
    || (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/lifeos/state.json"

  property var state: null
  property string lastError: ""
  property int errorSerial: 0
  // A change made from the panel that can be undone, announced once.
  property string lastChange: ""
  property int changeSerial: 0
  // Bumped when the day becomes complete while LifeOS is running.
  property int celebrateSerial: 0
  // A streak just reached a milestone: what to say, announced once.
  property string milestoneText: ""
  property int milestoneSerial: 0
  readonly property var summary: state ? state.summary : null
  readonly property real progress: Model.dayProgress(summary)
  readonly property string alert: state && state.day ? state.day.alert : "none"
  readonly property bool strict: state && state.settings ? state.settings.strict === "on" : false

  // One bar per monitor: only the first does the once-per-session work
  // (reminders, opening the plan, the quick-add box).
  readonly property bool leader: {
    if (!bar || typeof bar.moduleWidgets !== "function") return true
    var peers = bar.moduleWidgets(moduleName)
    return !peers || peers.length === 0 || peers[0] === root
  }

  readonly property string labelMode: {
    var mode = String(setting("label", "event"))
    return ["event", "tasks", "habits", "none"].indexOf(mode) >= 0 ? mode : "event"
  }

  readonly property string labelText: {
    if (!summary || vertical) return ""
    if (labelMode === "event" && summary.nextEvent) {
      var e = summary.nextEvent
      return (e.emoji ? e.emoji + " " : "") + Model.countdownShort(e.daysLeft)
    }
    if (labelMode === "tasks" && summary.tasksLeft > 0) return String(summary.tasksLeft)
    if (labelMode === "habits" && summary.habitsDue > 0) return summary.habitsDone + "/" + summary.habitsDue
    return ""
  }

  readonly property string tooltip: {
    if (!summary) return "LifeOS"
    var parts = []
    if (summary.tasksLeft > 0) parts.push(Model.plural(summary.tasksLeft, "task") + " left")
    else if (summary.tasksDoneToday > 0) parts.push("All tasks done")
    if (summary.habitsDue > 0) parts.push(summary.habitsDone + " of " + summary.habitsDue + " habits")
    if (summary.nextEvent) parts.push(summary.nextEvent.title + " · " + Model.countdownWord(summary.nextEvent.daysLeft).toLowerCase())
    return parts.length ? parts.join("  ·  ") : "LifeOS — a clean slate"
  }

  // ---- CLI --------------------------------------------------------------

  // How to reach the CLI, in order of preference: $LIFEOS_BIN, the compiled
  // ~/.local/bin/lifeos from install.sh, or Bun running the source that
  // ships in this plugin. Empty until found; `cliMissing` once we know Bun
  // is not installed either.
  property var cliCommand: []
  property bool cliMissing: false
  readonly property string setupCommand: "omarchy pkg add bun"

  Process {
    id: locate
    command: ["bash", "-c", ""
      + "dir=\"$1\"; "
      + "if [[ -n \"$LIFEOS_BIN\" && -x \"$LIFEOS_BIN\" ]]; then printf '%s\\n' \"$LIFEOS_BIN\"; exit; fi; "
      + "if [[ -x \"$HOME/.local/bin/lifeos\" ]]; then printf '%s\\n' \"$HOME/.local/bin/lifeos\"; exit; fi; "
      + "PATH=\"$PATH:$HOME/.bun/bin:/usr/local/bin\"; bun=\"$(command -v bun)\"; "
      + "if [[ -n \"$bun\" ]]; then printf '%s\\n%s\\n' \"$bun\" \"$dir/cli/src/index.ts\"; fi",
      "lifeos-locate", root.pluginDir]
    stdout: StdioCollector {
      id: locateOut
      waitForEnd: true
    }
    onExited: {
      var parts = String(locateOut.text || "").split("\n").filter(function(p) { return p !== "" })
      root.cliCommand = parts
      root.cliMissing = parts.length === 0
      if (parts.length) root.pump()
    }
  }

  function locateCli() {
    if (!locate.running) locate.running = true
  }

  // Opens a terminal that installs Bun; the widget looks again afterwards.
  function setup() {
    if (root.bar) root.bar.run("omarchy-launch-floating-terminal-with-presentation " + root.setupCommand)
    retryLocate.restart()
  }

  Timer {
    id: retryLocate
    interval: 5000
    repeat: true
    running: root.cliMissing
    onTriggered: root.locateCli()
  }

  property var queue: []

  function run(args) {
    queue = queue.concat([args])
    pump()
  }

  function pump() {
    if (cli.running || queue.length === 0 || root.cliCommand.length === 0) return
    var next = queue[0]
    queue = queue.slice(1)
    // --json leads: anything after the `--` that guards titles is text.
    cli.command = root.cliCommand.concat(["--json"]).concat(next)
    cli.running = true
  }

  // `own` is true for replies to commands this widget ran; only those
  // announce their change (with Undo) — the file watcher sees every change.
  function applyState(text, own) {
    if (!text) return false
    try {
      var parsed = JSON.parse(text)
      if (parsed && parsed.error) {
        root.lastError = String(parsed.error)
        root.errorSerial++
        return true
      }
      if (parsed && parsed.version === 1) {
        // The same snapshot can arrive twice — on stdout and through the
        // file watcher. Only a newer one replaces the model.
        if (!root.state || parsed.generatedAt >= root.state.generatedAt) {
          var wasComplete = root.state ? root.state.summary.dayComplete : null
          var sameDay = root.state ? root.state.today === parsed.today : false
          var before = ({})
          if (root.state && sameDay) for (var i = 0; i < root.state.habits.length; i++) before[root.state.habits[i].id] = root.state.habits[i].milestone
          root.state = parsed
          if (sameDay) for (var j = 0; j < parsed.habits.length; j++) {
            var h = parsed.habits[j]
            if (h.milestone && !before[h.id]) {
              root.milestoneText = "🔥 " + h.milestone + " days of " + h.name
              root.milestoneSerial++
            }
          }
          if (sameDay && wasComplete === false && parsed.summary.dayComplete) root.celebrateSerial++
          root.afterState()
        }
        if (own && parsed.change) {
          root.lastChange = parsed.change.label
          root.changeSerial++
        } else if (own && parsed.undone) {
          root.lastChange = "Undid: " + parsed.undone
          root.changeSerial++
        }
        return true
      }
    } catch (e) {
      return false
    }
    return false
  }

  Process {
    id: cli
    stdout: StdioCollector {
      id: cliOut
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: cliErr
      waitForEnd: true
    }
    onExited: function(code) {
      if (!root.applyState(String(cliOut.text || "").trim(), true) && code !== 0) {
        root.lastError = String(cliErr.text || "Something went wrong").trim().split("\n").pop()
        root.errorSerial++
      }
      Qt.callLater(root.pump)
    }
  }

  FileView {
    path: root.statePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.applyState(text(), false)
  }

  // Every minute: reminders go out (once each), the alert level and the
  // day's phase move on, and midnight turns today into yesterday.
  Timer {
    interval: 60000
    running: true
    repeat: true
    onTriggered: root.run([root.leader ? "tick" : "state"])
  }

  // ---- opening on its own ------------------------------------------------

  // At login the day asks to be planned; in strict mode the evening
  // shutdown and Monday's review insist too. Each opens once per day.
  property string openedPlanOn: ""
  property string openedShutdownOn: ""

  function afterState() {
    if (!root.leader || !root.state || !root.state.day || root.opened) return
    var d = root.state.day
    var today = root.state.today
    if (d.needsPlan && root.openedPlanOn !== today) {
      root.openedPlanOn = today
      Qt.callLater(function() { root.openMode("plan") })
    } else if (root.strict && d.needsShutdown && root.openedShutdownOn !== today) {
      root.openedShutdownOn = today
      Qt.callLater(function() { root.openMode("shutdown") })
    }
  }

  Component.onCompleted: {
    locateCli()
    run(["state"])
  }

  // ---- actions the panel calls -------------------------------------------

  function addTask(title, due) { run(due ? ["task", "add", "--due", due, "--", title] : ["task", "add", "--", title]) }
  function toggleTask(id) { run(["task", "toggle", String(id)]) }
  function setTaskDue(id, due) { run(["task", "due", String(id), due || "none"]) }
  function removeTask(id) { run(["task", "rm", String(id)]) }

  function addHabit(h) {
    var args = ["habit", "add", "--kind", h.kind]
    if (h.kind === "count") args = args.concat(["--target", String(h.target || 1)])
    if (h.unit) args = args.concat(["--unit", h.unit])
    if (h.days) args = args.concat(["--days", h.days])
    if (h.at) args = args.concat(["--at", h.at])
    run(args.concat(["--", h.name]))
  }
  function toggleHabit(id) { run(["habit", "toggle", String(id)]) }
  function stepHabit(id, delta) { run(["habit", delta >= 0 ? "inc" : "dec", String(id), String(Math.abs(delta))]) }
  function moveHabit(id, direction) { run(["habit", direction < 0 ? "up" : "down", String(id)]) }
  function removeHabit(id) { run(["habit", "rm", String(id)]) }

  function addBook(title, pages) { run(["book", "add", "--pages", String(pages), "--", title]) }
  function logPages(id, pages) { run(["book", "log", String(id), String(pages)]) }
  function removeBook(id) { run(["book", "rm", String(id)]) }

  function addEvent(title, day, emoji) {
    var args = ["event", "add", "--on", day]
    if (emoji) args = args.concat(["--emoji", emoji])
    run(args.concat(["--", title]))
  }
  function removeEvent(id) { run(["event", "rm", String(id)]) }

  function refresh() { run(["state"]) }

  function undo() { run(["undo"]) }
  function quick(text) { run(["quick", "--", text]) }
  function renameTask(id, title) { run(["task", "rename", String(id), "--", title]) }
  function focusTask(id, on) { run(on ? ["task", "focus", String(id)] : ["task", "focus", String(id), "--off"]) }
  function dropTask(id) { run(["task", "drop", String(id)]) }
  function planDay() {
    run(["plan", "start"])
    if (root.state && root.state.review && root.state.review.due) run(["review", "seen"])
  }
  function reviewSeen() { run(["review", "seen"]) }
  function shutdownDay() { run(["shutdown"]) }
  function skipHabit(id) { run(["habit", "skip", String(id)]) }
  function unskipHabit(id) { run(["habit", "set", String(id), "0"]) }
  function editHabit(id, h) {
    var args = ["habit", "edit", String(id), "--name", h.name]
    if (h.target) args = args.concat(["--target", String(h.target)])
    if (h.unit !== undefined) args = args.concat(["--unit", h.unit])
    if (h.days) args = args.concat(["--days", h.days])
    args = args.concat(["--at", h.at || "none"])
    run(args)
  }
  function editBook(id, title, pages) { run(["book", "edit", String(id), "--title", title, "--pages", String(pages)]) }
  function editEvent(id, title, day, emoji) { run(["event", "edit", String(id), "--title", title, "--on", day, "--emoji", emoji || ""]) }
  function setSetting(key, value) { run(["set", key, String(value)]) }
  function addPerson(name, born) { run(["person", "add", "--born", born, "--", name]) }
  function editPerson(id, name, born) { run(["person", "edit", String(id), "--name", name, "--born", born]) }
  function removePerson(id) { run(["person", "rm", String(id)]) }
  function checkIn(mood, note) { run(["checkin", String(mood), "--", note || ""]) }

  // Live preview for the quick-add box, off the main queue so typing never
  // waits behind a save.
  property var preview: null
  function parsePreview(text) {
    if (root.cliCommand.length === 0) return
    if (parser.running) { parser.pending = text; return }
    parser.command = root.cliCommand.concat(["--json", "parse", "--", text])
    parser.running = true
  }

  Process {
    id: parser
    property var pending: null
    stdout: StdioCollector { id: parserOut; waitForEnd: true }
    onExited: {
      try { root.preview = JSON.parse(String(parserOut.text || "{}")).parsed || null } catch (e) { root.preview = null }
      if (parser.pending !== null) {
        var next = parser.pending
        parser.pending = null
        root.parsePreview(next)
      }
    }
  }

  // ---- panel plumbing (same contract as the built-in clock) --------------

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }
  function openTab(tab, focusAdd) { if (panelLoader.item) panelLoader.item.openTab(tab, focusAdd) }
  function openMode(mode) { if (panelLoader.item) panelLoader.item.openMode(mode) }

  function cycleLabel() {
    var modes = ["event", "tasks", "habits", "none"]
    var next = modes[(modes.indexOf(labelMode) + 1) % modes.length]
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    entry.label = next
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "staruxian.lifeos"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function refresh(): void { root.refresh() }
    function tab(name: string): void { root.openTab(name, false) }
    function add(name: string): void { root.openTab(name || "tasks", true) }
    function quickadd(): void { if (quickLoader.item) quickLoader.item.toggle() }
    function plan(): void { root.openMode("plan") }
    function shutdown(): void { root.openMode("shutdown") }
    function review(): void { root.openMode("week") }
    function settings(): void { root.openMode("settings") }
  }

  Loader {
    id: quickLoader
    active: root.leader
    source: Qt.resolvedUrl("QuickAdd.qml")
    onLoaded: item.host = root
  }

  // ---- the bar item ------------------------------------------------------

  readonly property real openPanelIndicatorWidth: content.width
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    labelVisible: false
    hasVisualContent: true
    fixedWidth: root.vertical ? -1 : content.width + Style.spaceReal(8.5) * 2
    fixedHeight: root.vertical ? Style.bar.iconSlot + Style.space(8) : -1
    tooltipText: root.tooltip

    onPressed: function(b) {
      if (b === Qt.RightButton) root.cycleLabel()
      else if (b === Qt.MiddleButton) root.openTab("tasks", true)
      else root.togglePanel()
    }

    Row {
      id: content
      anchors.centerIn: parent
      spacing: labelItem.visible ? Style.space(6) : 0

      Ring {
        id: ring
        anchors.verticalCenter: parent.verticalCenter
        size: Math.round(Style.font.body * 1.05)
        lineWidth: Math.max(2, Math.round(size * 0.17))
        value: root.progress
        color: root.progress >= 1 ? Theme.good
          : root.alert === "urgent" ? Theme.danger
          : root.alert === "warn" ? Theme.fire
          : button.foreground
        trackColor: root.alert === "none" ? Theme.alpha(button.foreground, 0.22) : Theme.alpha(color, 0.3)
        Behavior on color { ColorAnimation { duration: Theme.slow } }

        // Late with habits still open: the ring breathes until they are done.
        SequentialAnimation on opacity {
          running: root.alert === "urgent"
          loops: Animation.Infinite
          onRunningChanged: if (!running) ring.opacity = 1
          NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutSine }
          NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
        }

        // The day closes: one proud pulse.
        SequentialAnimation {
          id: celebrate
          NumberAnimation { target: ring; property: "scale"; to: 1.45; duration: 180; easing.type: Easing.OutCubic }
          NumberAnimation { target: ring; property: "scale"; to: 1; duration: 520; easing.type: Easing.OutElastic }
        }
        Connections {
          target: root
          function onCelebrateSerialChanged() { celebrate.restart() }
          function onMilestoneSerialChanged() { celebrate.restart() }
        }
      }

      Text {
        id: labelItem
        anchors.verticalCenter: parent.verticalCenter
        visible: text !== ""
        text: root.labelText
        color: button.foreground
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        renderType: Text.NativeRendering
      }
    }
  }
}
