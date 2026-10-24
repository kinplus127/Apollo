import Quickshell
import Quickshell.Services.Notifications
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

  NotificationServer {
    id: notifServer
    bodySupported: true
    // Plain text only, so body markup is not interpreted.
    bodyMarkupSupported: false

    onNotification: function (notification) {
      notification.tracked = true
    }
  }

  PanelWindow {
    anchors.top: true
    anchors.right: true
    implicitWidth: 380
    implicitHeight: toastColumn.implicitHeight
    exclusiveZone: 0
    color: "transparent"
    visible: toastRepeater.count > 0
    margins.top: 40
    margins.right: 8

    Column {
      id: toastColumn
      width: parent.width
      spacing: 8

      Repeater {
        id: toastRepeater
        model: notifServer.trackedNotifications

        delegate: Rectangle {
          required property var modelData
          width: toastColumn.width
          radius: 8
          color: "#2a2a2a"
          implicitHeight: toastText.implicitHeight + 16

          Column {
            id: toastText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 8
            spacing: 4

            Text {
              width: parent.width
              color: "#f2f2f2"
              text: modelData.summary
              font.pixelSize: 13
              font.bold: true
              wrapMode: Text.Wrap
              textFormat: Text.PlainText
            }

            Text {
              width: parent.width
              color: "#c8c8c8"
              text: modelData.body
              font.pixelSize: 12
              wrapMode: Text.Wrap
              textFormat: Text.PlainText
              visible: text.length > 0
            }
          }

          // expireTimeout is seconds. 0 means the server default; -1 stays until dismissed.
          Timer {
            interval: modelData.expireTimeout > 0 ? Math.round(modelData.expireTimeout * 1000) : 5000
            running: modelData.expireTimeout >= 0
            onTriggered: modelData.expire()
          }

          MouseArea {
            anchors.fill: parent
            onClicked: modelData.dismiss()
          }
        }
      }
    }
  }
}
