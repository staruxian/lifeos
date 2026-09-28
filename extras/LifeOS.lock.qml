// LifeOS lock screen design for Lock Screen Explorer
// (https://github.com/SirJul1337/omarchy-lock-explorer).
// The Classic design, plus the time and a small card with today's
// priorities, habits left and the next countdown, read from the LifeOS
// snapshot. It only reads that file; the lock itself is untouched.
// install.sh copies it to ~/.config/omarchy/lock-designs/LifeOS.qml; pick it
// with `omarchy-shell lock explore` (Custom).
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "../plugins/io.github.sirjul1337.lock-explorer/designs"

DesignBase {
  id: lock
  inputItem: field.input

  property var life: null
  readonly property string todayKey: Qt.formatDate(lock.now, "yyyy-MM-dd")
  // A snapshot from another day is stale; show nothing rather than yesterday.
  readonly property bool fresh: life !== null && life.today === todayKey
  readonly property var priorities: fresh && life.day ? life.day.priorities : []
  readonly property int habitsLeft: fresh && life.day ? life.day.habitsLeft.length : 0
  readonly property var next: fresh ? life.summary.nextEvent : null

  FileView {
    path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/lifeos/state.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try { lock.life = JSON.parse(text()) } catch (e) { lock.life = null }
    }
  }

  Wallpaper { anchors.fill: parent; lock: lock; blur: 1.0; dim: 0.1; contrast: -0.08; vignette: false }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    onClicked: { lock.wakeRequested(); lock.forcePasswordFocus() }
    onPositionChanged: lock.wakeRequested()
  }

  Column {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: field.top
    anchors.bottomMargin: 36
    spacing: 2

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: Qt.formatTime(lock.now, "HH:mm")
      color: Color.lock.text
      font.family: Style.font.family
      font.pixelSize: 88
      font.weight: Font.Light
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: Qt.formatDate(lock.now, "dddd, MMMM d")
      color: Color.lock.placeholder
      font.family: Style.font.family
      font.pixelSize: 18
    }
  }

  PasswordField {
    id: field
    lock: lock
    anchors.centerIn: parent
    width: 381
    height: 67
    radius: Style.cornerRadius
    outlineThickness: 3
    showLockGlyph: false
    shakeOnFail: false
    placeholder: "Enter Password"
    fontScale: 1.125
  }

  // Today, at a glance.
  Rectangle {
    visible: lock.fresh && (lock.priorities.length > 0 || lock.habitsLeft > 0 || lock.next !== null)
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: field.bottom
    anchors.topMargin: 28
    width: 381
    height: today.implicitHeight + 32
    radius: 18
    color: Qt.rgba(0, 0, 0, 0.38)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.08)

    Column {
      id: today
      x: 20
      y: 16
      width: parent.width - 40
      spacing: 8

      Text {
        visible: lock.priorities.length > 0
        text: "TODAY"
        color: Qt.rgba(1, 1, 1, 0.5)
        font.family: Style.font.family
        font.pixelSize: 11
        font.letterSpacing: 1.4
        font.bold: true
      }

      Repeater {
        model: lock.priorities
        Row {
          required property var modelData
          spacing: 10
          Text { text: modelData.done ? "✓" : "★"; color: modelData.done ? "#30d158" : "#ff9f0a"; font.pixelSize: 14; anchors.verticalCenter: parent.verticalCenter }
          Text {
            width: 381 - 40 - 24
            text: modelData.title
            color: modelData.done ? Qt.rgba(1, 1, 1, 0.45) : "white"
            font.family: Style.font.family
            font.pixelSize: 15
            font.strikeout: modelData.done
            elide: Text.ElideRight
          }
        }
      }

      Text {
        width: parent.width
        visible: lock.habitsLeft > 0 || lock.next !== null
        topPadding: lock.priorities.length > 0 ? 4 : 0
        text: {
          var parts = []
          if (lock.habitsLeft > 0) parts.push(lock.habitsLeft + (lock.habitsLeft === 1 ? " habit left" : " habits left"))
          if (lock.next) parts.push((lock.next.emoji ? lock.next.emoji + " " : "") + lock.next.title + (lock.next.daysLeft === 0 ? " today" : " in " + lock.next.daysLeft + (lock.next.daysLeft === 1 ? " day" : " days")))
          return parts.join("   ·   ")
        }
        color: Qt.rgba(1, 1, 1, 0.7)
        font.family: Style.font.family
        font.pixelSize: 13
        elide: Text.ElideRight
      }
    }
  }
}
