import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import Qt.labs.settings 1.1
import MoriXterm.Terminal 1.0
import MoriXterm.FileManager 1.0
import MoriXterm.Rdp 1.0
import "components" as UI

ApplicationWindow {
    id: root
    width: 1720
    height: 980
    minimumWidth: 1180
    minimumHeight: 700
    visible: true
    title: "MoriXterm"
    color: "#1e1f20"

    // Neutral charcoal theme based on the compact desktop reference. Green is
    // reserved for state/selection instead of tinting every surface.
    property color bg: "#1e1f20"
    property color panel: "#222325"
    property color panel2: "#292a2c"
    property color panel3: "#303134"
    property color border: "#3a3c3f"
    property color text: "#e2e4e6"
    property color muted: "#8b8f94"
    property color accent: "#38d996"
    property color accent2: "#62e4af"
    property color accentSoft: "#2b3a34"
    property color danger: "#ff7078"
    property color warning: "#e3b85c"
    property string rdpRemoteShare: String.fromCharCode(92, 92) + "tsclient" + String.fromCharCode(92) + "morixterm"

    function effectiveRdpScale(sessionScale) {
        // Settings → RDP → Default zoom is the live value used on connect.
        // Per-session scale is only a fallback when settings are missing/invalid.
        var settings = Number(rdpSettings.defaultScale)
        if (isFinite(settings) && settings >= 100 && settings <= 300)
            return Math.round(settings)
        var s = Number(sessionScale)
        if (isFinite(s) && s >= 100 && s <= 300)
            return Math.round(s)
        return 125
    }

    Settings {
        id: terminalSettings
        category: "Terminal"
        property string themeName: "MoriXterm"
        property real fontSize: 11.5
    }

    Settings {
        id: uiSettings
        category: "UI"
        property real sessionsSidebarWidth: 225
        property real filePanelWidth: 360
    }

    Settings {
        id: rdpSettings
        category: "RDP"
        property int defaultScale: 125
        property string sharedFolder: ""
    }

    property string terminalTheme: terminalSettings.themeName
    property real terminalFontSize: terminalSettings.fontSize
    property var terminalThemes: ["MoriXterm", "Dracula", "Nord", "Solarized Dark", "Monokai", "Light"]

    property string pageMode: "home"
    property int currentTab: -1
    property var activeTerminal: null
    property bool filePanelVisible: true
    property bool appFullscreen: false

    property int selectedFileIndex: -1
    property string selectedFileName: ""
    property bool selectedFileDirectory: false
    property string selectedFilePermissions: "---------"
    property string selectedFileOwner: ""
    property string selectedFileGroup: ""

    property int editingSessionId: 0
    property bool editingCredentialSaved: false
    property int editingFolderId: 0
    property string sessionEditorMode: "new"
    property var folderModelCache: []
    property var recentSessionsCache: []

    property int contextSessionId: 0
    property int contextFolderId: 0
    property string contextFolderName: ""

    property bool draggingSession: false
    property int draggingSessionId: 0
    property string draggingSessionName: ""
    property int dragTargetFolderId: 0
    property string dragTargetFolderName: ""

    function showToast(message, kind, allowWhenLocked) {
        if (!message || String(message).trim().length === 0) return
        if (appLock.locked && !allowWhenLocked) return
        toastHost.show(String(message).trim(), kind || "info")
    }

    function escapeRichText(value) {
        return String(value || "")
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")
            .replace(/\"/g, "&quot;")
    }

    function sessionEndpointHtml(user, host, port) {
        var palettes = {
            "MoriXterm": ["#62d196", "#61afef", "#e5c07b"],
            "Dracula": ["#50fa7b", "#8be9fd", "#f1fa8c"],
            "Nord": ["#a3be8c", "#88c0d0", "#ebcb8b"],
            "Solarized Dark": ["#859900", "#2aa198", "#b58900"],
            "Monokai": ["#a6e22e", "#66d9ef", "#e6db74"],
            "Light": ["#116329", "#0969da", "#633c01"]
        }
        var colors = palettes[root.terminalTheme] || palettes["MoriXterm"]
        var userText = escapeRichText(user)
        var hostText = escapeRichText(host)
        var portText = escapeRichText(port)
        var prefix = userText.length
            ? "<font color='" + colors[0] + "'>" + userText + "</font><font color='#8b9a92'>@</font>"
            : ""
        return prefix
            + "<font color='" + colors[1] + "'>" + hostText + "</font>"
            + "<font color='" + colors[2] + "'>:" + portText + "</font>"
    }


    function openAdaptiveContextPopup(popup, sourceItem, localX, localY) {
        if (!popup || !sourceItem || !Overlay.overlay) return

        var overlay = Overlay.overlay
        var point = sourceItem.mapToItem(overlay, localX, localY)
        var margin = 12
        var gap = 7
        var popupWidth = Math.max(1, popup.width > 0 ? popup.width : popup.implicitWidth)
        var contentHeight = popup.contentItem ? popup.contentItem.implicitHeight : 0
        var popupHeight = Math.max(1, popup.height > 0 ? popup.height : popup.implicitHeight,
                                   contentHeight + popup.topPadding + popup.bottomPadding)

        var x = point.x
        if (x + popupWidth > overlay.width - margin)
            x = overlay.width - popupWidth - margin
        x = Math.max(margin, x)

        // Open downwards everywhere except when there is not enough room below.
        var y = point.y + gap
        if (y + popupHeight > overlay.height - margin)
            y = point.y - popupHeight - gap

        // Final clamp guarantees that the complete menu remains visible.
        y = Math.max(margin, Math.min(y, overlay.height - popupHeight - margin))

        popup.x = x
        popup.y = y
        popup.open()
    }

    function moveSessionIntoFolder(sessionId, folderId, folderName, sessionName) {
        var sid = Number(sessionId)
        var fid = Number(folderId)
        if (sid <= 0) {
            showToast("Unable to move the session: invalid session id.", "error")
            return false
        }
        var ok = sessionStore.moveSessionToFolder(sid, fid)
        if (!ok) {
            showToast(sessionStore.lastError.length ? sessionStore.lastError : "Unable to move the session.", "error")
            return false
        }
        showToast(fid > 0 ? "“" + (sessionName || draggingSessionName || "Session") + "” moved to “" + folderName + "”." : "Session moved to Ungrouped.", "success")
        return true
    }

    // Session drag/drop is handled manually instead of relying on Qt Quick's
    // Drag/DropArea delivery. This is more reliable inside a scrolling ListView
    // and avoids Wayland cases where DropEvent.source can be null or no drop is
    // delivered after the delegate moves.
    function beginSessionDrag(sessionId, sessionName) {
        draggingSession = true
        draggingSessionId = Number(sessionId)
        draggingSessionName = String(sessionName || "Session")
        dragTargetFolderId = 0
        dragTargetFolderName = ""
    }

    function updateSessionDragTarget(sourceItem, localX, localY) {
        if (!draggingSession || !sourceItem || !sessionList || !sessionList.contentItem)
            return

        var point = sourceItem.mapToItem(sessionList.contentItem, localX, localY)
        var children = sessionList.contentItem.children
        var targetId = 0
        var targetName = ""

        // Iterate visible delegates and hit-test folders in content coordinates.
        // The dragged session may be indented or the ListView may be scrolled;
        // mapToItem keeps the calculation correct in both cases.
        for (var i = 0; i < children.length; ++i) {
            var child = children[i]
            if (!child || child.isFolder !== true || !child.visible)
                continue
            var inside = sessionList.contentItem.mapToItem(child, point.x, point.y)
            if (inside.x >= 0 && inside.x <= child.width &&
                    inside.y >= 0 && inside.y <= child.height) {
                targetId = Number(child.itemId)
                targetName = String(child.name || "Folder")
                break
            }
        }

        dragTargetFolderId = targetId
        dragTargetFolderName = targetName
    }

    function cancelSessionDrag() {
        draggingSession = false
        draggingSessionId = 0
        draggingSessionName = ""
        dragTargetFolderId = 0
        dragTargetFolderName = ""
    }

    function finishSessionDrag() {
        var sid = Number(draggingSessionId)
        var sessionName = draggingSessionName
        var fid = Number(dragTargetFolderId)
        var folderName = dragTargetFolderName

        // Reset visual state before SessionStore reloads the ListView model.
        cancelSessionDrag()

        if (sid <= 0) {
            showToast("Unable to identify the dragged session.", "error")
            return false
        }
        if (fid <= 0) {
            showToast("Drop the session on a session folder.", "info")
            return false
        }
        Qt.callLater(function() {
            root.moveSessionIntoFolder(sid, fid, folderName, sessionName)
        })
        return true
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

    property bool fileManagerAvailable: currentTab >= 0 && currentTab < tabsModel.count
                                        && (tabsModel.get(currentTab).kind === "ssh" || tabsModel.get(currentTab).kind === "local")

    FileManagerController { id: fileManager }

    ListModel { id: tabsModel }

    function refreshHome() {
        recentSessionsCache = sessionStore.recentSessions(6)
    }

    function folderIndex(folderId) {
        for (var i = 0; i < folderModelCache.length; ++i)
            if (Number(folderModelCache[i].id) === Number(folderId)) return i
        return 0
    }

    function securityProfileFromIndex(index) {
        if (index === 1) return "compatible"
        if (index === 2) return "legacy"
        return "modern"
    }

    function securityIndex(profile) {
        if (profile === "compatible") return 1
        if (profile === "legacy") return 2
        return 0
    }

    function syncFileManager() {
        if (currentTab < 0 || currentTab >= tabsModel.count)
            return
        selectedFileIndex = -1
        selectedFileName = ""
        var tab = tabsModel.get(currentTab)
        if (tab.kind === "ssh")
            fileManager.configureSsh(tab.host, tab.user, tab.port, tab.controlPath, tab.securityProfile, tab.keyFile)
        else if (tab.kind === "local")
            fileManager.configureLocal()
    }

    function openLocal() {
        tabsModel.append({
            sessionId: 0, title: "Local", kind: "local", host: "", user: "", port: 0,
            program: "", argsJson: "[]", password: "", controlPath: "", securityProfile: "modern", keyFile: "",
            domain: "", rdpWidth: 1440, rdpHeight: 900, rdpScale: 125, fullscreen: false, ignoreCertificate: false,
            ftpTls: true, ftpPassive: true, overwriteExisting: true, maxParallel: 4
        })
        currentTab = tabsModel.count - 1
        pageMode = "workspace"
        Qt.callLater(syncFileManager)
    }

    function openConnection(sessionId, name, kind, host, user, port, password,
                            securityProfile, keyFile, domain, width, height, fullscreen, ignoreCertificate,
                            ftpTls, ftpPassive, overwriteExisting, maxParallel, rdpScale) {
        var normalizedKind = kind || "ssh"
        var base = {
            sessionId: sessionId,
            title: name || host,
            kind: normalizedKind,
            host: host,
            user: user,
            port: port,
            program: "",
            argsJson: "[]",
            password: password || "",
            controlPath: "",
            securityProfile: securityProfile || "modern",
            keyFile: keyFile || "",
            domain: domain || "",
            rdpWidth: width || 1440,
            rdpHeight: height || 900,
            rdpScale: root.effectiveRdpScale(rdpScale || rdpSettings.defaultScale || 125),
            fullscreen: !!fullscreen,
            ignoreCertificate: !!ignoreCertificate,
            ftpTls: ftpTls === undefined ? true : !!ftpTls,
            ftpPassive: ftpPassive === undefined ? true : !!ftpPassive,
            overwriteExisting: overwriteExisting === undefined ? true : !!overwriteExisting,
            maxParallel: Math.max(1, Math.min(8, Number(maxParallel || 4)))
        }

        if (normalizedKind === "ssh") {
            var args = sshSecurity.buildArguments(host, user, port, securityProfile || "modern", keyFile || "")
            base.program = sshSecurity.clientExecutable()
            base.argsJson = JSON.stringify(args)
            base.controlPath = sshSecurity.controlPathTemplate
        }
        tabsModel.append(base)
        currentTab = tabsModel.count - 1
        pageMode = "workspace"
        if (sessionId > 0) sessionStore.markUsed(sessionId)
        Qt.callLater(syncFileManager)
        refreshHome()
    }

    function openSavedSession(sessionId, name, kind, host, user, port, securityProfile, keyFile,
                              domain, width, height, fullscreen, ignoreCertificate,
                              ftpTls, ftpPassive, overwriteExisting, maxParallel, rdpScale) {
        var password = sessionStore.passwordForSession(sessionId)
        openConnection(sessionId, name, kind, host, user, port, password, securityProfile, keyFile,
                       domain, width, height, fullscreen, ignoreCertificate,
                       ftpTls, ftpPassive, overwriteExisting, maxParallel, rdpScale)
    }

    function closeTab(index) {
        if (index < 0 || index >= tabsModel.count) return
        if (index === currentTab) activeTerminal = null
        tabsModel.remove(index)
        if (tabsModel.count === 0) {
            currentTab = -1
            pageMode = "home"
            return
        }
        if (currentTab >= tabsModel.count) currentTab = tabsModel.count - 1
        else if (index < currentTab) currentTab--
        Qt.callLater(syncFileManager)
    }

    function protocolIndex(protocol) {
        if (protocol === "rdp") return 1
        if (protocol === "sftp") return 2
        if (protocol === "ftp") return 3
        return 0
    }

    function protocolKind(index) {
        if (index === 1) return "rdp"
        if (index === 2) return "sftp"
        if (index === 3) return "ftp"
        return "ssh"
    }

    function defaultPortForProtocol(index) {
        if (index === 1) return 3389
        if (index === 3) return 21
        return 22
    }

    function showNewSession(protocol) {
        editingSessionId = 0
        editingCredentialSaved = false
        editingFolderId = 0
        sessionEditorMode = "new"
        folderModelCache = sessionStore.folderOptions()
        protocolCombo.currentIndex = protocolIndex(protocol)
        sessionNameField.text = ""
        sessionHostField.text = ""
        sessionUserField.text = ""
        sessionPortField.text = String(defaultPortForProtocol(protocolCombo.currentIndex))
        sessionPasswordField.text = ""
        rememberPasswordBox.checked = false
        keyFileField.text = ""
        securityCombo.currentIndex = 0
        domainField.text = ""
        widthField.text = "1440"
        heightField.text = "900"
        scaleField.text = String(Math.max(100, Math.min(300, rdpSettings.defaultScale || 125)))
        fullscreenBox.checked = false
        ignoreCertBox.checked = false
        ftpTlsBox.checked = true
        ftpIgnoreCertBox.checked = false
        ftpPassiveBox.checked = true
        overwriteExistingBox.checked = true
        parallelField.text = "4"
        folderCombo.model = folderModelCache
        folderCombo.currentIndex = 0
        editorError.text = ""
        sessionEditor.open()
        sessionNameField.forceActiveFocus()
    }

    function showEditSession(sessionId, name, kind, host, user, port, securityProfile, keyFile,
                             credentialSaved, folderId, domain, width, height, fullscreen, ignoreCertificate,
                             ftpTls, ftpPassive, overwriteExisting, maxParallel, rdpScale) {
        editingSessionId = sessionId
        editingCredentialSaved = credentialSaved
        editingFolderId = folderId
        sessionEditorMode = "edit"
        folderModelCache = sessionStore.folderOptions()
        protocolCombo.currentIndex = protocolIndex(kind)
        sessionNameField.text = name
        sessionHostField.text = host
        sessionUserField.text = user
        sessionPortField.text = String(port)
        sessionPasswordField.text = ""
        rememberPasswordBox.checked = credentialSaved
        keyFileField.text = keyFile || ""
        securityCombo.currentIndex = securityIndex(securityProfile)
        domainField.text = domain || ""
        widthField.text = String(width || 1440)
        heightField.text = String(height || 900)
        scaleField.text = String(rdpScale || rdpSettings.defaultScale || 125)
        fullscreenBox.checked = !!fullscreen
        ignoreCertBox.checked = !!ignoreCertificate
        ftpTlsBox.checked = ftpTls === undefined ? true : !!ftpTls
        ftpIgnoreCertBox.checked = kind === "ftp" ? !!ignoreCertificate : false
        ftpPassiveBox.checked = ftpPassive === undefined ? true : !!ftpPassive
        overwriteExistingBox.checked = overwriteExisting === undefined ? true : !!overwriteExisting
        parallelField.text = String(maxParallel || 4)
        folderCombo.model = folderModelCache
        folderCombo.currentIndex = folderIndex(folderId)
        editorError.text = ""
        sessionEditor.open()
    }

    function commitSession(connectAfter) {
        var kind = protocolKind(protocolCombo.currentIndex)
        var port = parseInt(sessionPortField.text)
        if (!port || port < 1 || port > 65535) port = defaultPortForProtocol(protocolCombo.currentIndex)
        var width = parseInt(widthField.text); if (!width) width = 1440
        var height = parseInt(heightField.text); if (!height) height = 900
        var scale = parseInt(scaleField.text); if (!scale) scale = rdpSettings.defaultScale || 125
        scale = Math.max(100, Math.min(300, scale))
        var parallel = parseInt(parallelField.text); if (!parallel) parallel = 4
        parallel = Math.max(1, Math.min(8, parallel))
        var profile = securityProfileFromIndex(securityCombo.currentIndex)
        var folderId = folderCombo.currentIndex >= 0 && folderModelCache.length > folderCombo.currentIndex
                     ? Number(folderModelCache[folderCombo.currentIndex].id) : 0
        var removeSaved = editingSessionId > 0 && editingCredentialSaved && !rememberPasswordBox.checked
        var sessionIgnoreCertificate = kind === "rdp" ? ignoreCertBox.checked
                                     : (kind === "ftp" ? ftpIgnoreCertBox.checked : false)
        var id = sessionStore.saveSession(
                    editingSessionId, sessionNameField.text, kind, sessionHostField.text, sessionUserField.text,
                    port, sessionPasswordField.text, rememberPasswordBox.checked, removeSaved, folderId,
                    profile, keyFileField.text, domainField.text, width, height,
                    fullscreenBox.checked, sessionIgnoreCertificate,
                    ftpTlsBox.checked, ftpPassiveBox.checked, overwriteExistingBox.checked, parallel, scale)
        if (id <= 0) {
            editorError.text = sessionStore.lastError
            root.showToast(sessionStore.lastError.length ? sessionStore.lastError : "Could not save the connection.", "error")
            return
        }
        if (kind === "rdp" && editingSessionId > 0) {
            for (var i = 0; i < tabsModel.count; ++i) {
                if (Number(tabsModel.get(i).sessionId) === Number(id)) {
                    tabsModel.setProperty(i, "rdpScale", scale)
                    tabsModel.setProperty(i, "rdpWidth", width)
                    tabsModel.setProperty(i, "rdpHeight", height)
                    tabsModel.setProperty(i, "fullscreen", fullscreenBox.checked)
                }
            }
        }
        var connectionPassword = sessionPasswordField.text
        if (connectionPassword.length === 0 && rememberPasswordBox.checked)
            connectionPassword = sessionStore.passwordForSession(id)
        var connectionName = sessionNameField.text.length ? sessionNameField.text : sessionHostField.text
        var connectionHost = sessionHostField.text
        var connectionUser = sessionUserField.text
        var connectionKey = keyFileField.text
        var connectionDomain = domainField.text
        var connectionFullscreen = fullscreenBox.checked
        var connectionIgnoreCert = sessionIgnoreCertificate
        var connectionScale = scale
        var connectionFtpTls = ftpTlsBox.checked
        var connectionFtpPassive = ftpPassiveBox.checked
        var connectionOverwrite = overwriteExistingBox.checked
        sessionPasswordField.text = ""
        editorError.text = ""
        sessionEditor.close()
        refreshHome()
        root.showToast(connectAfter ? "Connection saved. Opening session…" : "Connection saved.", "success")
        if (connectAfter)
            openConnection(id, connectionName, kind, connectionHost, connectionUser, port, connectionPassword,
                           profile, connectionKey, connectionDomain, width, height,
                           connectionFullscreen, connectionIgnoreCert,
                           connectionFtpTls, connectionFtpPassive, connectionOverwrite, parallel, connectionScale)
    }

    function showCompressDialog() {
        if (root.selectedFileIndex < 0 || fileManager.busy) return
        archiveNameField.text = fileManager.defaultArchiveName(root.selectedFileIndex)
        compressDialog.open()
        archiveNameField.forceActiveFocus()
        archiveNameField.selectAll()
    }

    function showExtractDialog() {
        if (root.selectedFileIndex < 0 || root.selectedFileDirectory || fileManager.busy) return
        if (!root.selectedFileName.toLowerCase().endsWith(".zip")) return
        extractFolderField.text = fileManager.defaultExtractFolder(root.selectedFileIndex)
        extractDialog.open()
        extractFolderField.forceActiveFocus()
        extractFolderField.selectAll()
    }

    onCurrentTabChanged: Qt.callLater(syncFileManager)
    Component.onCompleted: {
        // Re-read persisted profiles after the QML scene is ready. This avoids
        // stale/empty sidebar state when an older database was migrated during startup.
        sessionStore.reload()
        refreshHome()
        if (sessionStore.lastError && sessionStore.lastError.length)
            Qt.callLater(function() { root.showToast(sessionStore.lastError, "error", true) })
    }

    Connections {
        target: sessionStore
        function onFoldersChanged() { root.folderModelCache = sessionStore.folderOptions(); root.refreshHome() }
        function onModelReset() { root.refreshHome() }
        function onLastErrorChanged() {
            if (sessionStore.lastError && sessionStore.lastError.length)
                root.showToast(sessionStore.lastError, "error")
        }
    }

    Connections {
        target: fileManager
        function onOperationFinished(success, message) {
            if (!success && message && message.length)
                root.showToast(message, "error")
        }
    }

    // ---------- Unified session editor ----------
    Dialog {
        id: sessionEditor
        modal: true
        anchors.centerIn: parent
        width: Math.min(root.width - 80, 720)
        height: Math.min(root.height - 88, 820)
        padding: 0
        standardButtons: Dialog.NoButton
        closePolicy: Popup.CloseOnEscape
        background: Rectangle { radius: 18; color: root.panel2; border.color: "#2b4638"; border.width: 1 }

        contentItem: ColumnLayout {
            spacing: 0
            Rectangle {
                Layout.fillWidth: true; Layout.preferredHeight: 84; color: "transparent"
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 28; anchors.rightMargin: 20
                    ColumnLayout {
                        spacing: 2
                        Label { text: root.sessionEditorMode === "edit" ? "Edit connection" : "New connection"; color: root.text; font.pixelSize: 21; font.bold: true }
                        Label { text: "SSH, RDP, SFTP and FTP profiles in one secure connection form"; color: root.muted; font.pixelSize: 11 }
                    }
                    Item { Layout.fillWidth: true }
                    UI.MIconButton { text: "×"; tip: "Close"; onClicked: sessionEditor.close() }
                }
            }
            Rectangle { Layout.fillWidth: true; height: 1; color: root.border }
            ScrollView {
                Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                contentWidth: availableWidth
                ColumnLayout {
                    width: Math.max(0, parent.width - 56)
                    x: 28
                    spacing: 16
                    Item { Layout.preferredHeight: 8 }

                    RowLayout {
                        Layout.fillWidth: true; spacing: 12
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 6
                            Label { text: "Protocol"; color: root.muted; font.pixelSize: 11; font.bold: true }
                            UI.MComboBox {
                                id: protocolCombo
                                Layout.fillWidth: true
                                model: ["SSH", "RDP", "SFTP", "FTP"]
                                onCurrentIndexChanged: {
                                    if (!sessionEditor.visible) return
                                    if (root.sessionEditorMode === "new")
                                        sessionPortField.text = String(root.defaultPortForProtocol(currentIndex))
                                }
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 6
                            Label { text: "Session folder"; color: root.muted; font.pixelSize: 11; font.bold: true }
                            UI.MComboBox { id: folderCombo; Layout.fillWidth: true; textRole: "name"; valueRole: "id" }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 6
                        Label { text: "Display name"; color: root.muted; font.pixelSize: 11; font.bold: true }
                        UI.MTextField { id: sessionNameField; Layout.fillWidth: true; placeholderText: "Production API"; onAccepted: saveConnectButton.clicked() }
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 12
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 6
                            Label { text: "Host / IP"; color: root.muted; font.pixelSize: 11; font.bold: true }
                            UI.MTextField { id: sessionHostField; Layout.fillWidth: true; placeholderText: "server.example.com"; onAccepted: saveConnectButton.clicked() }
                        }
                        ColumnLayout {
                            Layout.preferredWidth: 120; spacing: 6
                            Label { text: "Port"; color: root.muted; font.pixelSize: 11; font.bold: true }
                            UI.MTextField { id: sessionPortField; Layout.fillWidth: true; inputMethodHints: Qt.ImhDigitsOnly; onAccepted: saveConnectButton.clicked() }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 12
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 6
                            Label { text: "Username"; color: root.muted; font.pixelSize: 11; font.bold: true }
                            UI.MTextField { id: sessionUserField; Layout.fillWidth: true; placeholderText: protocolCombo.currentIndex === 1 ? "Administrator" : (protocolCombo.currentIndex === 3 ? "ftp-user" : "ubuntu"); onAccepted: saveConnectButton.clicked() }
                        }
                        ColumnLayout {
                            visible: protocolCombo.currentIndex === 1
                            Layout.fillWidth: true; spacing: 6
                            Label { text: "Domain"; color: root.muted; font.pixelSize: 11; font.bold: true }
                            UI.MTextField { id: domainField; Layout.fillWidth: true; placeholderText: "Optional"; onAccepted: saveConnectButton.clicked() }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true; implicitHeight: credentialColumn.implicitHeight + 24
                        radius: 12; color: "#26282a"; border.color: root.border
                        ColumnLayout {
                            id: credentialColumn
                            anchors.fill: parent; anchors.margins: 12; spacing: 8
                            RowLayout {
                                Layout.fillWidth: true
                                Label { text: "Credentials"; color: root.text; font.bold: true; font.pixelSize: 13 }
                                Item { Layout.fillWidth: true }
                                Label { text: credentialStore.backend; color: credentialStore.available ? root.accent : root.warning; font.pixelSize: 10 }
                            }
                            UI.MTextField {
                                id: sessionPasswordField; Layout.fillWidth: true; echoMode: TextInput.Password
                                placeholderText: root.editingCredentialSaved ? "Saved securely — leave blank to keep it" : "Password (optional)"
                                onAccepted: saveConnectButton.clicked()
                            }
                            UI.MCheckBox {
                                id: rememberPasswordBox
                                text: root.editingCredentialSaved ? "Keep password in the OS credential vault" : "Remember password securely"
                                enabled: credentialStore.available
                            }
                            Label {
                                visible: !credentialStore.available
                                Layout.fillWidth: true; wrapMode: Text.WordWrap; color: root.warning; font.pixelSize: 10
                                text: "Secure credential storage is unavailable. Linux: install libsecret-tools. Passwords are never written to SQLite."
                            }
                        }
                    }

                    ColumnLayout {
                        visible: protocolCombo.currentIndex === 0 || protocolCombo.currentIndex === 2
                        Layout.fillWidth: true
                        spacing: 10
                        Label { text: protocolCombo.currentIndex === 2 ? "SFTP security" : "SSH security"; color: root.text; font.pixelSize: 13; font.bold: true }
                        UI.MComboBox { id: securityCombo; visible: protocolCombo.currentIndex === 0; Layout.fillWidth: true; model: ["Modern", "Compatible", "Legacy"] }
                        Label {
                            visible: protocolCombo.currentIndex === 0
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            color: securityCombo.currentIndex === 2 ? root.warning : root.muted
                            font.pixelSize: 10
                            text: sshSecurity.profileWarning(root.securityProfileFromIndex(securityCombo.currentIndex))
                        }
                        Label { text: "Private key path (optional)"; color: root.muted; font.pixelSize: 11; font.bold: true }
                        UI.MTextField { id: keyFileField; Layout.fillWidth: true; placeholderText: "~/.ssh/id_ed25519"; onAccepted: saveConnectButton.clicked() }
                        Label {
                            visible: protocolCombo.currentIndex === 2
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            color: root.muted
                            font.pixelSize: 10
                            text: "SFTP uses curl's SSH backend and verifies the server against ~/.ssh/known_hosts when that file exists."
                        }
                        Rectangle {
                            visible: protocolCombo.currentIndex === 0 && securityCombo.currentIndex === 2
                            Layout.fillWidth: true
                            implicitHeight: legacyWarning.implicitHeight + 20
                            radius: 9
                            color: "#2b2411"
                            border.color: "#6d5720"
                            Label {
                                id: legacyWarning
                                anchors.fill: parent
                                anchors.margins: 10
                                wrapMode: Text.WordWrap
                                color: root.warning
                                font.pixelSize: 10
                                text: "Legacy mode is opt-in per session. It may enable ssh-rsa/ssh-dss, SHA-1 KEX, CBC ciphers and HMAC-SHA1 only when your installed OpenSSH still provides them. Prefer upgrading the remote server."
                            }
                        }
                    }

                    ColumnLayout {
                        visible: protocolCombo.currentIndex === 1
                        Layout.fillWidth: true; spacing: 10
                        Label { text: "Remote Desktop"; color: root.text; font.pixelSize: 13; font.bold: true }
                        RowLayout {
                            Layout.fillWidth: true; spacing: 12
                            UI.MTextField { id: widthField; Layout.fillWidth: true; placeholderText: "Width"; inputMethodHints: Qt.ImhDigitsOnly; onAccepted: saveConnectButton.clicked() }
                            UI.MTextField { id: heightField; Layout.fillWidth: true; placeholderText: "Height"; inputMethodHints: Qt.ImhDigitsOnly; onAccepted: saveConnectButton.clicked() }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Label { text: "Display zoom"; color: root.muted; Layout.fillWidth: true }
                            UI.MTextField { id: scaleField; Layout.preferredWidth: 110; placeholderText: "100–300%"; inputMethodHints: Qt.ImhDigitsOnly; onAccepted: saveConnectButton.clicked() }
                            Label { text: "%"; color: root.muted }
                        }
                        Label { text: "Magnifies the remote desktop. Change this profile's zoom here; reconnect to apply."; color: root.muted; font.pixelSize: 11; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                        UI.MCheckBox { id: fullscreenBox; text: "Fullscreen" }
                        UI.MCheckBox {
                            id: ignoreCertBox
                            text: "Ignore certificate validation (unsafe; use only for known legacy hosts)"
                            checked: false
                        }
                    }

                    Rectangle {
                        visible: protocolCombo.currentIndex === 3
                        Layout.fillWidth: true
                        implicitHeight: ftpOptions.implicitHeight + 24
                        radius: 12
                        color: "#26282a"
                        border.color: root.border
                        ColumnLayout {
                            id: ftpOptions
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 8
                            Label { text: "FTP security"; color: root.text; font.pixelSize: 13; font.bold: true }
                            UI.MCheckBox { id: ftpTlsBox; text: "Require TLS (FTPS)"; checked: true }
                            UI.MCheckBox {
                                id: ftpIgnoreCertBox
                                visible: ftpTlsBox.checked
                                text: "Allow invalid or hostname-mismatched TLS certificate for this profile"
                                checked: false
                            }
                            Label {
                                visible: ftpTlsBox.checked && ftpIgnoreCertBox.checked
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                color: root.warning
                                font.pixelSize: 10
                                text: "Less secure: certificate CA/hostname verification will be bypassed only for this saved FTP profile."
                            }
                            UI.MCheckBox { id: ftpPassiveBox; text: "Passive mode"; checked: true }
                            Label {
                                visible: !ftpTlsBox.checked
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                color: root.warning
                                font.pixelSize: 10
                                text: "Plain FTP is not encrypted. Credentials and file contents can be read on the network. Prefer SFTP or enable FTPS/TLS."
                            }
                        }
                    }

                    Rectangle {
                        visible: protocolCombo.currentIndex === 2 || protocolCombo.currentIndex === 3
                        Layout.fillWidth: true
                        implicitHeight: transferOptions.implicitHeight + 24
                        radius: 12
                        color: "#26282a"
                        border.color: root.border
                        ColumnLayout {
                            id: transferOptions
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 8
                            Label { text: "File transfer"; color: root.text; font.pixelSize: 13; font.bold: true }
                            UI.MCheckBox { id: overwriteExistingBox; text: "Overwrite duplicate files"; checked: true }
                            RowLayout {
                                Layout.fillWidth: true
                                Label { text: "Parallel transfers"; color: root.muted; Layout.fillWidth: true }
                                UI.MTextField {
                                    id: parallelField
                                    Layout.preferredWidth: 90
                                    text: "4"
                                    inputMethodHints: Qt.ImhDigitsOnly
                                    onAccepted: saveConnectButton.clicked()
                                }
                            }
                            Label { text: "1–8 concurrent transfers. Four is a good default for most servers."; color: root.muted; font.pixelSize: 10; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                        }
                    }

                    Label { id: editorError; Layout.fillWidth: true; color: root.danger; wrapMode: Text.WordWrap; font.pixelSize: 11 }
                    Item { Layout.preferredHeight: 4 }
                }
            }
            Rectangle { Layout.fillWidth: true; height: 1; color: root.border }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 64
                color: "transparent"
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 24
                    anchors.rightMargin: 24
                    spacing: 10
                    Item { Layout.fillWidth: true }
                    UI.MButton { text: "Cancel"; compact: true; Layout.preferredWidth: 92; Layout.preferredHeight: 36; onClicked: sessionEditor.close() }
                    UI.MButton { text: "Save"; compact: true; Layout.preferredWidth: 92; Layout.preferredHeight: 36; onClicked: root.commitSession(false) }
                    UI.MButton { id: saveConnectButton; text: "Save & Connect"; compact: true; primary: true; Layout.preferredWidth: 142; Layout.preferredHeight: 36; onClicked: root.commitSession(true) }
                }
            }
        }
    }

    // ---------- File dialogs ----------
    FileDialog { id: uploadDialog; title: "Select file to upload"; fileMode: FileDialog.OpenFile; onAccepted: fileManager.upload(selectedFile) }
    FolderDialog { id: downloadDialog; title: "Choose download folder"; onAccepted: fileManager.downloadEntry(root.selectedFileIndex, selectedFolder) }

    // ---------- Polished file operation dialogs ----------
    Dialog {
        id: newFolderDialog; modal: true; anchors.centerIn: parent; width: 430; padding: 22; standardButtons: Dialog.NoButton
        background: Rectangle { radius: 16; color: root.panel2; border.color: root.border }
        contentItem: ColumnLayout {
            spacing: 16
            Label { text: "Create folder"; color: root.text; font.pixelSize: 19; font.bold: true }
            Label { text: "A new folder will be created in " + fileManager.currentPath; color: root.muted; wrapMode: Text.WordWrap; Layout.fillWidth: true; font.pixelSize: 10 }
            UI.MTextField { id: folderNameField; Layout.fillWidth: true; placeholderText: "Folder name"; onAccepted: createFolderButton.clicked() }
            RowLayout { Layout.fillWidth: true; Item { Layout.fillWidth: true } UI.MButton { text: "Cancel"; onClicked: newFolderDialog.close() } UI.MButton { id: createFolderButton; text: "Create folder"; primary: true; onClicked: { fileManager.createFolder(folderNameField.text); folderNameField.text = ""; newFolderDialog.close() } } }
        }
        onOpened: folderNameField.forceActiveFocus()
    }

    Dialog {
        id: renameDialog; modal: true; anchors.centerIn: parent; width: 450; padding: 22; standardButtons: Dialog.NoButton
        onOpened: { renameField.forceActiveFocus(); renameField.selectAll() }
        background: Rectangle { radius: 16; color: root.panel2; border.color: root.border }
        contentItem: ColumnLayout {
            spacing: 16
            Label { text: "Rename"; color: root.text; font.pixelSize: 19; font.bold: true }
            Label { text: root.selectedFileName; color: root.muted; elide: Text.ElideMiddle; Layout.fillWidth: true }
            UI.MTextField { id: renameField; Layout.fillWidth: true; placeholderText: "New name"; onAccepted: renameApplyButton.clicked() }
            RowLayout { Layout.fillWidth: true; Item { Layout.fillWidth: true } UI.MButton { text: "Cancel"; onClicked: renameDialog.close() } UI.MButton { id: renameApplyButton; text: "Rename"; primary: true; onClicked: { fileManager.renameEntry(root.selectedFileIndex, renameField.text); renameDialog.close() } } }
        }
    }

    Dialog {
        id: fileDeleteDialog
        modal: true
        anchors.centerIn: parent
        width: 460
        padding: 24
        standardButtons: Dialog.NoButton
        background: Rectangle { radius: 18; color: root.panel2; border.color: "#62383b"; border.width: 1 }
        contentItem: ColumnLayout {
            spacing: 16
            Label { text: root.selectedFileDirectory ? "Delete folder?" : "Delete file?"; color: root.text; font.pixelSize: 20; font.bold: true }
            Label { text: root.selectedFileName; color: root.muted; Layout.fillWidth: true; elide: Text.ElideMiddle }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 56
                radius: 10
                color: "#2a1416"
                border.color: "#6e353b"
                Label {
                    anchors.fill: parent
                    anchors.margins: 11
                    text: root.selectedFileDirectory ? "The folder and all of its contents will be deleted. This cannot be undone." : "This file will be permanently deleted. This cannot be undone."
                    color: root.danger
                    wrapMode: Text.WordWrap
                    font.pixelSize: 10
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Item { Layout.fillWidth: true }
                UI.MButton { text: "Cancel"; onClicked: fileDeleteDialog.close() }
                UI.MButton {
                    id: fileDeleteApplyButton
                    text: "Delete"
                    danger: true
                    onClicked: {
                        fileManager.deleteEntry(root.selectedFileIndex)
                        fileDeleteDialog.close()
                    }
                }
            }
        }
        Shortcut { sequence: "Return"; enabled: fileDeleteDialog.visible; onActivated: fileDeleteApplyButton.clicked() }
        Shortcut { sequence: "Enter"; enabled: fileDeleteDialog.visible; onActivated: fileDeleteApplyButton.clicked() }
    }

    Dialog {
        id: compressDialog
        modal: true
        anchors.centerIn: parent
        width: 470
        padding: 24
        standardButtons: Dialog.NoButton
        background: Rectangle { radius: 18; color: root.panel2; border.color: root.border }
        contentItem: ColumnLayout {
            spacing: 16
            Label { text: "Create ZIP archive"; color: root.text; font.pixelSize: 20; font.bold: true }
            Label {
                Layout.fillWidth: true
                text: "Compress “" + root.selectedFileName + "” in the current folder."
                color: root.muted
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 6
                Label { text: "Archive name"; color: root.muted; font.pixelSize: 11; font.bold: true }
                UI.MTextField {
                    id: archiveNameField
                    Layout.fillWidth: true
                    placeholderText: "archive.zip"
                    onAccepted: compressApplyButton.clicked()
                }
            }
            Label {
                Layout.fillWidth: true
                text: fileManager.remote ? "ZIP is created on the active SSH server." : "ZIP is created on this machine."
                color: root.muted
                font.pixelSize: 10
                wrapMode: Text.WordWrap
            }
            RowLayout {
                Layout.fillWidth: true; spacing: 10
                Item { Layout.fillWidth: true }
                UI.MButton { text: "Cancel"; onClicked: compressDialog.close() }
                UI.MButton {
                    id: compressApplyButton
                    text: "Create ZIP"
                    primary: true
                    onClicked: {
                        fileManager.compressEntry(root.selectedFileIndex, archiveNameField.text)
                        compressDialog.close()
                    }
                }
            }
        }
    }

    Dialog {
        id: extractDialog
        modal: true
        anchors.centerIn: parent
        width: 470
        padding: 24
        standardButtons: Dialog.NoButton
        background: Rectangle { radius: 18; color: root.panel2; border.color: root.border }
        contentItem: ColumnLayout {
            spacing: 16
            Label { text: "Extract ZIP"; color: root.text; font.pixelSize: 20; font.bold: true }
            Label {
                Layout.fillWidth: true
                text: "Extract “" + root.selectedFileName + "” into a new folder."
                color: root.muted
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 6
                Label { text: "Destination folder"; color: root.muted; font.pixelSize: 11; font.bold: true }
                UI.MTextField {
                    id: extractFolderField
                    Layout.fillWidth: true
                    placeholderText: "extracted"
                    onAccepted: extractApplyButton.clicked()
                }
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 54
                radius: 10
                color: "#171d13"
                border.color: "#3b472c"
                Label {
                    anchors.fill: parent; anchors.margins: 10
                    text: "MoriXterm checks archive paths for absolute paths and parent-directory traversal before extraction."
                    color: root.warning
                    font.pixelSize: 10
                    wrapMode: Text.WordWrap
                }
            }
            RowLayout {
                Layout.fillWidth: true; spacing: 10
                Item { Layout.fillWidth: true }
                UI.MButton { text: "Cancel"; onClicked: extractDialog.close() }
                UI.MButton {
                    id: extractApplyButton
                    text: "Extract"
                    primary: true
                    onClicked: {
                        fileManager.extractZipEntry(root.selectedFileIndex, extractFolderField.text)
                        extractDialog.close()
                    }
                }
            }
        }
    }

    Dialog {
        id: chmodDialog; modal: true; anchors.centerIn: parent; width: 560; padding: 24; standardButtons: Dialog.NoButton
        property bool ur: true; property bool uw: true; property bool ux: true
        property bool gr: true; property bool gw: false; property bool gx: true
        property bool orr: true; property bool ow: false; property bool ox: true
        property int specialBits: 0
        function parsePermissions(p) {
            var s = (p || "---------").trim()
            specialBits = 0
            if (/^[0-7]{3,4}$/.test(s)) {
                var offset = s.length === 4 ? 1 : 0
                if (offset === 1) specialBits = parseInt(s[0])
                function fromDigit(ch) { var n=parseInt(ch); return {r:(n&4)!==0,w:(n&2)!==0,x:(n&1)!==0} }
                var u=fromDigit(s[offset]), g=fromDigit(s[offset+1]), o=fromDigit(s[offset+2])
                ur=u.r; uw=u.w; ux=u.x; gr=g.r; gw=g.w; gx=g.x; orr=o.r; ow=o.w; ox=o.x
                return
            }
            if (s.length > 9) s = s.slice(s.length - 9)
            while (s.length < 9) s += "-"
            ur=s[0]==="r"; uw=s[1]==="w"; ux=s[2]==="x" || s[2]==="s"
            gr=s[3]==="r"; gw=s[4]==="w"; gx=s[5]==="x" || s[5]==="s"
            orr=s[6]==="r"; ow=s[7]==="w"; ox=s[8]==="x" || s[8]==="t"
            if (s[2]==="s" || s[2]==="S") specialBits |= 4
            if (s[5]==="s" || s[5]==="S") specialBits |= 2
            if (s[8]==="t" || s[8]==="T") specialBits |= 1
        }
        function octal() {
            function n(r,w,x){ return (r?4:0)+(w?2:0)+(x?1:0) }
            var regular = "" + n(ur,uw,ux) + n(gr,gw,gx) + n(orr,ow,ox)
            return specialBits > 0 ? String(specialBits) + regular : regular
        }
        onOpened: parsePermissions(root.selectedFilePermissions)
        background: Rectangle { radius: 18; color: root.panel2; border.color: root.border }
        Shortcut { sequence: "Return"; enabled: chmodDialog.visible; onActivated: chmodApplyButton.clicked() }
        Shortcut { sequence: "Enter"; enabled: chmodDialog.visible; onActivated: chmodApplyButton.clicked() }
        contentItem: ColumnLayout {
            spacing: 16
            RowLayout {
                Layout.fillWidth: true
                ColumnLayout { Label { text: "Permissions"; color: root.text; font.pixelSize: 20; font.bold: true } Label { text: root.selectedFileName; color: root.muted; font.pixelSize: 11 } }
                Item { Layout.fillWidth: true }
                Rectangle { radius: 8; color: root.accentSoft; implicitWidth: 58; implicitHeight: 34; Label { anchors.centerIn: parent; text: chmodDialog.octal(); color: root.accent; font.bold: true; font.family: "monospace" } }
            }
            Rectangle { Layout.fillWidth: true; height: 1; color: root.border }
            GridLayout {
                columns: 4; columnSpacing: 18; rowSpacing: 10; Layout.fillWidth: true
                Label { text: "" }
                Label { text: "Read"; color: root.muted }
                Label { text: "Write"; color: root.muted }
                Label { text: "Execute"; color: root.muted }
                Label { text: "Owner"; color: root.text; font.bold: true }
                UI.MCheckBox { checked: chmodDialog.ur; onToggled: chmodDialog.ur=checked }
                UI.MCheckBox { checked: chmodDialog.uw; onToggled: chmodDialog.uw=checked }
                UI.MCheckBox { checked: chmodDialog.ux; onToggled: chmodDialog.ux=checked }
                Label { text: "Group"; color: root.text; font.bold: true }
                UI.MCheckBox { checked: chmodDialog.gr; onToggled: chmodDialog.gr=checked }
                UI.MCheckBox { checked: chmodDialog.gw; onToggled: chmodDialog.gw=checked }
                UI.MCheckBox { checked: chmodDialog.gx; onToggled: chmodDialog.gx=checked }
                Label { text: "Others"; color: root.text; font.bold: true }
                UI.MCheckBox { checked: chmodDialog.orr; onToggled: chmodDialog.orr=checked }
                UI.MCheckBox { checked: chmodDialog.ow; onToggled: chmodDialog.ow=checked }
                UI.MCheckBox { checked: chmodDialog.ox; onToggled: chmodDialog.ox=checked }
            }
            Label { text: chmodDialog.specialBits > 0 ? "Special permission bits are preserved. Recursive permission changes are intentionally not exposed to reduce accidental damage." : "Recursive permission changes are intentionally not exposed here to reduce accidental damage."; color: root.muted; font.pixelSize: 10; wrapMode: Text.WordWrap; Layout.fillWidth: true }
            RowLayout { Layout.fillWidth: true; Item { Layout.fillWidth: true } UI.MButton { text: "Cancel"; onClicked: chmodDialog.close() } UI.MButton { id: chmodApplyButton; text: "Apply permissions"; primary: true; onClicked: { fileManager.chmodEntry(root.selectedFileIndex, chmodDialog.octal()); chmodDialog.close() } } }
        }
    }

    Dialog {
        id: chownDialog; modal: true; anchors.centerIn: parent; width: 500; padding: 24; standardButtons: Dialog.NoButton
        onOpened: { ownerField.text = root.selectedFileOwner; groupField.text = root.selectedFileGroup; ownerField.forceActiveFocus(); ownerField.selectAll() }
        background: Rectangle { radius: 18; color: root.panel2; border.color: root.border }
        contentItem: ColumnLayout {
            spacing: 16
            Label { text: "Owner & group"; color: root.text; font.pixelSize: 20; font.bold: true }
            Label { text: root.selectedFileName; color: root.muted; Layout.fillWidth: true; elide: Text.ElideMiddle }
            RowLayout {
                Layout.fillWidth: true; spacing: 10
                ColumnLayout { Layout.fillWidth: true; Label { text: "Owner"; color: root.muted; font.pixelSize: 11 } UI.MTextField { id: ownerField; Layout.fillWidth: true; placeholderText: "user"; onAccepted: chownApplyButton.clicked() } }
                ColumnLayout { Layout.fillWidth: true; Label { text: "Group"; color: root.muted; font.pixelSize: 11 } UI.MTextField { id: groupField; Layout.fillWidth: true; placeholderText: "group"; onAccepted: chownApplyButton.clicked() } }
            }
            Rectangle { Layout.fillWidth: true; implicitHeight: 54; radius: 9; color: "#241f10"; border.color: "#59491e"; Label { anchors.fill: parent; anchors.margins: 10; text: "Changing ownership requires sufficient privileges on the target host. MoriXterm never elevates privileges automatically."; color: root.warning; wrapMode: Text.WordWrap; font.pixelSize: 10 } }
            RowLayout { Layout.fillWidth: true; Item { Layout.fillWidth: true } UI.MButton { text: "Cancel"; onClicked: chownDialog.close() } UI.MButton { id: chownApplyButton; text: "Apply owner"; primary: true; onClicked: { var v=ownerField.text.trim(); if (groupField.text.trim().length) v += ":" + groupField.text.trim(); fileManager.chownEntry(root.selectedFileIndex, v); chownDialog.close() } } }
        }
    }

    // ---------- Session folder dialogs ----------
    Dialog {
        id: sessionFolderDialog; modal: true; anchors.centerIn: parent; width: 430; padding: 22; standardButtons: Dialog.NoButton
        property int folderId: 0
        onOpened: { sessionFolderName.forceActiveFocus(); sessionFolderName.selectAll() }
        background: Rectangle { radius: 16; color: root.panel2; border.color: root.border }
        contentItem: ColumnLayout {
            spacing: 16
            Label { text: sessionFolderDialog.folderId > 0 ? "Rename session folder" : "New session folder"; color: root.text; font.pixelSize: 19; font.bold: true }
            UI.MTextField { id: sessionFolderName; Layout.fillWidth: true; placeholderText: "e.g. Test servers"; onAccepted: sessionFolderApplyButton.clicked() }
            RowLayout { Layout.fillWidth: true; Item { Layout.fillWidth: true } UI.MButton { text: "Cancel"; onClicked: sessionFolderDialog.close() } UI.MButton { id: sessionFolderApplyButton; text: sessionFolderDialog.folderId > 0 ? "Rename" : "Create"; primary: true; onClicked: { var editing = sessionFolderDialog.folderId > 0; var ok = editing ? sessionStore.renameFolder(sessionFolderDialog.folderId, sessionFolderName.text) : sessionStore.createFolder(sessionFolderName.text); if (ok) { root.showToast(editing ? "Session folder renamed." : "Session folder created.", "success"); sessionFolderDialog.close() } else root.showToast(sessionStore.lastError.length ? sessionStore.lastError : "Could not update the session folder.", "error") } } }
        }
    }

    // ---------- Settings ----------
    FolderDialog {
        id: rdpSharedFolderDialog
        title: "Choose folder shared with RDP"
        onAccepted: rdpSharedFolderField.text = selectedFolder.toString()
    }
    Dialog {
        id: settingsDialog; modal: true; anchors.centerIn: parent; width: 650; height: 560; padding: 24; standardButtons: Dialog.NoButton
        background: Rectangle { radius: 18; color: root.panel2; border.color: root.border }
        onOpened: {
            lockEnabledBox.checked=appLock.lockEnabled; lockStartupBox.checked=appLock.lockOnStartup
            timeoutField.text=String(appLock.timeoutMinutes); currentLockPassword.text=""
            newLockPassword.text=""; confirmLockPassword.text=""
            terminalThemeCombo.currentIndex=Math.max(0, root.terminalThemes.indexOf(root.terminalTheme))
            terminalFontSizeField.text=String(root.terminalFontSize)
            rdpDefaultScaleField.text=String(Math.max(100, Math.min(300, rdpSettings.defaultScale)))
            rdpSharedFolderField.text=rdpSettings.sharedFolder
            settingsTabs.currentIndex=0
        }
        contentItem: ColumnLayout {
            spacing: 16
            RowLayout { Layout.fillWidth: true; Label { text: "Settings"; color: root.text; font.pixelSize: 21; font.bold: true } Item { Layout.fillWidth: true } UI.MIconButton { text: "×"; onClicked: settingsDialog.close() } }
            Rectangle { Layout.fillWidth: true; height: 1; color: root.border }
            RowLayout {
                id: settingsTabs
                Layout.fillWidth: true
                property int currentIndex: 0
                spacing: 8
                Repeater {
                    model: ["Security", "Terminal", "RDP", "Storage"]
                    delegate: Button {
                        id: settingsTabButton
                        Layout.fillWidth: true
                        implicitHeight: 40
                        text: modelData
                        hoverEnabled: true
                        onClicked: settingsTabs.currentIndex = index
                        background: Rectangle {
                            radius: 9
                            color: settingsTabs.currentIndex === index
                                   ? root.accentSoft
                                   : (settingsTabButton.hovered ? root.panel3 : "transparent")
                            border.width: settingsTabs.currentIndex === index ? 1 : 0
                            border.color: root.accent
                        }
                        contentItem: Text {
                            text: settingsTabButton.text
                            color: settingsTabs.currentIndex === index ? root.accent : root.muted
                            font.pixelSize: 12
                            font.weight: settingsTabs.currentIndex === index ? Font.DemiBold : Font.Medium
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }
            ScrollView {
                id: settingsScroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                ScrollBar.vertical.policy: ScrollBar.AsNeeded
                contentWidth: availableWidth

                StackLayout {
                    id: settingsPages
                    width: settingsScroll.availableWidth
                    currentIndex: settingsTabs.currentIndex

                ColumnLayout {
                    width: settingsPages.width
                    spacing: 14
                    Label { text: "Application lock"; color: root.text; font.bold: true }
                    Label { text: "Locking hides the UI only. Active SSH, RDP and transfer processes remain alive."; color: root.muted; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                    UI.MCheckBox { id: lockEnabledBox; text: "Auto-lock after inactivity" }
                    UI.MCheckBox { id: lockStartupBox; text: "Require app password on startup" }
                    RowLayout { Layout.fillWidth: true; Label { text: "Idle timeout (minutes)"; color: root.muted; Layout.fillWidth: true } UI.MTextField { id: timeoutField; Layout.preferredWidth: 110; inputMethodHints: Qt.ImhDigitsOnly; onAccepted: applyLockSettingsButton.clicked() } }
                    UI.MButton { id: applyLockSettingsButton; text: "Apply lock settings"; onClicked: { var n=parseInt(timeoutField.text); if (!n) n=10; appLock.timeoutMinutes=n; appLock.lockOnStartup=lockStartupBox.checked; appLock.lockEnabled=lockEnabledBox.checked } }
                    Rectangle { Layout.fillWidth: true; height: 1; color: root.border }
                    Label { text: appLock.hasPassword ? "Change app password" : "Set app password"; color: root.text; font.bold: true }
                    UI.MTextField { id: currentLockPassword; visible: appLock.hasPassword; Layout.fillWidth: true; echoMode: TextInput.Password; placeholderText: "Current password"; onAccepted: setPasswordButton.clicked() }
                    UI.MTextField { id: newLockPassword; Layout.fillWidth: true; echoMode: TextInput.Password; placeholderText: "New password — minimum 8 characters"; onAccepted: setPasswordButton.clicked() }
                    UI.MTextField { id: confirmLockPassword; Layout.fillWidth: true; echoMode: TextInput.Password; placeholderText: "Confirm password"; onAccepted: setPasswordButton.clicked() }
                    RowLayout {
                        Layout.fillWidth: true
                        UI.MButton { id: setPasswordButton; text: appLock.hasPassword ? "Change password" : "Set password"; primary: true; onClicked: { if (newLockPassword.text !== confirmLockPassword.text) { settingsMessage.text="Passwords do not match."; return } appLock.setPassword(currentLockPassword.text,newLockPassword.text); settingsMessage.text=appLock.statusMessage; currentLockPassword.text="";newLockPassword.text="";confirmLockPassword.text="" } }
                        UI.MButton { visible: appLock.hasPassword; text: "Remove password"; danger: true; onClicked: { appLock.removePassword(currentLockPassword.text); settingsMessage.text=appLock.statusMessage } }
                        Item { Layout.fillWidth: true }
                        UI.MButton { visible: appLock.hasPassword; text: "Lock now"; onClicked: { settingsDialog.close(); appLock.lockNow() } }
                    }
                    Label { id: settingsMessage; Layout.fillWidth: true; color: root.muted; wrapMode: Text.WordWrap }
                    Item { Layout.fillHeight: true }
                }

                ColumnLayout {
                    width: settingsPages.width
                    spacing: 14
                    Label { text: "Terminal appearance"; color: root.text; font.bold: true }
                    Label { text: "Choose a built-in ANSI palette. The selection is saved for future sessions."; color: root.muted; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                    RowLayout { Layout.fillWidth: true; Label { text: "Theme"; color: root.muted; Layout.fillWidth: true } UI.MComboBox { id: terminalThemeCombo; Layout.preferredWidth: 220; model: root.terminalThemes } }
                    RowLayout { Layout.fillWidth: true; Label { text: "Font size"; color: root.muted; Layout.fillWidth: true } UI.MTextField { id: terminalFontSizeField; Layout.preferredWidth: 120; inputMethodHints: Qt.ImhDigitsOnly } }
                    UI.MButton {
                        text: "Apply terminal appearance"
                        primary: true
                        onClicked: {
                            var size=parseFloat(terminalFontSizeField.text)
                            if (!isFinite(size)) size=11.5
                            size=Math.max(7, Math.min(32, size))
                            root.terminalFontSize=size
                            terminalSettings.fontSize=size
                            var selected=root.terminalThemes[Math.max(0, terminalThemeCombo.currentIndex)]
                            terminalSettings.themeName=selected
                            root.terminalTheme=selected
                            root.showToast("Terminal appearance updated.", "success")
                        }
                    }
                    Item { Layout.fillHeight: true }
                }

                ColumnLayout {
                    width: settingsPages.width
                    spacing: 14
                    Label { text: "Remote Desktop"; color: root.text; font.bold: true }
                    Label { text: "Display zoom used when you Connect or Reconnect an RDP session (100–300%). Change it here, Apply, then reconnect."; color: root.muted; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                    RowLayout {
                        Layout.fillWidth: true
                        Label { text: "Display zoom"; color: root.muted; Layout.fillWidth: true }
                        UI.MTextField { id: rdpDefaultScaleField; Layout.preferredWidth: 110; inputMethodHints: Qt.ImhDigitsOnly; placeholderText: "100–300" }
                        Label { text: "%"; color: root.muted }
                    }
                    Label { text: "Shared host folder"; color: root.text; font.bold: true }
                    Label { text: "Both sides can read and write this folder. In the remote desktop open " + root.rdpRemoteShare + ". Leave blank to create and share ~/morixterm/share automatically."; color: root.muted; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                    RowLayout {
                        Layout.fillWidth: true
                        UI.MTextField { id: rdpSharedFolderField; Layout.fillWidth: true; placeholderText: "~/morixterm/share (default)" }
                        UI.MButton { text: "Browse…"; iconText: "▣"; onClicked: rdpSharedFolderDialog.open() }
                    }
                    Label { text: "Copy files on your computer, then paste them into a folder in the remote desktop. Clipboard text and files work both ways when the server allows it."; color: root.muted; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                    UI.MButton {
                        text: "Apply RDP settings"
                        primary: true
                        onClicked: {
                            var scale = Number(rdpDefaultScaleField.text)
                            if (!isFinite(scale) || scale < 100 || scale > 300 || Math.floor(scale) !== scale) {
                                root.showToast("RDP zoom must be a whole number between 100 and 300%.", "error")
                                return
                            }
                            rdpSettings.defaultScale = scale
                            rdpSettings.sharedFolder = rdpSharedFolderField.text.trim()
                            for (var i = 0; i < tabsModel.count; ++i) {
                                if (tabsModel.get(i).kind === "rdp")
                                    tabsModel.setProperty(i, "rdpScale", scale)
                            }
                            root.showToast("RDP settings saved. Reconnect active sessions to apply zoom.", "success")
                        }
                    }
                    Item { Layout.fillHeight: true }
                }

                ColumnLayout {
                    width: settingsPages.width
                    spacing: 14
                    Label { text: "Storage & security"; color: root.text; font.bold: true }
                    Label { text: "Profiles: SQLite • Credentials: " + credentialStore.backend; color: root.muted; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                    Label { text: sessionStore.databasePath; color: root.muted; font.pixelSize: 9; elide: Text.ElideMiddle; Layout.fillWidth: true }
                    Item { Layout.fillHeight: true }
                }
                }
            }
        }
    }

    Dialog {
        id: aboutDialog; modal: true; anchors.centerIn: parent; width: 600; padding: 26; standardButtons: Dialog.NoButton
        background: Rectangle { radius: 20; color: root.panel2; border.color: "#2b4638" }
        contentItem: ColumnLayout {
            spacing: 16
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 112
                Layout.preferredHeight: 112
                radius: 26
                color: "#242628"
                border.color: "#2b5a43"
                Image {
                    anchors.fill: parent
                    anchors.margins: 14
                    source: "qrc:/assets/morixtrem-app.png"
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    mipmap: true
                }
            }
            Label { text: "Secure terminal & remote workspace"; color: root.accent; Layout.alignment: Qt.AlignHCenter }
            Rectangle { Layout.fillWidth: true; height: 1; color: root.border }
            GridLayout {
                columns: 2; columnSpacing: 24; rowSpacing: 9; Layout.fillWidth: true
                Label { text: "Version"; color: root.muted } Label { text: appVersion; color: root.text }
                Label { text: "Developer"; color: root.muted } Label { text: "mortenaho"; color: root.text }
                Label { text: "Framework"; color: root.muted } Label { text: "Qt " + qtVersion + " • QML • C++20"; color: root.text }
                Label { text: "Platform"; color: root.muted } Label { text: platformName; color: root.text; elide: Text.ElideRight; Layout.fillWidth: true }
                Label { text: "Architecture"; color: root.muted } Label { text: cpuArchitecture; color: root.text }
                Label { text: "Database"; color: root.muted } Label { text: "SQLite"; color: root.text }
                Label { text: "Credential vault"; color: root.muted } Label { text: credentialStore.backend; color: root.text }
                Label { text: "Repository"; color: root.muted }
                Label {
                    id: repositoryLink
                    text: repositoryUrl
                    color: repoHover.hovered ? root.accent2 : root.accent
                    elide: Text.ElideMiddle
                    Layout.fillWidth: true
                    font.underline: repoHover.hovered
                    HoverHandler { id: repoHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: Qt.openUrlExternally(repositoryUrl) }
                }
            }
            Label { Layout.fillWidth: true; text: "MoriXterm provides local terminal sessions, SSH, RDP, remote file operations, session organization and application locking. Passwords marked as remembered are stored in the operating-system credential vault rather than SQLite."; color: root.muted; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter }
            Label { text: "© 2026 mortenaho • Built with Qt"; color: "#5f786b"; font.pixelSize: 10; Layout.alignment: Qt.AlignHCenter }
            UI.MButton { text: "Close"; primary: true; Layout.alignment: Qt.AlignHCenter; onClicked: aboutDialog.close() }
        }
    }

    // ---------- Context popups ----------
    Popup {
        id: terminalContext
        parent: Overlay.overlay
        width: 225; padding: 6; modal: false; focus: true; closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle { radius: 8; color: "#2a2b2d"; border.color: "#45474a" }
        contentItem: Column {
            spacing: 2
            Rectangle {
                width: parent.width; height: 42; color: "transparent"
                RowLayout { anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; Label { text: ">_"; color: root.accent; font.bold: true } Label { text: "Terminal"; color: root.text; font.bold: true; Layout.fillWidth: true } Label { text: "clipboard"; color: root.muted; font.pixelSize: 9 } }
            }
            Rectangle { width: parent.width; height: 1; color: root.border }
            UI.MContextItem { width: parent.width; iconText: "⧉"; text: "Copy"; shortcutText: "Ctrl+Shift+C"; onClicked: { if(root.activeTerminal) root.activeTerminal.copySelection(); terminalContext.close() } }
            UI.MContextItem { width: parent.width; iconText: "▣"; text: "Paste"; shortcutText: "Ctrl+Shift+V"; onClicked: { if(root.activeTerminal) root.activeTerminal.pasteClipboard(); terminalContext.close() } }
            Rectangle { width: parent.width; height: 1; color: root.border }
            UI.MContextItem { width: parent.width; iconText: "◩"; text: "Select all"; onClicked: { if(root.activeTerminal) root.activeTerminal.selectAll(); terminalContext.close() } }
            UI.MContextItem { width: parent.width; iconText: "⌫"; text: "Clear terminal"; onClicked: { if(root.activeTerminal) root.activeTerminal.clearTerminal(); terminalContext.close() } }
        }
    }

    Popup {
        id: fileContext
        parent: Overlay.overlay
        width: 286; padding: 6; modal: false; focus: true; closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        property real maximumMenuHeight: Overlay.overlay ? Math.max(180, Overlay.overlay.height - 24) : 620
        height: Math.min(fileContextColumn.implicitHeight + topPadding + bottomPadding, maximumMenuHeight)
        background: Rectangle { radius: 8; color: "#2a2b2d"; border.color: "#45474a" }
        contentItem: ScrollView {
            id: fileContextScroll
            clip: true
            contentWidth: availableWidth
            ScrollBar.vertical.policy: ScrollBar.AsNeeded
            Column {
                id: fileContextColumn
                width: fileContextScroll.availableWidth
                spacing: 2
                Rectangle {
                width: parent.width; height: 54; color: "transparent"
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 9
                    Rectangle {
                        width: 32; height: 32; radius: 6; color: "#343638"
                        Image { anchors.centerIn: parent; width: 20; height: 20; source: root.fileIconSource(root.selectedFileName, root.selectedFileDirectory); fillMode: Image.PreserveAspectFit; smooth: true }
                    }
                    ColumnLayout { Layout.fillWidth: true; spacing: 0; Label { text: root.selectedFileName.length ? root.selectedFileName : "Current folder"; color: root.text; font.bold: true; elide: Text.ElideMiddle; Layout.fillWidth: true } Label { text: root.selectedFileIndex >= 0 ? ((root.selectedFileOwner || "—") + (root.selectedFileGroup.length ? ":" + root.selectedFileGroup : "") + "  •  " + root.selectedFilePermissions) : fileManager.currentPath; color: root.muted; font.pixelSize: 9; elide: Text.ElideMiddle; Layout.fillWidth: true } }
                }
            }
            Rectangle { width: parent.width; height: 1; color: root.border }
            UI.MContextItem { width: parent.width; iconText: "↳"; text: "Open folder"; enabled: root.selectedFileDirectory; onClicked: { fileManager.openEntry(root.selectedFileIndex); fileContext.close() } }
            UI.MContextItem { width: parent.width; iconText: "⇩"; text: "Download…"; enabled: root.selectedFileIndex >= 0; onClicked: { downloadDialog.open(); fileContext.close() } }
            UI.MContextItem { width: parent.width; iconText: "⇧"; text: "Upload here…"; onClicked: { uploadDialog.open(); fileContext.close() } }
            UI.MContextItem { width: parent.width; iconText: "+"; text: "New folder…"; onClicked: { newFolderDialog.open(); fileContext.close() } }
            Rectangle { width: parent.width; height: 1; color: root.border }
            UI.MContextItem { width: parent.width; iconText: "⧉"; text: "Copy"; shortcutText: "Ctrl+C"; enabled: root.selectedFileIndex >= 0; onClicked: { fileManager.copyEntry(root.selectedFileIndex); fileContext.close() } }
            UI.MContextItem { width: parent.width; iconText: "✂"; text: "Cut"; shortcutText: "Ctrl+X"; enabled: root.selectedFileIndex >= 0; onClicked: { fileManager.cutEntry(root.selectedFileIndex); fileContext.close() } }
            UI.MContextItem { width: parent.width; iconText: "▣"; text: fileManager.clipboardCut ? "Move here" : "Paste here"; shortcutText: "Ctrl+V"; enabled: fileManager.hasClipboardEntry; onClicked: { fileManager.pasteEntry(); fileContext.close() } }
            Rectangle { width: parent.width; height: 1; color: root.border }
            UI.MContextItem { width: parent.width; iconText: "Z"; text: "Compress to ZIP…"; enabled: root.selectedFileIndex >= 0 && !fileManager.busy; onClicked: { fileContext.close(); root.showCompressDialog() } }
            UI.MContextItem { width: parent.width; iconText: "↓"; text: "Extract ZIP…"; enabled: root.selectedFileIndex >= 0 && !root.selectedFileDirectory && root.selectedFileName.toLowerCase().endsWith(".zip") && !fileManager.busy; onClicked: { fileContext.close(); root.showExtractDialog() } }
            Rectangle { width: parent.width; height: 1; color: root.border }
            UI.MContextItem { width: parent.width; iconText: "✎"; text: "Rename…"; enabled: root.selectedFileIndex >= 0; onClicked: { renameField.text=root.selectedFileName; renameDialog.open(); fileContext.close() } }
            UI.MContextItem { width: parent.width; iconText: "⌘"; text: "Permissions…"; enabled: root.selectedFileIndex >= 0; onClicked: { chmodDialog.open(); fileContext.close() } }
            UI.MContextItem { width: parent.width; iconText: "◉"; text: "Owner & group…"; enabled: root.selectedFileIndex >= 0; onClicked: { chownDialog.open(); fileContext.close() } }
            Rectangle { width: parent.width; height: 1; color: root.border }
            UI.MContextItem { width: parent.width; iconText: "×"; text: "Delete…"; danger: true; enabled: root.selectedFileIndex >= 0 && !fileManager.busy; onClicked: { fileContext.close(); fileDeleteDialog.open() } }
                Rectangle { width: parent.width; height: 1; color: root.border }
                UI.MContextItem { width: parent.width; iconText: "↻"; text: "Refresh"; onClicked: { fileManager.refresh(); fileContext.close() } }
            }
        }
    }

    Popup {
        id: sessionContext
        parent: Overlay.overlay
        width: 220; padding: 6; modal: false; focus: true; closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        property var payload: null
        background: Rectangle { radius: 8; color: "#2a2b2d"; border.color: "#45474a" }
        contentItem: Column {
            spacing: 2
            UI.MContextItem { width: parent.width; text: "Connect"; onClicked: { var p=sessionContext.payload; if(p) root.openSavedSession(p.sessionId,p.name,p.kind,p.host,p.user,p.port,p.securityProfile,p.keyFile,p.domain,p.rdpWidth,p.rdpHeight,p.fullscreen,p.ignoreCertificate,p.ftpTls,p.ftpPassive,p.overwriteExisting,p.maxParallel,p.rdpScale); sessionContext.close() } }
            UI.MContextItem { width: parent.width; text: "Edit…"; onClicked: { var p=sessionContext.payload; if(p) root.showEditSession(p.sessionId,p.name,p.kind,p.host,p.user,p.port,p.securityProfile,p.keyFile,p.credentialSaved,p.folderId,p.domain,p.rdpWidth,p.rdpHeight,p.fullscreen,p.ignoreCertificate,p.ftpTls,p.ftpPassive,p.overwriteExisting,p.maxParallel,p.rdpScale); sessionContext.close() } }
            UI.MContextItem { width: parent.width; text: "Move to ungrouped"; enabled: sessionContext.payload && Number(sessionContext.payload.folderId)>0; onClicked: { var ok=sessionStore.moveSessionToFolder(sessionContext.payload.sessionId,0); if(ok) root.showToast("Session moved to Ungrouped.", "success"); else root.showToast(sessionStore.lastError.length ? sessionStore.lastError : "Could not move the session.", "error"); sessionContext.close() } }
            Rectangle { width: parent.width; height: 1; color: root.border }
            UI.MContextItem { width: parent.width; text: "Delete session"; danger: true; onClicked: { sessionStore.removeSessionById(sessionContext.payload.sessionId); sessionContext.close() } }
        }
    }

    Popup {
        id: folderContext
        parent: Overlay.overlay
        width: 210; padding: 6; modal: false; focus: true; closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle { radius: 8; color: "#2a2b2d"; border.color: "#45474a" }
        contentItem: Column {
            spacing: 2
            UI.MContextItem { width: parent.width; text: "Rename folder…"; onClicked: { sessionFolderDialog.folderId=root.contextFolderId; sessionFolderName.text=root.contextFolderName; sessionFolderDialog.open(); folderContext.close() } }
            UI.MContextItem { width: parent.width; text: "Delete folder"; danger: true; onClicked: { var ok=sessionStore.deleteFolder(root.contextFolderId); if(ok) root.showToast("Session folder deleted. Sessions moved to Ungrouped.", "success"); else root.showToast(sessionStore.lastError.length ? sessionStore.lastError : "Could not delete the session folder.", "error"); folderContext.close() } }
        }
    }

    // ---------- Main layout ----------
    RowLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            id: sessionsSidebar
            Layout.preferredWidth: uiSettings.sessionsSidebarWidth
            Layout.minimumWidth: 205
            Layout.maximumWidth: 290
            Layout.fillHeight: true
            color: "#202123"
            border.color: "#343638"

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                // Compact session toolbar inspired by classic remote-client trees.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 42
                    color: "#292a2c"
                    border.color: "#3a3c3f"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 8
                        spacing: 4

                        Label {
                            text: "Sessions"
                            color: root.text
                            font.pixelSize: 16
                            font.weight: Font.DemiBold
                        }
                        Item { Layout.fillWidth: true }

                        UI.MIconButton {
                            Layout.preferredWidth: 30
                            Layout.preferredHeight: 30
                            iconName: "plus"
                            tip: "New connection"
                            onClicked: root.showNewSession("ssh")
                        }
                        UI.MIconButton {
                            Layout.preferredWidth: 30
                            Layout.preferredHeight: 30
                            iconName: "files"
                            tip: "New session folder"
                            onClicked: {
                                sessionFolderDialog.folderId = 0
                                sessionFolderName.text = ""
                                sessionFolderDialog.open()
                            }
                        }
                        UI.MIconButton {
                            Layout.preferredWidth: 30
                            Layout.preferredHeight: 30
                            iconName: "terminal"
                            tip: "Open local terminal"
                            onClicked: root.openLocal()
                        }
                        UI.MIconButton {
                            Layout.preferredWidth: 30
                            Layout.preferredHeight: 30
                            visible: appLock.hasPassword
                            iconName: "lock"
                            tip: "Lock application"
                            onClicked: appLock.lockNow()
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 27
                    color: "#252628"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 11
                        anchors.rightMargin: 9
                        spacing: 6
                        Label {
                            text: "USER SESSIONS"
                            color: "#6f8579"
                            font.pixelSize: 11
                            font.bold: true
                            font.letterSpacing: 0.7
                        }
                        Item { Layout.fillWidth: true }
                        Label {
                            text: sessionList.count
                            color: "#4f665a"
                            font.pixelSize: 11
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: "#36383a" }

                ListView {
                    id: sessionList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 0
                    boundsBehavior: Flickable.StopAtBounds
                    model: sessionStore

                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                        width: 5
                    }

                    delegate: Rectangle {
                        id: sessionRow
                        required property int index
                        required property bool isFolder
                        required property var itemId
                        required property var sessionId
                        required property var folderId
                        required property string name
                        required property string kind
                        required property string host
                        required property string user
                        required property int port
                        required property string domain
                        required property int rdpWidth
                        required property int rdpHeight
                        required property int rdpScale
                        required property bool fullscreen
                        required property bool ignoreCertificate
                        required property string securityProfile
                        required property string keyFile
                        required property bool credentialSaved
                        required property bool ftpTls
                        required property bool ftpPassive
                        required property bool overwriteExisting
                        required property int maxParallel
                        required property int depth
                        required property bool expanded
                        required property int childCount

                        property var sessionPayload: ({
                            sessionId: Number(sessionId), folderId: Number(folderId), name: name, kind: kind, host: host,
                            user: user, port: port, domain: domain, rdpWidth: rdpWidth, rdpHeight: rdpHeight, rdpScale: rdpScale,
                            fullscreen: fullscreen, ignoreCertificate: ignoreCertificate, securityProfile: securityProfile,
                            keyFile: keyFile, credentialSaved: credentialSaved, ftpTls: ftpTls, ftpPassive: ftpPassive,
                            overwriteExisting: overwriteExisting, maxParallel: maxParallel
                        })
                        property bool activeSession: !isFolder && root.currentTab >= 0 && root.currentTab < tabsModel.count
                                                     && Number(tabsModel.get(root.currentTab).sessionId) === Number(sessionId)

                        height: isFolder ? 38 : 52
                        width: sessionList.width
                        color: root.draggingSession && sessionRow.isFolder && root.dragTargetFolderId === Number(sessionRow.itemId)
                               ? "#33473f"
                               : (activeSession ? "#303936" : (sessionHover.hovered ? "#2b2d2f" : "transparent"))
                        border.width: 0

                        Rectangle {
                            visible: sessionRow.activeSession || (root.draggingSession && sessionRow.isFolder && root.dragTargetFolderId === Number(sessionRow.itemId))
                            width: 3
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            color: root.accent
                        }

                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: 1
                            color: "#2c2e30"
                        }

                        HoverHandler {
                            id: sessionHover
                            cursorShape: Qt.PointingHandCursor
                        }

                        MouseArea {
                            id: sessionMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            preventStealing: true

                            property real pressX: 0
                            property real pressY: 0
                            property bool dragStarted: false
                            property bool suppressClick: false

                            onPressed: function(mouse) {
                                if (mouse.button !== Qt.LeftButton || sessionRow.isFolder)
                                    return
                                pressX = mouse.x
                                pressY = mouse.y
                                dragStarted = false
                                suppressClick = false
                            }

                            onPositionChanged: function(mouse) {
                                if (sessionRow.isFolder || !(mouse.buttons & Qt.LeftButton))
                                    return

                                var dx = mouse.x - pressX
                                var dy = mouse.y - pressY
                                if (!dragStarted && (dx * dx + dy * dy) >= 49) {
                                    dragStarted = true
                                    suppressClick = true
                                    root.beginSessionDrag(Number(sessionRow.sessionId), sessionRow.name)
                                }

                                if (dragStarted)
                                    root.updateSessionDragTarget(sessionRow, mouse.x, mouse.y)
                            }

                            onReleased: function(mouse) {
                                if (mouse.button !== Qt.LeftButton || !dragStarted)
                                    return
                                // Hit-test once more at the release point, then move the
                                // session. This does not depend on a Qt DropEvent.
                                root.updateSessionDragTarget(sessionRow, mouse.x, mouse.y)
                                root.finishSessionDrag()
                                dragStarted = false
                            }

                            onCanceled: {
                                if (dragStarted || root.draggingSession)
                                    root.cancelSessionDrag()
                                dragStarted = false
                                suppressClick = false
                            }

                            onClicked: function(mouse) {
                                if (suppressClick) {
                                    suppressClick = false
                                    return
                                }
                                if (mouse.button === Qt.RightButton) {
                                    if (sessionRow.isFolder) {
                                        root.contextFolderId = Number(sessionRow.itemId)
                                        root.contextFolderName = sessionRow.name
                                        root.openAdaptiveContextPopup(folderContext, sessionRow, mouse.x, mouse.y)
                                    } else {
                                        sessionContext.payload = sessionRow.sessionPayload
                                        root.openAdaptiveContextPopup(sessionContext, sessionRow, mouse.x, mouse.y)
                                    }
                                    return
                                }
                                if (sessionRow.isFolder)
                                    sessionStore.toggleFolder(Number(sessionRow.itemId))
                            }

                            onDoubleClicked: function(mouse) {
                                if (mouse.button !== Qt.LeftButton || sessionRow.isFolder || suppressClick)
                                    return
                                var p = sessionRow.sessionPayload
                                root.openSavedSession(p.sessionId,p.name,p.kind,p.host,p.user,p.port,p.securityProfile,p.keyFile,p.domain,p.rdpWidth,p.rdpHeight,p.fullscreen,p.ignoreCertificate,p.ftpTls,p.ftpPassive,p.overwriteExisting,p.maxParallel,p.rdpScale)
                            }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 9 + sessionRow.depth * 14
                            anchors.rightMargin: 8
                            spacing: 7

                            Label {
                                visible: sessionRow.isFolder
                                Layout.preferredWidth: 12
                                text: sessionRow.expanded ? "▾" : "▸"
                                color: (root.draggingSession && root.dragTargetFolderId === Number(sessionRow.itemId)) ? root.accent : "#7c9186"
                                font.pixelSize: 12
                                horizontalAlignment: Text.AlignHCenter
                            }

                            Rectangle {
                                Layout.preferredWidth: sessionRow.isFolder ? 26 : 32
                                Layout.preferredHeight: sessionRow.isFolder ? 26 : 32
                                radius: sessionRow.isFolder ? 5 : 7
                                color: sessionRow.isFolder
                                       ? ((root.draggingSession && root.dragTargetFolderId === Number(sessionRow.itemId)) ? "#1a5138" : "#2b2d2f")
                                       : (sessionRow.activeSession ? "#30483e" : "#292c2e")
                                border.width: sessionRow.activeSession && !sessionRow.isFolder ? 1 : 0
                                border.color: "#3c8d64"

                                Label {
                                    anchors.centerIn: parent
                                    text: sessionRow.isFolder ? "▰"
                                          : (sessionRow.kind === "rdp" ? "R"
                                          : (sessionRow.kind === "ftp" ? "F"
                                          : (sessionRow.kind === "sftp" ? "SF" : ">_")))
                                    color: sessionRow.isFolder ? "#8aa096" : root.accent
                                    font.pixelSize: sessionRow.kind === "sftp" ? 9 : 12
                                    font.bold: true
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                Label {
                                    Layout.fillWidth: true
                                    text: sessionRow.name
                                    color: sessionRow.activeSession ? "#ecfff5" : root.text
                                    font.pixelSize: sessionRow.isFolder ? 13 : 13
                                    font.weight: sessionRow.isFolder ? Font.DemiBold : Font.Medium
                                    elide: Text.ElideRight
                                }

                                Text {
                                    visible: !sessionRow.isFolder
                                    Layout.fillWidth: true
                                    text: root.sessionEndpointHtml(sessionRow.user, sessionRow.host, sessionRow.port)
                                    textFormat: Text.RichText
                                    color: sessionRow.activeSession ? "#b1e8cc" : root.muted
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                }

                                Label {
                                    visible: sessionRow.isFolder
                                    Layout.fillWidth: true
                                    text: sessionRow.childCount + (sessionRow.childCount === 1 ? " session" : " sessions")
                                    color: (root.draggingSession && root.dragTargetFolderId === Number(sessionRow.itemId)) ? root.accent : "#566b60"
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                }
                            }

                            Rectangle {
                                visible: !sessionRow.isFolder
                                Layout.preferredWidth: 29
                                Layout.preferredHeight: 17
                                radius: 4
                                color: "#101b16"
                                border.width: 1
                                border.color: "#21382c"
                                Label {
                                    anchors.centerIn: parent
                                    text: sessionRow.kind.toUpperCase()
                                    color: "#71877b"
                                    font.pixelSize: sessionRow.kind === "sftp" ? 8 : 9
                                    font.bold: true
                                }
                            }

                            Label {
                                visible: !sessionRow.isFolder && sessionRow.credentialSaved
                                text: "●"
                                color: "#5fd99b"
                                font.pixelSize: 7
                                ToolTip.visible: credHover.hovered
                                ToolTip.text: "Credential stored in OS vault"
                                HoverHandler { id: credHover }
                            }

                            Label {
                                visible: sessionRow.isFolder && root.draggingSession && root.dragTargetFolderId === Number(sessionRow.itemId)
                                text: "DROP"
                                color: root.accent
                                font.pixelSize: 8
                                font.bold: true
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    color: "#252628"
                    border.color: "#36383a"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 7
                        anchors.rightMargin: 8
                        spacing: 2
                        UI.MIconButton {
                            Layout.preferredWidth: 29
                            Layout.preferredHeight: 29
                            text: "⚙"
                            tip: "Settings"
                            onClicked: settingsDialog.open()
                        }
                        UI.MIconButton {
                            Layout.preferredWidth: 29
                            Layout.preferredHeight: 29
                            text: "?"
                            tip: "About"
                            onClicked: aboutDialog.open()
                        }
                        Item { Layout.fillWidth: true }
                        Label {
                            text: "v" + appVersion
                            color: "#4f6459"
                            font.pixelSize: 10
                        }
                    }
                }
            }
        }

        Rectangle {
            id: sessionsSidebarResizeHandle
            Layout.preferredWidth: 7
            Layout.fillHeight: true
            color: sessionsSidebarResizeMouse.pressed ? root.accent : (sessionsSidebarResizeHover.hovered ? root.accentSoft : "#292b2d")

            HoverHandler {
                id: sessionsSidebarResizeHover
                cursorShape: Qt.SizeHorCursor
            }
            MouseArea {
                id: sessionsSidebarResizeMouse
                anchors.fill: parent
                cursorShape: Qt.SizeHorCursor
                property real startX: 0
                property real startWidth: 0
                onPressed: {
                    startX = mouse.x
                    startWidth = uiSettings.sessionsSidebarWidth
                }
                onPositionChanged: {
                    if (!pressed) return
                    uiSettings.sessionsSidebarWidth = Math.max(205, Math.min(420, startWidth + mouse.x - startX))
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true; Layout.fillHeight: true; spacing: 0

            // Command bar — compact desktop toolbar with consistent visual rhythm.
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 72
                color: "#242627"
                border.color: "#343738"

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 1
                    color: "#151717"
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 18
                    anchors.rightMargin: 20
                    anchors.topMargin: 5
                    anchors.bottomMargin: 5
                    spacing: 4

                    UI.MTopToolButton {
                        iconName: "session"
                        label: "Session"
                        tip: "Create a new SSH, RDP, SFTP or FTP session"
                        onClicked: root.showNewSession("ssh")
                    }
                    UI.MTopToolButton {
                        iconName: "files"
                        label: "Files"
                        property string activeKind: root.currentTab >= 0 && root.currentTab < tabsModel.count ? tabsModel.get(root.currentTab).kind : ""
                        tip: activeKind === "ftp" || activeKind === "sftp" ? "File workspace is already open" : (root.filePanelVisible ? "Hide file manager" : "Show file manager")
                        enabled: root.currentTab >= 0 && activeKind !== "rdp"
                        active: (activeKind === "ftp" || activeKind === "sftp") || (root.filePanelVisible && root.fileManagerAvailable)
                        onClicked: {
                            if (activeKind !== "ftp" && activeKind !== "sftp")
                                root.filePanelVisible = !root.filePanelVisible
                        }
                    }

                    Rectangle { Layout.preferredWidth: 1; Layout.preferredHeight: 40; Layout.leftMargin: 4; Layout.rightMargin: 4; color: "#3a3d3d" }

                    UI.MTopToolButton {
                        iconName: "fullscreen"
                        label: "Fullscreen"
                        tip: root.appFullscreen ? "Exit fullscreen" : "Enter fullscreen"
                        active: root.appFullscreen
                        onClicked: root.toggleFullscreen()
                    }
                    UI.MTopToolButton {
                        iconName: "disconnect"
                        label: "Disconnect"
                        tip: "Close the active session"
                        danger: true
                        enabled: root.currentTab >= 0
                        onClicked: root.closeTab(root.currentTab)
                    }

                    Rectangle { Layout.preferredWidth: 1; Layout.preferredHeight: 40; Layout.leftMargin: 4; Layout.rightMargin: 4; color: "#3a3d3d" }

                    UI.MTopToolButton {
                        iconName: "info"
                        label: "About"
                        tip: "About MoriXterm"
                        onClicked: aboutDialog.open()
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        visible: root.currentTab >= 0 && root.currentTab < tabsModel.count
                        Layout.preferredWidth: Math.min(330, Math.max(210, sessionTitle.implicitWidth + 92))
                        Layout.preferredHeight: 46
                        radius: 12
                        color: "#202322"
                        border.color: "#343a37"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 10
                            Rectangle {
                                Layout.preferredWidth: 30
                                Layout.preferredHeight: 30
                                radius: 8
                                color: "#263b32"
                                UI.MVectorIcon {
                                    anchors.centerIn: parent
                                    width: 18; height: 18
                                    name: root.currentTab >= 0 && root.currentTab < tabsModel.count ? tabsModel.get(root.currentTab).kind : "terminal"
                                    color: root.accent
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Label {
                                    id: sessionTitle
                                    Layout.fillWidth: true
                                    text: root.currentTab >= 0 && root.currentTab < tabsModel.count ? tabsModel.get(root.currentTab).title : ""
                                    color: "#e9edeb"
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }
                                Label {
                                    Layout.fillWidth: true
                                    text: root.currentTab >= 0 && root.currentTab < tabsModel.count
                                          ? tabsModel.get(root.currentTab).kind.toUpperCase() + " workspace" : ""
                                    color: "#76807c"
                                    font.pixelSize: 9
                                }
                            }
                        }
                    }
                }
            }

            // Session tabs — roomy enough to read, compact enough for many sessions.
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 50
                color: "#1f2122"
                border.color: "#343738"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    anchors.topMargin: 6
                    anchors.bottomMargin: 6
                    spacing: 8

                    AbstractButton {
                        id: homeTabButton
                        Layout.preferredWidth: 38
                        Layout.preferredHeight: 36
                        hoverEnabled: true
                        onClicked: root.pageMode = "home"
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        contentItem: Item {
                            UI.MVectorIcon {
                                anchors.centerIn: parent
                                width: 18; height: 18
                                name: "home"
                                color: homeTabButton.hovered || root.pageMode === "home" ? root.accent : "#89918e"
                            }
                        }
                        background: Rectangle {
                            radius: 9
                            color: root.pageMode === "home" ? "#28352f" : (homeTabButton.hovered ? "#292c2b" : "transparent")
                            border.width: root.pageMode === "home" ? 1 : 0
                            border.color: "#355c4b"
                        }
                    }

                    Rectangle { Layout.preferredWidth: 1; Layout.preferredHeight: 28; color: "#363a39" }

                    Flickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentWidth: tabRow.width
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        Row {
                            id: tabRow
                            height: parent.height
                            spacing: 6

                            Repeater {
                                model: tabsModel
                                delegate: Rectangle {
                                    required property int index
                                    required property string title
                                    required property string kind
                                    property bool selected: root.pageMode === "workspace" && root.currentTab === index

                                    width: Math.min(245, Math.max(154, tabLabel.implicitWidth + 82))
                                    height: 36
                                    anchors.verticalCenter: parent.verticalCenter
                                    radius: 10
                                    color: selected ? "#29332f" : (tabMouse.containsMouse ? "#292c2b" : "#232526")
                                    border.width: selected ? 1 : 0
                                    border.color: selected ? "#38644f" : "transparent"

                                    Rectangle {
                                        visible: selected
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        anchors.leftMargin: 11
                                        anchors.rightMargin: 11
                                        height: 2
                                        radius: 1
                                        color: root.accent
                                    }

                                    MouseArea {
                                        id: tabMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: { root.currentTab = index; root.pageMode = "workspace" }
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 6
                                        spacing: 8

                                        Rectangle {
                                            Layout.preferredWidth: 24
                                            Layout.preferredHeight: 24
                                            radius: 7
                                            color: selected ? "#30483d" : "#2d302f"
                                            UI.MVectorIcon {
                                                anchors.centerIn: parent
                                                width: 15; height: 15
                                                name: kind
                                                color: selected ? root.accent2 : "#8f9995"
                                                strokeWidth: 2.0
                                            }
                                        }
                                        Label {
                                            id: tabLabel
                                            text: title
                                            color: selected ? "#f0f4f2" : "#b8bebc"
                                            font.pixelSize: 11
                                            font.weight: selected ? Font.DemiBold : Font.Normal
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                        AbstractButton {
                                            id: closeTabButton
                                            Layout.preferredWidth: 24
                                            Layout.preferredHeight: 24
                                            hoverEnabled: true
                                            onClicked: root.closeTab(index)
                                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                                            contentItem: Item {
                                                UI.MVectorIcon {
                                                    anchors.centerIn: parent
                                                    width: 13; height: 13
                                                    name: "close"
                                                    color: closeTabButton.hovered ? "#ff858c" : "#6f7774"
                                                    strokeWidth: 2.0
                                                }
                                            }
                                            background: Rectangle {
                                                radius: 6
                                                color: closeTabButton.hovered ? "#3b292c" : "transparent"
                                            }
                                        }
                                    }
                                }
                            }

                            AbstractButton {
                                id: addTabButton
                                width: 34; height: 34
                                anchors.verticalCenter: parent.verticalCenter
                                hoverEnabled: true
                                onClicked: root.showNewSession("ssh")
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                contentItem: Item {
                                    UI.MVectorIcon {
                                        anchors.centerIn: parent
                                        width: 16; height: 16
                                        name: "plus"
                                        color: addTabButton.hovered ? root.accent : "#7d8582"
                                    }
                                }
                                background: Rectangle {
                                    radius: 9
                                    color: addTabButton.hovered ? "#29312e" : "transparent"
                                }
                            }
                        }
                    }
                }
            }

            Item {
                Layout.fillWidth: true; Layout.fillHeight: true

                // HOME — intentionally calm and uncluttered
                Flickable {
                    visible: root.pageMode === "home"
                    anchors.fill: parent
                    contentHeight: homeColumn.implicitHeight + 96
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    ColumnLayout {
                        id: homeColumn
                        width: Math.max(720, Math.min(parent.width - 96, 1040))
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 50
                        spacing: 28

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 220
                            radius: 24
                            clip: true
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: "#303234" }
                                GradientStop { position: 0.62; color: "#252729" }
                                GradientStop { position: 1.0; color: "#202224" }
                            }
                            border.color: "#28523f"

                            Rectangle {
                                width: 330; height: 330; radius: 165
                                x: parent.width - 210; y: -170
                                color: root.accent; opacity: 0.045
                            }
                            Rectangle {
                                width: 260; height: 260; radius: 130
                                x: parent.width - 390; y: 130
                                color: "#39bfff"; opacity: 0.035
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 34
                                anchors.rightMargin: 34
                                anchors.topMargin: 28
                                anchors.bottomMargin: 28
                                spacing: 36

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 10
                                    Label { text: "MORIXTERM"; color: root.accent; font.pixelSize: 11; font.bold: true; font.letterSpacing: 1.8 }
                                    Label { text: "Your remote workspace"; color: "#f2fff8"; font.pixelSize: 34; font.bold: true }
                                    Label {
                                        Layout.maximumWidth: 600
                                        text: "Open SSH, RDP or a local shell. Your saved sessions stay organized in the sidebar."
                                        color: "#91aa9e"; font.pixelSize: 13; wrapMode: Text.WordWrap
                                    }
                                    Item { Layout.preferredHeight: 6 }
                                    RowLayout {
                                        spacing: 10
                                        UI.MButton { text: "New connection"; iconText: "+"; primary: true; onClicked: root.showNewSession("ssh") }
                                        UI.MButton { text: "Local terminal"; iconText: ">_"; onClicked: root.openLocal() }
                                    }
                                }

                                Image {
                                    Layout.preferredWidth: 172
                                    Layout.preferredHeight: 172
                                    source: "qrc:/assets/morixtrem-app.png"
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                    mipmap: true
                                    opacity: 0.96
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12
                            Label { text: "Recent connections"; color: root.text; font.pixelSize: 18; font.bold: true }
                            Label { text: root.recentSessionsCache.length > 0 ? "Quickly reopen a recent session" : "Your recent sessions will appear here"; color: root.muted; font.pixelSize: 11 }
                            Item { Layout.fillWidth: true }
                            Rectangle {
                                implicitWidth: securityStatus.implicitWidth + 20
                                implicitHeight: 28
                                radius: 14
                                color: "#292b2d"
                                border.color: "#244635"
                                Label {
                                    id: securityStatus
                                    anchors.centerIn: parent
                                    text: credentialStore.available ? "Credentials • OS vault" : "Credential vault unavailable"
                                    color: credentialStore.available ? root.accent : root.warning
                                    font.pixelSize: 10
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.recentSessionsCache.length === 0 ? 150 : Math.max(96, recentFlow.implicitHeight + 28)
                            radius: 18
                            color: root.panel2
                            border.color: root.border

                            Flow {
                                id: recentFlow
                                anchors.fill: parent
                                anchors.margins: 14
                                spacing: 10
                                Repeater {
                                    model: root.recentSessionsCache
                                    delegate: Rectangle {
                                        required property var modelData
                                        width: 300
                                        height: 70
                                        radius: 12
                                        color: recentMouse.containsMouse ? "#303234" : "#26282a"
                                        border.color: recentMouse.containsMouse ? "#4d6a5e" : "#3a3d40"
                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 12
                                            spacing: 11
                                            Rectangle {
                                                width: 38; height: 38; radius: 10; color: root.accentSoft
                                                Label { anchors.centerIn: parent; text: modelData.kind === "rdp" ? "R" : (modelData.kind === "ftp" ? "F" : (modelData.kind === "sftp" ? "SF" : "S")); color: root.accent; font.bold: true }
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true; spacing: 2
                                                Label { text: modelData.name; color: root.text; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
                                                Label { text: modelData.host + ":" + modelData.port; color: root.muted; font.pixelSize: 10; elide: Text.ElideRight; Layout.fillWidth: true }
                                            }
                                            Label { text: "›"; color: root.muted; font.pixelSize: 18 }
                                        }
                                        MouseArea {
                                            id: recentMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.openSavedSession(modelData.sessionId,modelData.name,modelData.kind,modelData.host,modelData.user,modelData.port,modelData.securityProfile,modelData.keyFile,modelData.domain,modelData.rdpWidth,modelData.rdpHeight,modelData.fullscreen,modelData.ignoreCertificate,modelData.ftpTls,modelData.ftpPassive,modelData.overwriteExisting,modelData.maxParallel,modelData.rdpScale)
                                        }
                                    }
                                }
                            }

                            ColumnLayout {
                                visible: root.recentSessionsCache.length === 0
                                anchors.centerIn: parent
                                spacing: 7
                                Label { text: "No recent connections"; color: root.text; font.pixelSize: 16; font.bold: true; Layout.alignment: Qt.AlignHCenter }
                                Label { text: "Create an SSH, RDP, SFTP or FTP profile, or start a local terminal."; color: root.muted; font.pixelSize: 11; Layout.alignment: Qt.AlignHCenter }
                            }
                        }
                    }
                }

                // WORKSPACE (kept alive even when Home is shown)
                RowLayout {
                    visible: root.pageMode === "workspace"
                    anchors.fill: parent; spacing: 0
                    Item {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        Repeater {
                            model: tabsModel
                            delegate: Item {
                                id: sessionPage
                                required property int index
                                required property int sessionId
                                required property string title
                                required property string kind
                                required property string host
                                required property string user
                                required property int port
                                required property string program
                                required property string argsJson
                                required property string password
                                required property string controlPath
                                required property string securityProfile
                                required property string keyFile
                                required property string domain
                                required property int rdpWidth
                                required property int rdpHeight
                                required property int rdpScale
                                required property bool fullscreen
                                required property bool ignoreCertificate
                                required property bool ftpTls
                                required property bool ftpPassive
                                required property bool overwriteExisting
                                required property int maxParallel
                                property string pendingHostFingerprint: ""
                                anchors.fill: parent
                                visible: index === root.currentTab

                                RdpSessionController { id: rdpController }

                                Connections {
                                    target: rdpController
                                    function onErrorOccurred(message) { root.showToast(message, "error") }
                                }

                                TerminalView {
                                    id: terminal
                                    anchors.fill: parent; anchors.margins: 10
                                    visible: kind === "ssh" || kind === "local"
                                    fontFamily: "JetBrainsMono Nerd Font"
                                    fontSize: root.terminalFontSize
                                    themeName: root.terminalTheme
                                    focus: visible
                                    Component.onCompleted: {
                                        if (kind !== "ssh" && kind !== "local") return
                                        if (program.length > 0) startCommandWithPassword(program, JSON.parse(argsJson), password)
                                        else startLocalShell()
                                        if (password.length > 0) tabsModel.setProperty(index,"password","")
                                        if (visible) root.activeTerminal=terminal
                                    }
                                    onVisibleChanged: if (visible) root.activeTerminal=terminal
                                    onTitleChanged: function(newTitle) { if(newTitle.length>0) tabsModel.setProperty(index,"title",newTitle.length>30?newTitle.slice(0,30):newTitle) }
                                    onErrorOccurred: function(message) { root.showToast(message, "error") }
                                    onSshHostKeyChanged: function(fingerprint) {
                                        if (kind !== "ssh") return
                                        sessionPage.pendingHostFingerprint = fingerprint || ""
                                        sshHostKeyChangedDialog.open()
                                    }
                                    onSshHostKeyVerificationFailed: function(message) {
                                        if (kind === "ssh" && !sshHostKeyChangedDialog.visible)
                                            root.showToast(message + " Check the stored host key for " + host + ".", "error")
                                    }

                                    MouseArea {
                                        anchors.fill: parent; acceptedButtons: Qt.RightButton; propagateComposedEvents: true
                                        onClicked: function(mouse) {
                                            terminal.forceActiveFocus(); root.activeTerminal=terminal
                                            root.openAdaptiveContextPopup(terminalContext, terminal, mouse.x, mouse.y)
                                        }
                                    }
                                }

                                Dialog {
                                    id: sshHostKeyChangedDialog
                                    parent: Overlay.overlay
                                    modal: true
                                    anchors.centerIn: parent
                                    width: Math.min(560, Math.max(420, root.width - 80))
                                    padding: 24
                                    standardButtons: Dialog.NoButton
                                    closePolicy: Popup.NoAutoClose
                                    background: Rectangle {
                                        radius: 18
                                        color: root.panel2
                                        border.color: "#8b4d31"
                                        border.width: 1
                                    }
                                    contentItem: ColumnLayout {
                                        spacing: 15
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Rectangle {
                                                Layout.preferredWidth: 42; Layout.preferredHeight: 42
                                                radius: 12; color: "#3a2317"; border.color: "#8b4d31"
                                                Label { anchors.centerIn: parent; text: "!"; color: root.warning; font.pixelSize: 20; font.bold: true }
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true; spacing: 2
                                                Label { text: "SSH host key changed"; color: root.text; font.pixelSize: 19; font.bold: true }
                                                Label { text: host + ":" + port; color: root.muted; font.pixelSize: 10; Layout.fillWidth: true; elide: Text.ElideMiddle }
                                            }
                                        }
                                        Label {
                                            Layout.fillWidth: true
                                            text: "The identity presented by this server is different from the key MoriXterm previously trusted. This can happen after a server reinstall or key rotation, but it can also indicate a man-in-the-middle attack."
                                            color: root.text
                                            wrapMode: Text.WordWrap
                                            font.pixelSize: 11
                                        }
                                        Rectangle {
                                            visible: sessionPage.pendingHostFingerprint.length > 0
                                            Layout.fillWidth: true
                                            implicitHeight: visible ? 58 : 0
                                            radius: 10
                                            color: "#252729"
                                            border.color: root.border
                                            ColumnLayout {
                                                anchors.fill: parent; anchors.margins: 10; spacing: 2
                                                Label { text: "Fingerprint reported by SSH"; color: root.muted; font.pixelSize: 9 }
                                                Label { text: sessionPage.pendingHostFingerprint; color: root.accent; font.family: "monospace"; font.pixelSize: 10; Layout.fillWidth: true; elide: Text.ElideMiddle }
                                            }
                                        }
                                        Label {
                                            Layout.fillWidth: true
                                            text: "Only replace the stored key if you expected this server change or verified the fingerprint with the server administrator."
                                            color: root.warning
                                            wrapMode: Text.WordWrap
                                            font.pixelSize: 10
                                        }
                                        RowLayout {
                                            Layout.fillWidth: true; spacing: 10
                                            Item { Layout.fillWidth: true }
                                            UI.MButton { text: "Cancel"; onClicked: sshHostKeyChangedDialog.close() }
                                            UI.MButton {
                                                text: "Replace host key & connect"
                                                primary: true
                                                onClicked: {
                                                    if (!sshSecurity.replaceHostKey(host, port)) {
                                                        root.showToast(sshSecurity.lastError.length ? sshSecurity.lastError : "Could not replace the stored SSH host key.", "error")
                                                        return
                                                    }
                                                    sshHostKeyChangedDialog.close()
                                                    root.showToast("Stored SSH host key replaced. Reconnecting…", "warning")
                                                    var retryPassword = sessionPage.sessionId > 0
                                                        ? sessionStore.passwordForSession(sessionPage.sessionId) : ""
                                                    terminal.startCommandWithPassword(program, JSON.parse(argsJson), retryPassword)
                                                }
                                            }
                                        }
                                    }
                                }

                                Loader {
                                    anchors.fill: parent
                                    active: sessionPage.kind === "ftp" || sessionPage.kind === "sftp"
                                    sourceComponent: Component {
                                        UI.FtpWorkspace {
                                            protocol: sessionPage.kind
                                            host: sessionPage.host
                                            user: sessionPage.user
                                            port: sessionPage.port
                                            password: sessionPage.password
                                            keyFile: sessionPage.keyFile
                                            ftpTls: sessionPage.ftpTls
                                            ignoreCertificate: sessionPage.ignoreCertificate
                                            ftpPassive: sessionPage.ftpPassive
                                            maxParallel: sessionPage.maxParallel
                                            overwriteExisting: sessionPage.overwriteExisting
                                            bg: root.bg
                                            panel: root.panel
                                            panel2: root.panel2
                                            panel3: root.panel3
                                            border: root.border
                                            textColor: root.text
                                            muted: root.muted
                                            accent: root.accent
                                            accentSoft: root.accentSoft
                                            danger: root.danger
                                            warning: root.warning
                                            onCredentialsConsumed: {
                                                if (sessionPage.password.length > 0)
                                                    tabsModel.setProperty(sessionPage.index, "password", "")
                                            }
                                            onNotificationRequested: function(message, type) { root.showToast(message, type) }
                                            onPersistentCertificateTrustRequested: {
                                                if (sessionPage.sessionId > 0) {
                                                    if (sessionStore.setIgnoreCertificate(sessionPage.sessionId, true)) {
                                                        tabsModel.setProperty(sessionPage.index, "ignoreCertificate", true)
                                                        root.showToast("Certificate exception saved for this FTP profile.", "warning")
                                                    } else {
                                                        root.showToast(sessionStore.lastError.length ? sessionStore.lastError : "Could not save the certificate exception.", "error")
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    visible: kind === "rdp"
                                    anchors.centerIn: parent
                                    width: Math.min(parent.width - 80, 650)
                                    height: Math.min(parent.height - 20, Math.max(420, rdpCardContent.implicitHeight + 56))
                                    radius: 10
                                    color: root.panel2
                                    border.color: root.border
                                    ColumnLayout {
                                        id: rdpCardContent
                                        anchors.fill: parent
                                        anchors.margins: 28
                                        spacing: 13
                                        Rectangle {
                                            width: 58; height: 58; radius: 16; color: root.accentSoft
                                            Layout.alignment: Qt.AlignHCenter
                                            Label { anchors.centerIn: parent; text: "R"; color: root.accent; font.pixelSize: 28; font.bold: true }
                                        }
                                        Label { text: title; color: root.text; font.pixelSize: 21; font.bold: true; Layout.alignment: Qt.AlignHCenter }
                                        Label { text: (domain.length?domain+"\\":"") + user + (user.length?" @ ":"") + host + ":" + port; color: root.muted; Layout.alignment: Qt.AlignHCenter }
                                        Label {
                                            Layout.fillWidth: true
                                            text: "FreeRDP opens in its own desktop window. MoriXterm keeps the profile and session controls here."
                                            color: root.muted; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter
                                        }
                                        Rectangle { Layout.fillWidth: true; height: 1; color: root.border }
                                        Label {
                                            Layout.fillWidth: true
                                            text: rdpController.statusText
                                            color: rdpController.running ? root.accent : root.muted
                                            horizontalAlignment: Text.AlignHCenter
                                            wrapMode: Text.WordWrap
                                            maximumLineCount: 5
                                            elide: Text.ElideRight
                                        }
                                        Label {
                                            Layout.fillWidth: true
                                            text: rdpController.clientBinary.length ? "Client: " + rdpController.clientBinary : "FreeRDP client not detected"
                                            color: root.muted; font.pixelSize: 9; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideMiddle
                                        }
                                        Label {
                                            Layout.fillWidth: true
                                            text: "Clipboard: text and files both ways • Zoom: " + root.effectiveRdpScale(rdpScale) + "% (Settings → Remote Desktop)"
                                            color: root.muted; font.pixelSize: 11; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                                        }
                                        Label {
                                            Layout.fillWidth: true
                                            text: "Shared folder: " + (rdpController.sharedFolderPath || "not connected") + " → " + root.rdpRemoteShare
                                            color: root.muted; font.pixelSize: 11; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                                        }
                                        RowLayout {
                                            Layout.alignment: Qt.AlignHCenter
                                            UI.MButton {
                                                text: "Reconnect"
                                                enabled: !rdpController.running
                                                onClicked: {
                                                    var pw=sessionId>0?sessionStore.passwordForSession(sessionId):""
                                                    rdpController.start(host,user,pw,domain,port,rdpWidth,rdpHeight,fullscreen,ignoreCertificate,root.effectiveRdpScale(rdpScale),rdpSettings.sharedFolder)
                                                }
                                            }
                                            UI.MButton {
                                                text: "Disconnect"
                                                danger: true
                                                enabled: rdpController.running
                                                onClicked: rdpController.stop()
                                            }
                                        }
                                    }
                                }

                                Component.onCompleted: {
                                    if (kind === "rdp") {
                                        root.activeTerminal=null
                                        rdpController.start(host,user,password,domain,port,rdpWidth,rdpHeight,fullscreen,ignoreCertificate,root.effectiveRdpScale(rdpScale),rdpSettings.sharedFolder)
                                        if (password.length>0) tabsModel.setProperty(index,"password","")
                                    }
                                }
                                onVisibleChanged: { if(!visible) return; root.activeTerminal = (kind === "ssh" || kind === "local") ? terminal : null }
                            }
                        }
                    }

                    Rectangle {
                        visible: root.filePanelVisible && root.fileManagerAvailable
                        Layout.preferredWidth: visible ? uiSettings.filePanelWidth : 0
                        Layout.minimumWidth: visible ? 280 : 0
                        Layout.maximumWidth: visible ? 620 : 0
                        Layout.fillHeight: true
                        color: root.panel; border.color: root.border; clip: true
                        ColumnLayout {
                            anchors.fill: parent; anchors.margins: 8; spacing: 6
                            RowLayout {
                                Layout.fillWidth: true
                                ColumnLayout { Layout.fillWidth: true; spacing: 0; Label { text: fileManager.remote ? "REMOTE FILES" : "LOCAL FILES"; color: root.text; font.bold: true; font.pixelSize: 12 } Label { text: fileManager.sessionLabel; color: root.muted; font.pixelSize: 9; elide: Text.ElideRight; Layout.fillWidth: true } }
                                BusyIndicator { running: fileManager.busy; visible: running; implicitWidth: 26; implicitHeight: 26 }
                                UI.MIconButton { text: "↻"; tip: "Refresh"; enabled: !fileManager.busy; onClicked: fileManager.refresh() }
                            }
                            RowLayout {
                                Layout.fillWidth: true; spacing: 5
                                UI.MIconButton { text: "↑"; tip: "Parent folder"; enabled: !fileManager.busy; onClicked: fileManager.goUp() }
                                UI.MTextField { id: pathField; Layout.fillWidth: true; text: fileManager.currentPath; onAccepted: fileManager.goToPath(text) }
                            }
                            RowLayout {
                                Layout.fillWidth: true; spacing: 3
                                UI.MIconButton { text: "⇧"; tip: "Upload file"; enabled: !fileManager.busy; onClicked: uploadDialog.open() }
                                UI.MIconButton { text: "⇩"; tip: "Download selected"; enabled: root.selectedFileIndex>=0&&!fileManager.busy; onClicked: downloadDialog.open() }
                                UI.MIconButton { text: "+D"; tip: "Create folder"; enabled: !fileManager.busy; onClicked: newFolderDialog.open() }
                                Rectangle { width: 1; height: 22; color: root.border }
                                UI.MIconButton { text: "⧉"; tip: "Copy"; enabled: root.selectedFileIndex>=0&&!fileManager.busy; onClicked: fileManager.copyEntry(root.selectedFileIndex) }
                                UI.MIconButton { text: "✂"; tip: "Cut"; enabled: root.selectedFileIndex>=0&&!fileManager.busy; onClicked: fileManager.cutEntry(root.selectedFileIndex) }
                                UI.MIconButton { text: "▣"; tip: fileManager.clipboardCut?"Move here":"Paste here"; enabled: fileManager.hasClipboardEntry&&!fileManager.busy; onClicked: fileManager.pasteEntry() }
                                Item { Layout.fillWidth: true }
                            }
                            Rectangle { Layout.fillWidth: true; height: 27; radius: 4; color: "#2b2c2e"; RowLayout { anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8; Label { text: "Name"; color: root.muted; font.pixelSize: 9; Layout.fillWidth: true } Label { text: "Mode"; color: root.muted; font.pixelSize: 9; Layout.preferredWidth: 65 } Label { text: "Size"; color: root.muted; font.pixelSize: 9; Layout.preferredWidth: 60; horizontalAlignment: Text.AlignRight } } }

                            ListView {
                                id: fileList; Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 2; model: fileManager.entries; currentIndex: root.selectedFileIndex
                                delegate: Rectangle {
                                    id: fileRow
                                    required property int index
                                    required property string name
                                    required property string path
                                    required property string permissions
                                    required property string owner
                                    required property string group
                                    required property double size
                                    required property bool directory
                                    width: fileList.width; height: 38; radius: 4
                                    color: root.selectedFileIndex===index?"#333b38":(fileHover.hovered?"#2b2d2f":"transparent")
                                    border.color: root.selectedFileIndex===index?"#4d6a5e":"transparent"
                                    HoverHandler { id: fileHover; cursorShape: Qt.PointingHandCursor }
                                    TapHandler {
                                        acceptedButtons: Qt.LeftButton
                                        onTapped: { root.selectedFileIndex=index; root.selectedFileName=name; root.selectedFileDirectory=directory; root.selectedFilePermissions=permissions; root.selectedFileOwner=owner; root.selectedFileGroup=group }
                                        onDoubleTapped: { if(directory) fileManager.openEntry(index) }
                                    }
                                    TapHandler {
                                        acceptedButtons: Qt.RightButton
                                        onTapped: function(eventPoint) {
                                            root.selectedFileIndex=index; root.selectedFileName=name; root.selectedFileDirectory=directory; root.selectedFilePermissions=permissions; root.selectedFileOwner=owner; root.selectedFileGroup=group
                                            root.openAdaptiveContextPopup(fileContext, fileRow, eventPoint.position.x, eventPoint.position.y)
                                        }
                                    }
                                    RowLayout {
                                        anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8; spacing: 7
                                        Image {
                                            source: root.fileIconSource(name, directory)
                                            Layout.preferredWidth: 20
                                            Layout.preferredHeight: 20
                                            sourceSize.width: 20
                                            sourceSize.height: 20
                                            fillMode: Image.PreserveAspectFit
                                            smooth: true
                                        }
                                        ColumnLayout { Layout.fillWidth: true; spacing: 0; Label { text: name; color: root.text; elide: Text.ElideRight; Layout.fillWidth: true } Label { text: owner+(group.length?":"+group:""); color: root.muted; font.pixelSize: 8; elide: Text.ElideRight; Layout.fillWidth: true } }
                                        Label { text: permissions; color: root.muted; font.pixelSize: 9; font.family: "monospace"; Layout.preferredWidth: 65 }
                                        Label { text: directory?"—":root.humanSize(size); color: root.muted; font.pixelSize: 9; Layout.preferredWidth: 60; horizontalAlignment: Text.AlignRight }
                                    }
                                }
                            }
                            // Intentionally no Rename/chmod/chown button row: these advanced actions live in the file context menu.
                            Rectangle {
                                visible: fileManager.busy && fileManager.operationName.length > 0 && fileManager.operationName !== "Working"
                                Layout.fillWidth: true
                                Layout.preferredHeight: visible ? 64 : 0
                                radius: 10
                                color: "#26282a"
                                border.color: "#45474a"
                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 9
                                    spacing: 5
                                    RowLayout {
                                        Layout.fillWidth: true
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 0
                                            Label { text: fileManager.operationName; color: root.text; font.pixelSize: 10; font.bold: true; Layout.fillWidth: true }
                                            Label { text: fileManager.operationDetail; visible: text.length > 0; color: root.muted; font.pixelSize: 8; elide: Text.ElideMiddle; Layout.fillWidth: true }
                                        }
                                        BusyIndicator { visible: fileManager.operationProgress < 0; running: visible; implicitWidth: 22; implicitHeight: 22 }
                                        Label { visible: fileManager.operationProgress >= 0; text: fileManager.operationProgress + "%"; color: root.accent; font.pixelSize: 10; font.bold: true }
                                    }
                                    Rectangle {
                                        visible: fileManager.operationProgress >= 0
                                        Layout.fillWidth: true
                                        height: 5
                                        radius: 3
                                        color: "#35383b"
                                        Rectangle {
                                            width: parent.width * Math.max(0, Math.min(100, fileManager.operationProgress)) / 100
                                            height: parent.height
                                            radius: 3
                                            color: root.accent
                                            Behavior on width { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
                                        }
                                    }
                                }
                            }
                            Label { Layout.fillWidth: true; text: fileManager.statusText; color: root.muted; font.pixelSize: 9; elide: Text.ElideRight }
                            Label { visible: fileManager.remote && fileManager.statusText.indexOf("not authenticated yet")>=0; Layout.fillWidth: true; text: "Finish SSH authentication in the terminal, then refresh. The file manager reuses the authenticated ControlMaster connection."; color: root.warning; font.pixelSize: 9; wrapMode: Text.WordWrap }
                        }
                    }

                    Rectangle {
                        id: filePanelResizeHandle
                        visible: root.filePanelVisible && root.fileManagerAvailable
                        Layout.preferredWidth: visible ? 7 : 0
                        Layout.fillHeight: true
                        color: filePanelResizeMouse.pressed ? root.accent : (filePanelResizeHover.hovered ? root.accentSoft : root.border)

                        HoverHandler {
                            id: filePanelResizeHover
                            cursorShape: Qt.SizeHorCursor
                        }
                        MouseArea {
                            id: filePanelResizeMouse
                            anchors.fill: parent
                            cursorShape: Qt.SizeHorCursor
                            property real startX: 0
                            property real startWidth: 0
                            onPressed: {
                                startX = mouse.x
                                startWidth = uiSettings.filePanelWidth
                            }
                            onPositionChanged: {
                                if (!pressed) return
                                uiSettings.filePanelWidth = Math.max(280, Math.min(620, startWidth - (mouse.x - startX)))
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true; Layout.preferredHeight: 30; color: "#177c58"; border.color: "#177c58"
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14
                    Label { text: "●"; color: "#c8f8e5"; font.pixelSize: 9 }
                    Label { text: root.pageMode==="home"?"Home":(root.currentTab>=0 && root.currentTab<tabsModel.count ? tabsModel.get(root.currentTab).kind.toUpperCase()+" session" : "Ready"); color: "#e8fff6"; font.pixelSize: 11; font.weight: Font.Medium }
                    Item { Layout.fillWidth: true }
                    Label { text: "Right click for context actions • Credentials: OS vault"; color: "#d4f5e8"; font.pixelSize: 10 }
                }
            }
        }
    }

    Rectangle {
        id: dragHint
        visible: root.draggingSession
        z: 9400
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 94
        width: Math.min(430, dragHintRow.implicitWidth + 34)
        height: 48
        radius: 14
        color: "#2d302f"
        border.color: root.accent
        border.width: 1
        opacity: 0.98
        RowLayout {
            id: dragHintRow
            anchors.centerIn: parent
            spacing: 10
            Label { text: "↳"; color: root.accent; font.pixelSize: 18; font.bold: true }
            Label { text: root.dragTargetFolderId > 0 ? "Move “" + root.draggingSessionName + "” to “" + root.dragTargetFolderName + "”" : "Drop “" + root.draggingSessionName + "” on a folder"; color: root.text; font.pixelSize: 11; font.bold: true }
        }
    }

    UI.MToastHost {
        id: toastHost
        // Dialogs/Popups are re-parented to Overlay.overlay by Qt Quick Controls.
        // Keeping the toast in the normal content item means a modal can cover it
        // regardless of z. Parent it to the same overlay and give it the highest z.
        parent: Overlay.overlay
        anchors.fill: parent
        z: 2147483000
    }

    // ---------- App lock overlay ----------
    Rectangle {
        id: lockOverlay
        visible: appLock.locked
        anchors.fill: parent
        z: 9999
        focus: visible
        clip: true
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#020a07" }
            GradientStop { position: 0.55; color: "#222426" }
            GradientStop { position: 1.0; color: "#242628" }
        }
        Keys.onPressed: function(event) {
            if(event.key===Qt.Key_Return || event.key===Qt.Key_Enter) {
                unlockButton.clicked()
                event.accepted = true
            }
        }

        Rectangle {
            width: Math.max(root.width * 0.62, 760)
            height: 220
            x: root.width * 0.44
            y: -20
            radius: 110
            rotation: -18
            color: "#32c7ff"
            opacity: 0.055
        }
        Rectangle {
            width: Math.max(root.width * 0.72, 860)
            height: 260
            x: root.width * 0.18
            y: root.height - 170
            radius: 130
            rotation: 12
            color: root.accent
            opacity: 0.06
        }
        Image {
            source: "qrc:/assets/morixtrem-app.png"
            width: Math.min(560, root.width * 0.36)
            height: width
            anchors.right: parent.right
            anchors.rightMargin: 60
            anchors.verticalCenter: parent.verticalCenter
            fillMode: Image.PreserveAspectFit
            opacity: 0.055
            smooth: true
        }

        Rectangle {
            anchors.centerIn: parent
            width: 440
            height: lockColumn.implicitHeight + 58
            radius: 24
            color: Qt.rgba(0.035, 0.085, 0.061, 0.96)
            border.color: "#274c3a"
            border.width: 1

            ColumnLayout {
                id: lockColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 28
                spacing: 14

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 82; Layout.preferredHeight: 82; radius: 22
                    color: "#242628"
                    border.color: "#244b38"
                    Image { anchors.fill: parent; anchors.margins: 9; source: "qrc:/assets/morixtrem-app.png"; fillMode: Image.PreserveAspectFit; smooth: true }
                }
                Label { text: "Workspace locked"; color: "#f0fff7"; font.pixelSize: 24; font.bold: true; Layout.alignment: Qt.AlignHCenter }
                Label {
                    text: "Your active sessions keep running while the interface is protected."
                    color: root.muted; font.pixelSize: 12; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter
                    Layout.fillWidth: true
                }
                Item { Layout.preferredHeight: 4 }
                UI.MTextField {
                    id: unlockPassword
                    Layout.fillWidth: true
                    echoMode: TextInput.Password
                    placeholderText: "Application password"
                    onAccepted: unlockButton.clicked()
                }
                UI.MButton {
                    id: unlockButton
                    Layout.fillWidth: true
                    text: "Unlock workspace"
                    primary: true
                    onClicked: { if(appLock.unlock(unlockPassword.text)) unlockPassword.text=""; else unlockPassword.selectAll() }
                }
                Label { text: appLock.statusMessage; color: root.danger; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap }
                Rectangle { Layout.fillWidth: true; height: 1; color: root.border }
                Label { text: "●  SSH, RDP and transfers remain active"; color: "#729487"; font.pixelSize: 10; Layout.alignment: Qt.AlignHCenter }
            }
        }
        onVisibleChanged: if(visible) Qt.callLater(function(){ unlockPassword.forceActiveFocus() })
    }

    Connections {
        target: appLock
        function onStatusMessageChanged() {
            if (appLock.statusMessage && appLock.statusMessage.length) {
                var lower = appLock.statusMessage.toLowerCase()
                var kind = (lower.indexOf("incorrect") >= 0 || lower.indexOf("must") >= 0 || lower.indexOf("too many") >= 0 || lower.indexOf("failed") >= 0) ? "error" : "info"
                root.showToast(appLock.statusMessage, kind, true)
            }
        }
        function onLockedChanged() {
            if (appLock.locked) {
                toastHost.dismiss()
                sessionEditor.close(); settingsDialog.close(); aboutDialog.close(); compressDialog.close(); extractDialog.close(); fileContext.close(); terminalContext.close(); sessionContext.close(); folderContext.close()
                sessionPasswordField.text=""; currentLockPassword.text=""; newLockPassword.text=""; confirmLockPassword.text=""
            }
        }
    }
}
