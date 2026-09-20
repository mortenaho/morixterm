import QtQuick
import QtQuick.Controls

AbstractButton {
    id: control

    property string iconName: ""
    property string iconText: ""
    property string label: ""
    property string tip: label
    property bool active: false
    property bool danger: false

    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    padding: 0
    implicitWidth: 82
    implicitHeight: 58

    ToolTip.visible: control.hovered && control.tip.length > 0
    ToolTip.text: control.tip
    ToolTip.delay: 450

    HoverHandler {
        enabled: control.enabled
        cursorShape: Qt.PointingHandCursor
    }

    contentItem: Item {
        Column {
            anchors.centerIn: parent
            spacing: 5

            Item {
                width: 30
                height: 27
                anchors.horizontalCenter: parent.horizontalCenter

                MVectorIcon {
                    visible: control.iconName.length > 0
                    anchors.centerIn: parent
                    width: 23
                    height: 23
                    name: control.iconName
                    color: !control.enabled ? "#5d6264"
                           : control.danger ? (control.hovered ? "#ff9098" : "#d9727a")
                           : (control.active || control.hovered ? "#5ee3ad" : "#aab2af")
                }

                Text {
                    visible: control.iconName.length === 0
                    anchors.centerIn: parent
                    text: control.iconText
                    color: !control.enabled ? "#5d6264" : (control.danger ? "#ff9098" : "#aab2af")
                    font.pixelSize: 19
                    font.weight: Font.DemiBold
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: control.label
                color: !control.enabled ? "#606567"
                       : (control.hovered || control.active ? "#f4f7f5" : "#a3aaa7")
                font.pixelSize: 10
                font.weight: control.active ? Font.DemiBold : Font.Medium
            }
        }
    }

    background: Rectangle {
        radius: 10
        color: {
            if (!control.enabled) return "transparent"
            if (control.pressed) return control.danger ? "#3a2428" : "#333735"
            if (control.active) return "#263a32"
            if (control.hovered) return control.danger ? "#332326" : "#2f3231"
            return "transparent"
        }
        border.width: control.activeFocus ? 1 : 0
        border.color: control.danger ? "#764048" : "#4ad99f"

        Rectangle {
            visible: control.active && control.enabled
            width: 24
            height: 2
            radius: 1
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 2
            color: "#4fe0a8"
        }
    }
}
