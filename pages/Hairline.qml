import QtQuick
import "../components"

Rectangle {
  property int inset: 0
  x: inset
  width: (parent ? parent.width : 0) - inset
  height: 1
  color: Theme.separator
}
