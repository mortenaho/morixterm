import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Dialog {
    id: root

    property int editRow: -1
    signal submitted(var values, int row)
    signal validationError(string message)

    function openForCreate() {
        editRow = -1
        nameField.text = ""
        hostField.text = ""
        userField.text = ""
        protocolBox.currentIndex = 0
        portField.text = "22"
        folderField.text = ""
        open()
        nameField.forceActiveFocus()
    }

    function openForEdit(row, values) {
        editRow = row
        nameField.text = values.name || ""
        hostField.text = values.host || ""
        userField.text = values.username || ""
        protocolBox.currentIndex = values.protocol === "rdp" ? 1 : 0
        portField.text = String(values.port || (protocolBox.currentIndex === 0 ? 22 : 3389))
        folderField.text = values.folder || ""
        open()
        nameField.forceActiveFocus()
    }

    parent: Overlay.overlay
    anchors.centerIn: parent
    width: 520
    modal: true
    focus: true
    title: editRow < 0 ? qsTr("New session") : qsTr("Edit session")
    closePolicy: Popup.CloseOnEscape

    background: Rectangle {
        radius: 12
        color: "#252932"
        border.color: "#3d4350"
    }

    contentItem: ColumnLayout {
        spacing: 14

        GridLayout {
            columns: 2
            columnSpacing: 14
            rowSpacing: 10
            Layout.fillWidth: true

            Label { text: qsTr("Name"); color: "#cbd2dc" }
            TextField {
                id: nameField
                Layout.fillWidth: true
                placeholderText: qsTr("Production server")
            }

            Label { text: qsTr("Protocol"); color: "#cbd2dc" }
            ComboBox {
                id: protocolBox
                Layout.fillWidth: true
                model: ["SSH", "RDP"]
                onCurrentIndexChanged: {
                    const oldDefault = currentIndex === 0 ? "3389" : "22"
                    if (portField.text === "" || portField.text === oldDefault)
                        portField.text = currentIndex === 0 ? "22" : "3389"
                }
            }

            Label { text: qsTr("Host"); color: "#cbd2dc" }
            TextField {
                id: hostField
                Layout.fillWidth: true
                placeholderText: qsTr("server.example.com")
            }

            Label { text: qsTr("Port"); color: "#cbd2dc" }
            TextField {
                id: portField
                Layout.fillWidth: true
                validator: IntValidator { bottom: 1; top: 65535 }
            }

            Label { text: qsTr("Username"); color: "#cbd2dc" }
            TextField {
                id: userField
                Layout.fillWidth: true
                placeholderText: qsTr("Optional")
            }

            Label { text: qsTr("Folder"); color: "#cbd2dc" }
            TextField {
                id: folderField
                Layout.fillWidth: true
                placeholderText: qsTr("Optional group")
            }
        }

        Label {
            Layout.fillWidth: true
            text: qsTr("Passwords are never saved or passed on a process command line. Authentication is handled by your system SSH/RDP client.")
            wrapMode: Text.Wrap
            color: "#8993a3"
            font.pixelSize: 12
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            Item { Layout.fillWidth: true }
            Button { text: qsTr("Cancel"); onClicked: root.close() }
            Button {
                text: editRow < 0 ? qsTr("Create") : qsTr("Save")
                highlighted: true
                onClicked: {
                    const port = Number(portField.text)
                    if (nameField.text.trim() === "" || hostField.text.trim() === "") {
                        root.validationError(qsTr("Name and host are required."))
                        return
                    }
                    if (!Number.isInteger(port) || port < 1 || port > 65535) {
                        root.validationError(qsTr("Port must be between 1 and 65535."))
                        return
                    }
                    root.submitted({
                        name: nameField.text.trim(),
                        host: hostField.text.trim(),
                        port: port,
                        username: userField.text.trim(),
                        protocol: protocolBox.currentIndex === 0 ? "ssh" : "rdp",
                        folder: folderField.text.trim(),
                        color: protocolBox.currentIndex === 0 ? "#e6b422" : "#5b9bd5"
                    }, editRow)
                    root.close()
                }
            }
        }
    }
}
