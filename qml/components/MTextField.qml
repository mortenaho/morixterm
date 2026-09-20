import QtQuick
import QtQuick.Controls

TextField {
    id: control
    implicitHeight: 44
    color: "#e3e5e7"
    placeholderTextColor: "#777b80"
    selectionColor: "#315a4b"
    selectedTextColor: "#ffffff"
    font.pixelSize: 13
    leftPadding: 14
    rightPadding: 14
    selectByMouse: true
    background: Rectangle {
        radius: 10
        color: control.enabled ? "#202224" : "#252729"
        border.color: control.activeFocus ? "#38d996" : (control.hovered ? "#4d5054" : "#3b3e41")
        border.width: control.activeFocus ? 1.5 : 1
    }
}
