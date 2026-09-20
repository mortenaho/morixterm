import QtQuick
import QtQuick.Controls

ToolButton {
    id: control

    property string tip: ""
    property string iconName: ""
    property bool danger: false

    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    padding: 0
    implicitWidth: 38
    implicitHeight: 38

    ToolTip.visible: control.hovered && control.tip.length > 0
    ToolTip.text: control.tip
    ToolTip.delay: 500

    HoverHandler {
        enabled: control.enabled
        cursorShape: Qt.PointingHandCursor
    }

    contentItem: Item {
        MVectorIcon {
            visible: control.iconName.length > 0
            anchors.centerIn: parent
            width: 19
            height: 19
            name: control.iconName
            color: control.enabled
                   ? (control.danger ? "#ff8f95" : "#e0e2e4")
                   : "#666a6f"
        }
        Text {
            visible: control.iconName.length === 0
            anchors.centerIn: parent
            text: control.text
            color: control.enabled
                   ? (control.danger ? "#ff8f95" : "#e0e2e4")
                   : "#666a6f"
            font.pixelSize: 15
            font.weight: Font.Medium
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }

    background: Rectangle {
        radius: 9
        color: {
            if (!control.enabled) return "transparent"
            if (control.pressed) return control.danger ? "#432326" : "#3a3d3f"
            if (control.hovered) return control.danger ? "#342023" : "#343638"
            return "transparent"
        }
        border.width: control.activeFocus ? 2 : ((control.hovered && control.enabled) ? 1 : 0)
        border.color: control.activeFocus ? "#38d996" : (control.danger ? "#6a383d" : "#4a4d50")
    }
}
