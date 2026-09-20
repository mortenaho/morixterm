import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Button {
    id: control

    property string shortcutText: ""
    property string iconText: ""
    property bool danger: false

    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    flat: true
    padding: 0
    implicitHeight: 40

    HoverHandler {
        enabled: control.enabled
        cursorShape: Qt.PointingHandCursor
    }

    contentItem: RowLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        spacing: 10

        Text {
            visible: control.iconText.length > 0
            Layout.preferredWidth: 20
            text: control.iconText
            color: control.enabled ? (control.danger ? "#ff8f95" : "#4bdba1") : "#666a6f"
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font.pixelSize: 13
        }

        Text {
            Layout.fillWidth: true
            text: control.text
            color: control.enabled ? (control.danger ? "#ff8f95" : "#e2e4e6") : "#666a6f"
            verticalAlignment: Text.AlignVCenter
            font.pixelSize: 12
            elide: Text.ElideRight
        }

        Text {
            visible: control.shortcutText.length > 0
            text: control.shortcutText
            color: "#85898e"
            font.pixelSize: 10
            verticalAlignment: Text.AlignVCenter
        }
    }

    background: Rectangle {
        radius: 7
        color: control.hovered && control.enabled
               ? (control.danger ? "#3a2225" : "#343b38")
               : "transparent"
        border.width: control.activeFocus ? 1 : 0
        border.color: "#38d996"
    }
}
