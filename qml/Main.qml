import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "components"

ApplicationWindow {
    id: window

    width: 1240
    height: 780
    minimumWidth: 900
    minimumHeight: 600
    visible: true
    title: "MoriXterm"
    color: "#171a20"

    palette.window: "#1e222a"
    palette.windowText: "#edf1f7"
    palette.base: "#171a20"
    palette.alternateBase: "#242932"
    palette.text: "#edf1f7"
    palette.button: "#303641"
    palette.buttonText: "#edf1f7"
    palette.highlight: "#3d9970"
    palette.highlightedText: "#ffffff"

    header: ToolBar {
        height: 52
        background: Rectangle {
            color: "#252932"
            border.color: "#343a46"
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 10

            Rectangle {
                width: 30
                height: 30
                radius: 8
                color: "#3d9970"
                Label {
                    anchors.centerIn: parent
                    text: ">_"
                    color: "white"
                    font.bold: true
                    font.pixelSize: 13
                }
            }
            Label {
                text: "MoriXterm"
                font.pixelSize: 17
                font.bold: true
            }
            Label {
                text: "Qt / QML"
                color: "#7e8999"
                font.pixelSize: 11
            }
            Item { Layout.fillWidth: true }
            Label {
                text: connectionManager.statusText
                color: connectionManager.active ? "#63c18d" : "#8993a3"
            }
            Button {
                text: qsTr("＋ New session")
                highlighted: true
                onClicked: sessionDialog.openForCreate()
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.preferredWidth: 286
            Layout.fillHeight: true
            color: "#20242c"
            border.color: "#343a46"

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10

                Label {
                    text: qsTr("SAVED SESSIONS")
                    color: "#7e8999"
                    font.pixelSize: 11
                    font.bold: true
                    font.letterSpacing: 0.8
                }
                TextField {
                    Layout.fillWidth: true
                    placeholderText: qsTr("⌕  Search sessions")
                    onTextChanged: sessionModel.searchText = text
                }
                ListView {
                    id: sessionsList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 7
                    model: sessionModel

                    Label {
                        anchors.centerIn: parent
                        visible: sessionModel.count === 0
                        text: sessionModel.searchText === ""
                              ? qsTr("No saved sessions yet") : qsTr("No matching sessions")
                        color: "#697383"
                    }

                    delegate: Rectangle {
                        id: sessionCard
                        required property int index
                        required property string name
                        required property string host
                        required property int port
                        required property string username
                        required property string protocol
                        required property string folder
                        required property string accentColor

                        width: ListView.view.width
                        height: 78
                        radius: 9
                        color: cardMouse.containsMouse ? "#303641" : "#292e37"
                        border.color: "#3a414d"

                        Rectangle {
                            width: 4
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            radius: 4
                            color: sessionCard.accentColor
                        }

                        MouseArea {
                            id: cardMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onDoubleClicked: connectionManager.connectSession(sessionModel.get(sessionCard.index))
                        }

                        Column {
                            anchors.left: parent.left
                            anchors.leftMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - actions.width - 26
                            spacing: 5
                            Label {
                                width: parent.width
                                text: sessionCard.name
                                elide: Text.ElideRight
                                font.bold: true
                            }
                            Label {
                                width: parent.width
                                text: sessionCard.protocol.toUpperCase() + "  ·  " + sessionCard.host + ":" + sessionCard.port
                                color: "#929cab"
                                elide: Text.ElideMiddle
                                font.pixelSize: 11
                            }
                            Label {
                                visible: sessionCard.folder !== ""
                                text: "▸ " + sessionCard.folder
                                color: "#697383"
                                font.pixelSize: 10
                            }
                        }

                        Row {
                            id: actions
                            anchors.right: parent.right
                            anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1
                            ToolButton {
                                text: "▶"
                                ToolTip.visible: hovered
                                ToolTip.text: qsTr("Connect")
                                onClicked: connectionManager.connectSession(sessionModel.get(sessionCard.index))
                            }
                            ToolButton {
                                text: "✎"
                                ToolTip.visible: hovered
                                ToolTip.text: qsTr("Edit")
                                onClicked: sessionDialog.openForEdit(sessionCard.index, sessionModel.get(sessionCard.index))
                            }
                            ToolButton {
                                text: "×"
                                ToolTip.visible: hovered
                                ToolTip.text: qsTr("Delete")
                                onClicked: {
                                    window.pendingDeleteRow = sessionCard.index
                                    window.pendingDeleteName = sessionCard.name
                                    deleteDialog.open()
                                }
                            }
                        }
                    }
                }
            }
        }

        StackLayout {
            id: workspace
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: connectionManager.active || connectionManager.output.length > 0 ? 1 : 0

            Rectangle {
                color: "#111419"
                ColumnLayout {
                    anchors.centerIn: parent
                    width: Math.min(parent.width - 80, 650)
                    spacing: 18

                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        width: 74
                        height: 74
                        radius: 20
                        color: "#3d9970"
                        Label {
                            anchors.centerIn: parent
                            text: ">_"
                            color: "white"
                            font.pixelSize: 27
                            font.bold: true
                        }
                    }
                    Label {
                        Layout.alignment: Qt.AlignHCenter
                        text: qsTr("Remote sessions, made elegant.")
                        color: "white"
                        font.pixelSize: 30
                        font.bold: true
                    }
                    Label {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: qsTr("Manage SSH shells and RDP desktops from one focused Qt workspace.")
                        color: "#929cab"
                        wrapMode: Text.Wrap
                        font.pixelSize: 15
                    }
                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 10
                        Button {
                            text: qsTr("＋ Create your first session")
                            highlighted: true
                            onClicked: sessionDialog.openForCreate()
                        }
                        Label { text: "SSH"; color: "#e6b422" }
                        Label { text: "RDP"; color: "#5b9bd5" }
                    }
                }
            }

            Rectangle {
                color: "#0c0f13"
                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 46
                        color: "#20242c"
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 8
                            Label {
                                text: connectionManager.title || qsTr("Session")
                                font.bold: true
                            }
                            Label { text: connectionManager.statusText; color: "#8993a3" }
                            Item { Layout.fillWidth: true }
                            ToolButton { text: qsTr("Clear"); onClicked: connectionManager.clearOutput() }
                            Button {
                                text: qsTr("Disconnect")
                                enabled: connectionManager.active
                                onClicked: connectionManager.disconnectSession()
                            }
                        }
                    }

                    ScrollView {
                        id: terminalScroll
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        TextArea {
                            id: terminalOutput
                            text: connectionManager.output
                            readOnly: true
                            selectByMouse: true
                            color: "#d8dee9"
                            selectionColor: "#3d9970"
                            font.family: "monospace"
                            font.pixelSize: 13
                            wrapMode: TextEdit.WrapAnywhere
                            background: Rectangle { color: "#0c0f13" }
                            onTextChanged: cursorPosition = length
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 52
                        color: "#171b21"
                        border.color: "#303641"
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            Label { text: "❯"; color: "#e6b422"; font.bold: true }
                            TextField {
                                id: commandInput
                                Layout.fillWidth: true
                                enabled: connectionManager.active
                                placeholderText: connectionManager.active ? qsTr("Type a command…") : qsTr("Session is not interactive")
                                onAccepted: {
                                    if (text !== "") {
                                        connectionManager.sendInput(text)
                                        text = ""
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    property int pendingDeleteRow: -1
    property string pendingDeleteName: ""

    SessionDialog {
        id: sessionDialog
        onValidationError: message => toast.show(message, "warning")
        onSubmitted: (values, row) => {
            const ok = row < 0 ? sessionModel.addSession(values) : sessionModel.updateSession(row, values)
            toast.show(ok ? (row < 0 ? qsTr("Session created.") : qsTr("Session updated."))
                          : qsTr("The session could not be saved."), ok ? "success" : "error")
        }
    }

    Dialog {
        id: deleteDialog
        parent: Overlay.overlay
        anchors.centerIn: parent
        modal: true
        title: qsTr("Delete session?")
        standardButtons: Dialog.Yes | Dialog.No
        Label {
            text: qsTr("Remove “%1” from saved sessions?").arg(window.pendingDeleteName)
            color: "#edf1f7"
        }
        onAccepted: {
            const ok = sessionModel.removeSession(window.pendingDeleteRow)
            toast.show(ok ? qsTr("Session deleted.") : qsTr("The session could not be deleted."), ok ? "success" : "error")
            window.pendingDeleteRow = -1
        }
    }

    Toast {
        id: toast
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 22
    }

    Connections {
        target: connectionManager
        function onUserError(message) { toast.show(message, "error") }
        function onUserNotice(message) { toast.show(message, "success") }
    }
    Connections {
        target: sessionModel
        function onPersistenceError(message) { toast.show(message, "error") }
    }
}
