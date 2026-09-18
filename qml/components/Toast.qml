import QtQuick
import QtQuick.Controls

Rectangle {
    id: root

    property string message: ""
    property string kind: "info"

    function show(text, messageKind) {
        message = text
        kind = messageKind || "info"
        visible = true
        opacity = 1
        hideTimer.restart()
    }

    width: Math.min(parent ? parent.width - 32 : 440, 440)
    height: toastText.implicitHeight + 28
    radius: 9
    color: kind === "error" ? "#5a2222"
          : kind === "success" ? "#1f4d3a"
          : kind === "warning" ? "#5a4520" : "#2a3b4d"
    border.width: 1
    border.color: kind === "error" ? "#ff6b6b"
                : kind === "success" ? "#4caf7a"
                : kind === "warning" ? "#e6b422" : "#5b9bd5"
    opacity: 0
    visible: false
    z: 1000

    Behavior on opacity { NumberAnimation { duration: 160 } }

    Row {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 10

        Label {
            text: root.kind === "error" ? "●" : root.kind === "success" ? "✓" : "●"
            color: root.border.color
            font.bold: true
        }
        Label {
            id: toastText
            width: parent.width - 54
            text: root.message
            color: "white"
            wrapMode: Text.Wrap
        }
        ToolButton {
            text: "×"
            onClicked: root.close()
        }
    }

    function close() {
        opacity = 0
        closeTimer.restart()
    }

    Timer {
        id: hideTimer
        interval: root.kind === "error" ? 4500 : 3200
        onTriggered: root.close()
    }
    Timer {
        id: closeTimer
        interval: 180
        onTriggered: root.visible = false
    }
}
