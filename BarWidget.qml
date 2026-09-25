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
  readonly property var summary: state ? state.summary : null
  readonly property real progress: Model.dayProgress(summary)

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

  function applyState(text) {
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
        if (!root.state || parsed.generatedAt >= root.state.generatedAt) root.state = parsed
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
      if (!root.applyState(String(cliOut.text || "").trim()) && code !== 0) {
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
    onLoaded: root.applyState(text())
  }

  // Midnight turns today into yesterday; ask for a fresh snapshot.
  Timer {
    interval: 60000
    running: true
    repeat: true
    onTriggered: {
      var now = new Date()
      var today = now.getFullYear() + "-" + String(now.getMonth() + 1).padStart(2, "0") + "-" + String(now.getDate()).padStart(2, "0")
      if (!root.state || root.state.today !== today) root.run(["state"])
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

  // ---- panel plumbing (same contract as the built-in clock) --------------

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }
  function openTab(tab, focusAdd) { if (panelLoader.item) panelLoader.item.openTab(tab, focusAdd) }

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
        color: root.progress >= 1 ? Theme.good : button.foreground
        trackColor: Theme.alpha(button.foreground, 0.22)
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
