import QtQuick
import QtQuick.Controls

CheckBox {
    id: control
    spacing: 8
    indicator: Rectangle {
        implicitWidth: 19
        implicitHeight: 19
        x: control.leftPadding
        y: parent.height / 2 - height / 2
        radius: 5
        color: control.checked ? "#38d996" : "#202224"
        border.color: control.checked ? "#38d996" : "#4d5054"
        Text {
            anchors.centerIn: parent
            visible: control.checked
            text: "✓"
            color: "#111315"
            font.pixelSize: 12
            font.bold: true
        }
    }
    HoverHandler {
        enabled: control.enabled
        cursorShape: Qt.PointingHandCursor
    }

    contentItem: Text {
        text: control.text
        color: control.enabled ? "#e3e5e7" : "#777b80"
        leftPadding: control.indicator.width + control.spacing
        verticalAlignment: Text.AlignVCenter
        font.pixelSize: 13
        wrapMode: Text.WordWrap
    }
}
