import Quickshell
import QtQuick

ShellRoot {
  PanelWindow {
    anchors {
      top: true
      left: true
      right: true
    }
    height: 32
    exclusiveZone: 32
    color: "#1a1a1a"

    Text {
      anchors.centerIn: parent
      color: "#e0e0e0"
      text: "Apollo · edit ~/.config/quickshell/apollo/shell.qml"
      font.pixelSize: 12
    }
  }
}
