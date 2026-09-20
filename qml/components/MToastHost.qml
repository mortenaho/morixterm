import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root

    property string message: ""
    property string kind: "info" // info | success | warning | error
    property bool shown: false

    enabled: shown

    function show(text, type) {
        var normalized = String(text || "").trim()
        if (normalized.length === 0)
            return
        message = normalized
        kind = type || "info"
        shown = true
        hideTimer.restart()
    }

    function dismiss() {
        hideTimer.stop()
        shown = false
    }

    function copyMessage() {
        clipboardProxy.text = root.message
        clipboardProxy.selectAll()
        clipboardProxy.copy()
    }

    TextEdit {
        id: clipboardProxy
        visible: false
        width: 1
        height: 1
    }

    Timer {
        id: hideTimer
        interval: root.kind === "error" ? 10000 : 5000
        repeat: false
        onTriggered: root.shown = false
    }

    Rectangle {
        id: card
        width: Math.min(620, Math.max(360, content.implicitWidth + 42))
        implicitHeight: Math.max(68, content.implicitHeight + 24)
        height: implicitHeight
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.shown ? 24 : -height - 16
        opacity: root.shown ? 1 : 0
        radius: 14
        color: root.kind === "error" ? "#2a1115"
             : root.kind === "warning" ? "#2b2412"
             : root.kind === "success" ? "#0f2c20"
             : "#0e2119"
        border.width: 2
        border.color: root.kind === "error" ? "#ff6f78"
                      : root.kind === "warning" ? "#e7bd55"
                      : root.kind === "success" ? "#55e99a"
                      : "#4fcf91"

        Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 150 } }

        Rectangle {
            width: 5
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: 7
            radius: 3
            color: card.border.color
        }

        RowLayout {
            id: content
            anchors.fill: parent
            anchors.leftMargin: 20
            anchors.rightMargin: 10
            anchors.topMargin: 11
            anchors.bottomMargin: 11
            spacing: 11

            Rectangle {
                Layout.preferredWidth: 30
                Layout.preferredHeight: 30
                radius: 9
                color: root.kind === "error" ? "#4a1c21"
                       : root.kind === "warning" ? "#403416"
                       : root.kind === "success" ? "#16462f"
                       : "#17372a"
                Text {
                    anchors.centerIn: parent
                    text: root.kind === "error" ? "!"
                          : root.kind === "warning" ? "!"
                          : root.kind === "success" ? "✓" : "i"
                    color: root.kind === "error" ? "#ffabb0"
                           : root.kind === "warning" ? "#f5d277"
                           : "#76f7b2"
                    font.pixelSize: 15
                    font.bold: true
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3
                Text {
                    text: root.kind === "error" ? "Operation failed"
                          : root.kind === "warning" ? "Attention"
                          : root.kind === "success" ? "Done" : "MoriXterm"
                    color: "#f0f8f3"
                    font.pixelSize: 12
                    font.bold: true
                }
                Text {
                    Layout.fillWidth: true
                    text: root.message
                    color: "#c0d3c8"
                    font.pixelSize: 10
                    wrapMode: Text.Wrap
                    maximumLineCount: 5
                    elide: Text.ElideRight
                }
            }

            Rectangle {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                radius: 8
                color: copyHover.hovered ? "#244437" : "transparent"
                border.color: copyHover.hovered ? "#456c59" : "transparent"
                Text { anchors.centerIn: parent; text: "⧉"; color: "#d9e8df"; font.pixelSize: 14 }
                HoverHandler { id: copyHover }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.copyMessage()
                    ToolTip.visible: containsMouse
                    ToolTip.text: "Copy message"
                }
            }

            Rectangle {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                radius: 8
                color: closeHover.hovered ? "#3c2023" : "transparent"
                border.color: closeHover.hovered ? "#714148" : "transparent"
                Text { anchors.centerIn: parent; text: "×"; color: "#f2dddd"; font.pixelSize: 17 }
                HoverHandler { id: closeHover }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.dismiss()
                    ToolTip.visible: containsMouse
                    ToolTip.text: "Close"
                }
            }
        }
    }
}
