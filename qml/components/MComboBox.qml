import QtQuick
import QtQuick.Controls

ComboBox {
    id: control
    implicitHeight: 44
    leftPadding: 14
    rightPadding: 34
    font.pixelSize: 13

    contentItem: Text {
        leftPadding: 1
        text: control.displayText
        color: "#e3e5e7"
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    background: Rectangle {
        radius: 10
        color: "#202224"
        border.color: control.activeFocus ? "#38d996" : (control.hovered ? "#4d5054" : "#3b3e41")
    }
    indicator: Text {
        x: control.width - width - 12
        anchors.verticalCenter: parent.verticalCenter
        text: "⌄"
        color: "#8b8f94"
        font.pixelSize: 16
    }
    popup: Popup {
        y: control.height + 4
        width: control.width
        implicitHeight: Math.min(contentItem.implicitHeight + 12, 280)
        padding: 6
        background: Rectangle {
            radius: 10
            color: "#2a2c2e"
            border.color: "#45484c"
        }
        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: control.popup.visible ? control.delegateModel : null
            currentIndex: control.highlightedIndex
        }
    }
    delegate: ItemDelegate {
        width: control.width - 12
        height: 36
        contentItem: Text {
            text: control.textRole.length > 0 ? modelData[control.textRole] : modelData
            color: highlighted ? "#55e0aa" : "#e3e5e7"
            verticalAlignment: Text.AlignVCenter
            leftPadding: 8
            font.pixelSize: 13
        }
        background: Rectangle {
            radius: 7
            color: highlighted ? "#333d39" : "transparent"
        }
    }
}
