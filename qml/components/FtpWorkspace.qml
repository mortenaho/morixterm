import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import MoriXterm.FileManager 1.0
import MoriXterm.Ftp 1.0
import "." as UI

Item {
    id: root

    property string protocol: "sftp"
    property string host: ""
    property string user: ""
    property int port: protocol === "ftp" ? 21 : 22
    property string password: ""
    property string keyFile: ""
    property bool ftpTls: true
    property bool ignoreCertificate: false
    property bool ftpPassive: true
    property int maxParallel: 4
    property bool overwriteExisting: true

    property color bg: "#1e1f20"
    property color panel: "#222325"
    property color panel2: "#292a2c"
    property color panel3: "#303134"
    property color border: "#3a3c3f"
    property color textColor: "#e2e4e6"
    property color muted: "#8b8f94"
    property color accent: "#38d996"
    property color accentSoft: "#2b3a34"
    property color danger: "#ff7078"
    property color warning: "#e3b85c"

    property var localSelection: []
    property var remoteSelection: []
    property int localAnchor: -1
    property int remoteAnchor: -1

    signal credentialsConsumed()
    signal notificationRequested(string message, string type)
    signal persistentCertificateTrustRequested()

    FileManagerController { id: localFiles }
    FtpClientController { id: remoteFiles }

    Connections {
        target: localFiles
        function onOperationFinished(success, message) {
            if (!success && message && message.length)
                root.notificationRequested(message, "error")
        }
    }

    Connections {
        target: remoteFiles
        function onOperationFinished(success, message) {
            if (!success && message && message.length)
                root.notificationRequested(message, "error")
        }
        function onTlsCertificateError(message) {
            tlsCertificateMessage.text = message
            ftpCertificateDialog.open()
        }
    }


    function openAdaptiveContextPopup(popup, sourceItem, localX, localY) {
        if (!popup || !sourceItem || !Overlay.overlay) return

        var overlay = Overlay.overlay
        var point = sourceItem.mapToItem(overlay, localX, localY)
        var margin = 12
        var gap = 7
        var popupWidth = Math.max(1, popup.width > 0 ? popup.width : popup.implicitWidth)
        var contentHeight = popup.contentItem ? popup.contentItem.implicitHeight : 0
        var popupHeight = Math.max(1, popup.implicitHeight, contentHeight + popup.topPadding + popup.bottomPadding)

        var x = point.x
        if (x + popupWidth > overlay.width - margin)
            x = overlay.width - popupWidth - margin
        x = Math.max(margin, x)

        var y = point.y + gap
        if (y + popupHeight > overlay.height - margin)
            y = point.y - popupHeight - gap
        y = Math.max(margin, Math.min(y, overlay.height - popupHeight - margin))

        popup.x = x
        popup.y = y
        popup.open()
    }

    function fileIconSource(name, directory) {
        if (directory) return "qrc:/assets/icons/folder.svg"
        var lower = String(name || "").toLowerCase()
        if (lower.endsWith(".zip") || lower.endsWith(".7z") || lower.endsWith(".rar") ||
            lower.endsWith(".tar") || lower.endsWith(".tgz") || lower.endsWith(".gz") ||
            lower.endsWith(".bz2") || lower.endsWith(".xz"))
            return "qrc:/assets/icons/archive.svg"
        return "qrc:/assets/icons/file.svg"
    }

    function containsRow(list, row) {
        for (var i = 0; i < list.length; ++i)
            if (Number(list[i]) === Number(row)) return true
        return false
    }

    function selectRow(side, row, modifiers) {
        var current = side === "local" ? localSelection.slice(0) : remoteSelection.slice(0)
        var anchor = side === "local" ? localAnchor : remoteAnchor
        if ((modifiers & Qt.ShiftModifier) && anchor >= 0) {
            current = []
            var start = Math.min(anchor, row)
            var end = Math.max(anchor, row)
            for (var i = start; i <= end; ++i) current.push(i)
        } else if (modifiers & Qt.ControlModifier) {
            var found = -1
            for (var j = 0; j < current.length; ++j) {
                if (Number(current[j]) === Number(row)) { found = j; break }
            }
            if (found >= 0) current.splice(found, 1)
            else current.push(row)
            if (side === "local") localAnchor = row
            else remoteAnchor = row
        } else {
            current = [row]
            if (side === "local") localAnchor = row
            else remoteAnchor = row
        }
        if (side === "local") localSelection = current
        else remoteSelection = current
    }

    function selectedLocalPaths() {
        var paths = []
        for (var i = 0; i < localSelection.length; ++i) {
            var p = localFiles.entryPath(Number(localSelection[i]))
            if (p.length) paths.push(p)
        }
        return paths
    }

    function firstRemoteRow() {
        return remoteSelection.length ? Number(remoteSelection[0]) : -1
    }

    function uploadSelected() {
        var paths = selectedLocalPaths()
        if (paths.length === 0) return
        remoteFiles.uploadPaths(paths, overwriteBox.checked)
    }

    function downloadSelected() {
        if (remoteSelection.length === 0) return
        downloadFolderDialog.open()
    }

    Component.onCompleted: {
        localFiles.configureLocal()
        remoteFiles.configure(protocol, host, user, port, password, keyFile,
                              ftpTls, ftpPassive, maxParallel, overwriteExisting, ignoreCertificate)
        credentialsConsumed()
    }

    Dialog {
        id: ftpCertificateDialog
        modal: true
        anchors.centerIn: parent
        width: Math.min(620, Math.max(420, root.width - 80))
        padding: 20
        standardButtons: Dialog.NoButton
        closePolicy: Popup.CloseOnEscape
        background: Rectangle { radius: 16; color: root.panel2; border.color: root.warning; border.width: 1 }
        contentItem: ColumnLayout {
            spacing: 14
            RowLayout {
                Layout.fillWidth: true
                Rectangle {
                    width: 40; height: 40; radius: 12; color: "#3a2d12"; border.color: "#7c6327"
                    Label { anchors.centerIn: parent; text: "!"; color: root.warning; font.pixelSize: 20; font.bold: true }
                }
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 2
                    Label { text: "FTPS certificate warning"; color: root.textColor; font.pixelSize: 18; font.bold: true }
                    Label { text: root.host + ":" + root.port; color: root.muted; font.pixelSize: 10 }
                }
            }
            Label {
                Layout.fillWidth: true
                text: "The server certificate could not be verified. If this is a server you trust (for example, FileZilla previously accepted its certificate), you can continue for this run or save an exception for this connection profile."
                color: root.textColor
                wrapMode: Text.WordWrap
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(150, Math.max(78, tlsCertificateMessage.implicitHeight + 18))
                radius: 10
                color: "#1f2123"
                border.color: root.border
                Flickable {
                    anchors.fill: parent; anchors.margins: 9; clip: true
                    contentWidth: width; contentHeight: tlsCertificateMessage.implicitHeight
                    Text {
                        id: tlsCertificateMessage
                        width: parent.width
                        color: root.muted
                        font.pixelSize: 10
                        font.family: "monospace"
                        wrapMode: Text.WrapAnywhere
                        textFormat: Text.PlainText
                    }
                }
            }
            Label {
                Layout.fillWidth: true
                text: "Security note: continuing bypasses CA/hostname verification for this FTPS connection. Prefer fixing the certificate on the server when possible."
                color: root.warning
                font.pixelSize: 10
                wrapMode: Text.WordWrap
            }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                UI.MButton { text: "Cancel"; compact: true; onClicked: ftpCertificateDialog.close() }
                UI.MButton {
                    text: "Trust once"
                    compact: true
                    onClicked: {
                        ftpCertificateDialog.close()
                        remoteFiles.trustTlsForCurrentSession()
                    }
                }
                UI.MButton {
                    text: "Allow for this profile"
                    primary: true
                    compact: true
                    onClicked: {
                        ftpCertificateDialog.close()
                        remoteFiles.trustTlsForCurrentSession()
                        root.persistentCertificateTrustRequested()
                    }
                }
            }
        }
    }

    FolderDialog {
        id: downloadFolderDialog
        title: "Choose local download folder"
        onAccepted: remoteFiles.downloadRows(root.remoteSelection, selectedFolder, overwriteBox.checked)
    }

    Dialog {
        id: remoteFolderDialog
        modal: true
        anchors.centerIn: parent
        width: 420
        padding: 20
        standardButtons: Dialog.NoButton
        background: Rectangle { radius: 16; color: root.panel2; border.color: root.border }
        contentItem: ColumnLayout {
            spacing: 14
            Label { text: "New remote folder"; color: root.textColor; font.pixelSize: 18; font.bold: true }
            Label { text: "Create in " + remoteFiles.currentPath; color: root.muted; font.pixelSize: 10; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            UI.MTextField { id: remoteFolderName; Layout.fillWidth: true; placeholderText: "Folder name"; onAccepted: remoteFolderCreate.clicked() }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                UI.MButton { text: "Cancel"; compact: true; onClicked: remoteFolderDialog.close() }
                UI.MButton {
                    id: remoteFolderCreate
                    text: "Create"
                    primary: true
                    compact: true
                    onClicked: {
                        remoteFiles.createFolder(remoteFolderName.text)
                        remoteFolderName.text = ""
                        remoteFolderDialog.close()
                    }
                }
            }
        }
    }

    Dialog {
        id: remoteRenameDialog
        modal: true
        anchors.centerIn: parent
        width: 420
        padding: 20
        standardButtons: Dialog.NoButton
        background: Rectangle { radius: 16; color: root.panel2; border.color: root.border }
        contentItem: ColumnLayout {
            spacing: 14
            Label { text: "Rename remote item"; color: root.textColor; font.pixelSize: 18; font.bold: true }
            UI.MTextField { id: remoteRenameField; Layout.fillWidth: true; onAccepted: remoteRenameApply.clicked() }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                UI.MButton { text: "Cancel"; compact: true; onClicked: remoteRenameDialog.close() }
                UI.MButton {
                    id: remoteRenameApply
                    text: "Rename"
                    primary: true
                    compact: true
                    onClicked: {
                        remoteFiles.renameEntry(root.firstRemoteRow(), remoteRenameField.text)
                        remoteRenameDialog.close()
                    }
                }
            }
        }
    }

    Dialog {
        id: remoteDeleteDialog
        modal: true
        anchors.centerIn: parent
        width: 430
        padding: 20
        standardButtons: Dialog.NoButton
        background: Rectangle { radius: 16; color: root.panel2; border.color: root.border }
        contentItem: ColumnLayout {
            spacing: 14
            Label { text: "Delete remote item?"; color: root.textColor; font.pixelSize: 18; font.bold: true }
            Label { text: remoteFiles.entryName(root.firstRemoteRow()); color: root.muted; Layout.fillWidth: true; elide: Text.ElideMiddle }
            Label { text: "Directories must be empty before they can be removed."; color: root.warning; font.pixelSize: 10; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                UI.MButton { text: "Cancel"; compact: true; onClicked: remoteDeleteDialog.close() }
                UI.MButton {
                    text: "Delete"
                    danger: true
                    compact: true
                    onClicked: {
                        remoteFiles.deleteEntry(root.firstRemoteRow())
                        root.remoteSelection = []
                        remoteDeleteDialog.close()
                    }
                }
            }
        }
    }

    Dialog {
        id: remoteChmodDialog
        modal: true
        anchors.centerIn: parent
        width: 420
        padding: 20
        standardButtons: Dialog.NoButton
        background: Rectangle { radius: 16; color: root.panel2; border.color: root.border }
        contentItem: ColumnLayout {
            spacing: 14
            Label { text: "Change permissions"; color: root.textColor; font.pixelSize: 18; font.bold: true }
            Label { text: "SFTP only • octal mode"; color: root.muted; font.pixelSize: 10 }
            UI.MTextField { id: remoteModeField; Layout.fillWidth: true; placeholderText: "755"; onAccepted: remoteChmodApply.clicked() }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                UI.MButton { text: "Cancel"; compact: true; onClicked: remoteChmodDialog.close() }
                UI.MButton {
                    id: remoteChmodApply
                    text: "Apply"
                    primary: true
                    compact: true
                    onClicked: {
                        remoteFiles.chmodEntry(root.firstRemoteRow(), remoteModeField.text)
                        remoteChmodDialog.close()
                    }
                }
            }
        }
    }

    Popup {
        id: remoteContext
        parent: Overlay.overlay
        width: 230
        padding: 6
        modal: false
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle { radius: 12; color: "#2a2b2d"; border.color: "#45474a" }
        contentItem: Column {
            spacing: 2
            UI.MContextItem {
                width: parent.width
                iconText: "↳"
                text: "Open folder"
                enabled: root.firstRemoteRow() >= 0 && remoteFiles.entryIsDirectory(root.firstRemoteRow())
                onClicked: { remoteFiles.openEntry(root.firstRemoteRow()); root.remoteSelection = []; remoteContext.close() }
            }
            UI.MContextItem { width: parent.width; iconText: "⇩"; text: "Download selected…"; enabled: root.remoteSelection.length > 0; onClicked: { remoteContext.close(); root.downloadSelected() } }
            UI.MContextItem { width: parent.width; iconText: "+"; text: "New folder…"; onClicked: { remoteContext.close(); remoteFolderDialog.open(); remoteFolderName.forceActiveFocus() } }
            Rectangle { width: parent.width; height: 1; color: root.border }
            UI.MContextItem {
                width: parent.width
                iconText: "✎"
                text: "Rename…"
                enabled: root.remoteSelection.length === 1
                onClicked: {
                    remoteRenameField.text = remoteFiles.entryName(root.firstRemoteRow())
                    remoteContext.close()
                    remoteRenameDialog.open()
                    remoteRenameField.forceActiveFocus()
                }
            }
            UI.MContextItem {
                width: parent.width
                iconText: "755"
                text: "Permissions…"
                visible: root.protocol === "sftp"
                enabled: root.remoteSelection.length === 1
                onClicked: { remoteContext.close(); remoteModeField.text = "755"; remoteChmodDialog.open(); remoteModeField.forceActiveFocus() }
            }
            UI.MContextItem { width: parent.width; iconText: "×"; text: "Delete…"; danger: true; enabled: root.remoteSelection.length === 1; onClicked: { remoteContext.close(); remoteDeleteDialog.open() } }
            Rectangle { width: parent.width; height: 1; color: root.border }
            UI.MContextItem { width: parent.width; iconText: "↻"; text: "Refresh"; onClicked: { remoteFiles.refresh(); remoteContext.close() } }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 52
            color: root.panel2
            border.color: root.border
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 10
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    Label { text: root.protocol.toUpperCase() + " file session"; color: root.textColor; font.bold: true; font.pixelSize: 12 }
                    Label { text: remoteFiles.sessionLabel; color: root.muted; font.pixelSize: 9; elide: Text.ElideRight; Layout.fillWidth: true }
                }
                UI.MCheckBox { id: overwriteBox; text: "Overwrite duplicates"; checked: root.overwriteExisting; onToggled: remoteFiles.overwriteExisting = checked }
                Label { text: remoteFiles.activeTransferCount > 0 ? remoteFiles.activeTransferCount + " active • " + remoteFiles.overallProgress + "%" : "Queue idle"; color: remoteFiles.activeTransferCount > 0 ? root.accent : root.muted; font.pixelSize: 10 }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 1

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: root.bg
                border.color: root.border
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8
                    RowLayout {
                        Layout.fillWidth: true
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Label { text: "LOCAL SOURCE"; color: root.textColor; font.bold: true; font.pixelSize: 12 }
                            Label { text: localSelection.length + " selected"; color: root.muted; font.pixelSize: 9 }
                        }
                        UI.MIconButton { text: "↻"; tip: "Refresh local files"; onClicked: localFiles.refresh() }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        UI.MIconButton { text: "↑"; tip: "Parent folder"; onClicked: { localSelection = []; localFiles.goUp() } }
                        UI.MTextField { Layout.fillWidth: true; text: localFiles.currentPath; onAccepted: { localSelection = []; localFiles.goToPath(text) } }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        height: 27
                        radius: 4
                        color: root.panel2
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            Label { text: "Name"; color: root.muted; font.pixelSize: 9; Layout.fillWidth: true }
                            Label { text: "Size"; color: root.muted; font.pixelSize: 9; Layout.preferredWidth: 75; horizontalAlignment: Text.AlignRight }
                        }
                    }
                    ListView {
                        id: localList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 2
                        model: localFiles.entries
                        delegate: Rectangle {
                            id: localRow
                            required property int index
                            required property string name
                            required property string path
                            required property double size
                            required property bool directory
                            width: localList.width
                            height: 38
                            radius: 4
                            color: root.containsRow(root.localSelection, index) ? root.accentSoft : (localHover.hovered ? root.panel3 : "transparent")
                            border.color: root.containsRow(root.localSelection, index) ? "#4d6a5e" : "transparent"
                            HoverHandler { id: localHover }
                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: function(mouse) {
                                    root.selectRow("local", index, mouse.modifiers)
                                    if (mouse.button === Qt.RightButton) {
                                        // Right click selects the item; upload remains explicit to avoid accidental transfers.
                                    }
                                }
                                onDoubleClicked: function(mouse) {
                                    if (mouse.button === Qt.LeftButton && directory) {
                                        root.localSelection = []
                                        localFiles.openEntry(index)
                                    }
                                }
                            }
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 8
                                Rectangle {
                                    width: 18; height: 18; radius: 5
                                    color: root.containsRow(root.localSelection, index) ? root.accent : "transparent"
                                    border.color: root.containsRow(root.localSelection, index) ? root.accent : "#51555a"
                                    Label { anchors.centerIn: parent; visible: root.containsRow(root.localSelection, index); text: "✓"; color: "#111315"; font.pixelSize: 10; font.bold: true }
                                }
                                Image {
                                    source: root.fileIconSource(name, directory)
                                    Layout.preferredWidth: 20
                                    Layout.preferredHeight: 20
                                    sourceSize.width: 20
                                    sourceSize.height: 20
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                }
                                Label { text: name; color: root.textColor; elide: Text.ElideRight; Layout.fillWidth: true }
                                Label { text: directory ? "—" : root.formatBytes(size); color: root.muted; font.pixelSize: 9; Layout.preferredWidth: 75; horizontalAlignment: Text.AlignRight }
                            }
                        }
                    }
                    Label { text: localFiles.statusText; color: root.muted; font.pixelSize: 9; Layout.fillWidth: true; elide: Text.ElideRight }
                }
            }

            Rectangle {
                Layout.preferredWidth: 104
                Layout.fillHeight: true
                color: root.panel
                border.color: root.border
                ColumnLayout {
                    anchors.centerIn: parent
                    width: 88
                    spacing: 12
                    UI.MButton {
                        text: "Upload"
                        iconText: "→"
                        primary: true
                        compact: true
                        Layout.fillWidth: true
                        enabled: root.localSelection.length > 0
                        onClicked: root.uploadSelected()
                    }
                    UI.MButton {
                        text: "Download"
                        iconText: "←"
                        compact: true
                        Layout.fillWidth: true
                        enabled: root.remoteSelection.length > 0
                        onClicked: root.downloadSelected()
                    }
                    Label { text: "Ctrl/Shift\nfor multi-select"; color: root.muted; font.pixelSize: 8; horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: root.bg
                border.color: root.border
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8
                    RowLayout {
                        Layout.fillWidth: true
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Label { text: "REMOTE FILE MANAGER"; color: root.textColor; font.bold: true; font.pixelSize: 12 }
                            Label { text: root.remoteSelection.length + " selected • " + root.protocol.toUpperCase(); color: root.muted; font.pixelSize: 9 }
                        }
                        BusyIndicator { running: remoteFiles.busy; visible: running; implicitWidth: 24; implicitHeight: 24 }
                        UI.MIconButton { text: "+D"; tip: "New remote folder"; onClicked: { remoteFolderDialog.open(); remoteFolderName.forceActiveFocus() } }
                        UI.MIconButton { text: "↻"; tip: "Refresh remote files"; enabled: !remoteFiles.busy; onClicked: remoteFiles.refresh() }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        UI.MIconButton { text: "↑"; tip: "Parent folder"; enabled: !remoteFiles.busy; onClicked: { remoteSelection = []; remoteFiles.goUp() } }
                        UI.MTextField { Layout.fillWidth: true; text: remoteFiles.currentPath; onAccepted: { remoteSelection = []; remoteFiles.goToPath(text) } }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        height: 27
                        radius: 4
                        color: root.panel2
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            Label { text: "Name"; color: root.muted; font.pixelSize: 9; Layout.fillWidth: true }
                            Label { text: "Mode"; color: root.muted; font.pixelSize: 9; Layout.preferredWidth: 72 }
                            Label { text: "Size"; color: root.muted; font.pixelSize: 9; Layout.preferredWidth: 75; horizontalAlignment: Text.AlignRight }
                        }
                    }
                    ListView {
                        id: remoteList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 2
                        model: remoteFiles.entries
                        delegate: Rectangle {
                            id: remoteRow
                            required property int index
                            required property string name
                            required property string permissions
                            required property double size
                            required property bool directory
                            width: remoteList.width
                            height: 38
                            radius: 4
                            color: root.containsRow(root.remoteSelection, index) ? root.accentSoft : (remoteHover.hovered ? root.panel3 : "transparent")
                            border.color: root.containsRow(root.remoteSelection, index) ? "#4d6a5e" : "transparent"
                            HoverHandler { id: remoteHover }
                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                hoverEnabled: true
                                onClicked: function(mouse) {
                                    root.selectRow("remote", index, mouse.modifiers)
                                    if (mouse.button === Qt.RightButton) {
                                        root.openAdaptiveContextPopup(remoteContext, remoteRow, mouse.x, mouse.y)
                                    }
                                }
                                onDoubleClicked: function(mouse) {
                                    if (mouse.button === Qt.LeftButton && directory) {
                                        root.remoteSelection = []
                                        remoteFiles.openEntry(index)
                                    }
                                }
                            }
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 8
                                Rectangle {
                                    width: 18; height: 18; radius: 5
                                    color: root.containsRow(root.remoteSelection, index) ? root.accent : "transparent"
                                    border.color: root.containsRow(root.remoteSelection, index) ? root.accent : "#51555a"
                                    Label { anchors.centerIn: parent; visible: root.containsRow(root.remoteSelection, index); text: "✓"; color: "#111315"; font.pixelSize: 10; font.bold: true }
                                }
                                Image {
                                    source: root.fileIconSource(name, directory)
                                    Layout.preferredWidth: 20
                                    Layout.preferredHeight: 20
                                    sourceSize.width: 20
                                    sourceSize.height: 20
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                }
                                Label { text: name; color: root.textColor; elide: Text.ElideRight; Layout.fillWidth: true }
                                Label { text: permissions.length ? permissions : "—"; color: root.muted; font.pixelSize: 9; font.family: "monospace"; Layout.preferredWidth: 72 }
                                Label { text: directory ? "—" : root.formatBytes(size); color: root.muted; font.pixelSize: 9; Layout.preferredWidth: 75; horizontalAlignment: Text.AlignRight }
                            }
                        }
                    }
                    Label { text: remoteFiles.statusText; color: root.muted; font.pixelSize: 9; Layout.fillWidth: true; elide: Text.ElideRight }
                    Label {
                        visible: root.protocol === "ftp" && !root.ftpTls
                        text: "Plain FTP sends credentials and data without encryption. Prefer SFTP or enable FTPS/TLS."
                        color: root.warning
                        font.pixelSize: 9
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    Label {
                        visible: root.protocol === "ftp" && root.ftpTls && remoteFiles.tlsVerificationBypassed
                        text: "FTPS certificate verification is bypassed for this session. Traffic is encrypted, but server identity is not being verified."
                        color: root.warning
                        font.pixelSize: 9
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }
            }
        }

        Rectangle {
            visible: remoteFiles.transfers.length > 0
            Layout.fillWidth: true
            Layout.preferredHeight: visible ? Math.min(190, 56 + transferColumn.implicitHeight) : 0
            color: "#232527"
            border.color: root.border
            clip: true
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 7
                RowLayout {
                    Layout.fillWidth: true
                    Label { text: "TRANSFERS"; color: root.textColor; font.bold: true; font.pixelSize: 11 }
                    Label { text: remoteFiles.activeTransferCount > 0 ? remoteFiles.overallProgress + "% overall" : "Completed"; color: remoteFiles.activeTransferCount > 0 ? root.accent : root.muted; font.pixelSize: 9 }
                    Item { Layout.fillWidth: true }
                    UI.MButton { text: "Cancel all"; compact: true; visible: remoteFiles.activeTransferCount > 0; onClicked: remoteFiles.cancelAllTransfers() }
                    UI.MButton { text: "Clear"; compact: true; onClicked: remoteFiles.clearFinishedTransfers() }
                }
                Flickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentWidth: width
                    contentHeight: transferColumn.implicitHeight
                    clip: true
                    Column {
                        id: transferColumn
                        width: parent.width
                        spacing: 5
                        Repeater {
                            model: remoteFiles.transfers
                            delegate: Rectangle {
                                required property var modelData
                                width: transferColumn.width
                                height: 48
                                radius: 9
                                color: root.panel2
                                border.color: root.border
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 8
                                    spacing: 9
                                    Label { text: modelData.direction === "Upload" ? "↑" : "↓"; color: root.accent; font.pixelSize: 16; Layout.preferredWidth: 20 }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 3
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Label { text: modelData.label; color: root.textColor; font.pixelSize: 10; elide: Text.ElideRight; Layout.fillWidth: true }
                                            Label { text: modelData.state === "Running" || modelData.state === "Queued" ? modelData.progress + "%" : modelData.state; color: modelData.state === "Failed" ? root.danger : (modelData.state === "Done" ? root.accent : root.muted); font.pixelSize: 9 }
                                        }
                                        Rectangle {
                                            Layout.fillWidth: true
                                            height: 5
                                            radius: 3
                                            color: "#303234"
                                            Rectangle { width: parent.width * Math.max(0, Math.min(100, Number(modelData.progress))) / 100; height: parent.height; radius: 3; color: modelData.state === "Failed" ? root.danger : root.accent }
                                        }
                                    }
                                    UI.MIconButton { text: "×"; tip: "Cancel transfer"; visible: modelData.state === "Running" || modelData.state === "Queued"; onClicked: remoteFiles.cancelTransfer(Number(modelData.id)) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    function formatBytes(value) {
        var n = Number(value)
        if (!isFinite(n) || n < 0) return "—"
        if (n < 1024) return n + " B"
        if (n < 1024 * 1024) return (n / 1024).toFixed(1) + " KB"
        if (n < 1024 * 1024 * 1024) return (n / (1024 * 1024)).toFixed(1) + " MB"
        return (n / (1024 * 1024 * 1024)).toFixed(1) + " GB"
    }
}
