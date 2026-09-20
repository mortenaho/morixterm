import QtQuick
import QtQuick.Controls

Button {
    id: control

    property bool primary: false
    property bool danger: false
    property bool compact: false
    property string iconText: ""
    property int minimumWidth: compact ? 72 : 96

    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    padding: 0

    implicitHeight: compact ? 32 : 38
    implicitWidth: Math.max(minimumWidth, buttonContent.implicitWidth + (compact ? 22 : 32))

    HoverHandler {
        enabled: control.enabled
        cursorShape: Qt.PointingHandCursor
    }

    contentItem: Item {
        id: buttonContent
        implicitWidth: contentRow.implicitWidth
        implicitHeight: contentRow.implicitHeight

        Row {
            id: contentRow
            anchors.centerIn: parent
            spacing: control.iconText.length > 0 ? 7 : 0

            Text {
                visible: control.iconText.length > 0
                text: control.iconText
                color: control.enabled
                       ? (control.primary ? "#111315" : (control.danger ? "#ffadad" : "#e3e5e7"))
                       : "#676b70"
                font.pixelSize: control.compact ? 12 : 13
                font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            Text {
                text: control.text
                color: control.enabled
                       ? (control.primary ? "#111315" : (control.danger ? "#ffadad" : "#e3e5e7"))
                       : "#676b70"
                font.pixelSize: control.compact ? 10 : 11
                font.weight: control.primary ? Font.DemiBold : Font.Medium
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }
    }

    background: Rectangle {
        radius: control.compact ? 8 : 9
        color: {
            if (!control.enabled) return "#242628"
            if (control.pressed) return control.primary ? "#2e9f76" : (control.danger ? "#482326" : "#3a3c3f")
            if (control.hovered) return control.primary ? "#49d7a0" : (control.danger ? "#3b2225" : "#343639")
            return control.primary ? "#38d996" : (control.danger ? "#2c1e20" : "#2b2d2f")
        }
        border.width: control.activeFocus ? 2 : 1
        border.color: {
            if (control.activeFocus) return control.primary ? "#8af1c2" : "#38d996"
            if (control.primary) return "#38d996"
            if (control.danger) return "#6a383d"
            return control.hovered ? "#4a4d50" : "#404347"
        }
    }

    Keys.onReturnPressed: function(event) {
        if (control.enabled) control.clicked()
        event.accepted = true
    }
    Keys.onEnterPressed: function(event) {
        if (control.enabled) control.clicked()
        event.accepted = true
    }
}
