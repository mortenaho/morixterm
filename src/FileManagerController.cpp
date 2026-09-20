#include "FileManagerController.h"
#include "SshSecurity.h"

#include <QDir>
#include <QFileInfo>
#include <QFileInfoList>
#include <QStandardPaths>
#include <QRegularExpression>

#include <algorithm>

namespace {
QString modeToSymbolic(const QFileInfo &info)
{
    const QFile::Permissions p = info.permissions();
    QString s;
    s.reserve(9);
    s += (p & QFileDevice::ReadOwner) ? 'r' : '-';
    s += (p & QFileDevice::WriteOwner) ? 'w' : '-';
    s += (p & QFileDevice::ExeOwner) ? 'x' : '-';
    s += (p & QFileDevice::ReadGroup) ? 'r' : '-';
    s += (p & QFileDevice::WriteGroup) ? 'w' : '-';
    s += (p & QFileDevice::ExeGroup) ? 'x' : '-';
    s += (p & QFileDevice::ReadOther) ? 'r' : '-';
    s += (p & QFileDevice::WriteOther) ? 'w' : '-';
    s += (p & QFileDevice::ExeOther) ? 'x' : '-';
    return s;
}

QString urlToLocalPath(const QUrl &url)
{
    if (url.isLocalFile())
        return url.toLocalFile();
    return url.toString();
}
}

FileManagerController::FileManagerController(QObject *parent)
    : QObject(parent), m_entries(this)
{
    m_authRetryTimer.setSingleShot(true);
    m_authRetryTimer.setInterval(1000);
    connect(&m_authRetryTimer, &QTimer::timeout, this, [this] {
        if (m_remote && !m_busy && m_authRetryRemaining > 0)
            refresh();
    });
    configureLocal();
}

void FileManagerController::configureLocal()
{
    m_authRetryTimer.stop();
    m_authRetryRemaining = 0;
    if (m_process) {
        disconnect(m_process, nullptr, this, nullptr);
        if (m_process->state() != QProcess::NotRunning)
            m_process->kill();
        m_process->deleteLater();
        m_process = nullptr;
        setBusy(false);
    }

    m_entries.setEntries({});
    m_remote = false;
    m_host.clear();
    m_user.clear();
    m_port = 22;
    m_currentPath = QDir::homePath();
    m_sessionLabel = QStringLiteral("Local machine");
    clearClipboardEntry();
    emit sessionChanged();
    emit currentPathChanged();
    refresh();
}

void FileManagerController::configureSsh(const QString &host, const QString &user, int port,
                                         const QString &controlPath, const QString &securityProfile,
                                         const QString &keyFile)
{
    m_authRetryTimer.stop();
    // The terminal creates/authenticates the shared OpenSSH ControlMaster. The
    // file manager retries quietly until that authenticated channel exists.
    m_authRetryRemaining = 60;
    if (m_process) {
        disconnect(m_process, nullptr, this, nullptr);
        if (m_process->state() != QProcess::NotRunning)
            m_process->kill();
        m_process->deleteLater();
        m_process = nullptr;
        setBusy(false);
    }

    m_entries.setEntries({});
    m_remote = true;
    m_host = host.trimmed();
    m_user = user.trimmed();
    m_port = (port > 0 && port <= 65535) ? port : 22;
    m_controlPath = controlPath.isEmpty() ? SshSecurity::controlPathTemplate() : controlPath;
    m_securityProfile = SshSecurity::normalizeProfile(securityProfile);
    m_keyFile = keyFile.trimmed();
    m_currentPath = QStringLiteral("~");
    m_sessionLabel = m_user.isEmpty()
        ? QStringLiteral("%1:%2").arg(m_host).arg(m_port)
        : QStringLiteral("%1@%2:%3").arg(m_user, m_host).arg(m_port);
    clearClipboardEntry();
    emit sessionChanged();
    emit currentPathChanged();
    refresh();
}

void FileManagerController::refresh()
{
    if (m_busy)
        return;
    m_operationName.clear();
    m_operationDetail.clear();
    m_operationProgress = -1;
    emit operationChanged();
    if (m_remote)
        refreshRemote();
    else
        refreshLocal();
}

void FileManagerController::goUp()
{
    if (m_busy)
        return;

    if (m_currentPath == QStringLiteral("/") || m_currentPath.isEmpty() || (m_remote && m_currentPath == QStringLiteral("~")))
        return;

    if (m_remote) {
        m_currentPath = QDir::cleanPath(m_currentPath + QStringLiteral("/.."));
    } else {
        QDir dir(m_currentPath);
        if (!dir.cdUp())
            return;
        m_currentPath = dir.absolutePath();
    }
    emit currentPathChanged();
    refresh();
}

void FileManagerController::openEntry(int row)
{
    const FileEntry *entry = m_entries.entryAt(row);
    if (!entry || !entry->directory || m_busy)
        return;
    m_currentPath = entry->path;
    emit currentPathChanged();
    refresh();
}

void FileManagerController::goToPath(const QString &path)
{
    if (path.trimmed().isEmpty() || m_busy)
        return;
    m_currentPath = path.trimmed();
    emit currentPathChanged();
    refresh();
}

QString FileManagerController::entryPath(int row) const
{
    const FileEntry *entry = m_entries.entryAt(row);
    return entry ? entry->path : QString();
}

QString FileManagerController::entryName(int row) const
{
    const FileEntry *entry = m_entries.entryAt(row);
    return entry ? entry->name : QString();
}

bool FileManagerController::entryIsDirectory(int row) const
{
    const FileEntry *entry = m_entries.entryAt(row);
    return entry && entry->directory;
}

void FileManagerController::upload(const QUrl &localFileUrl)
{
    if (m_busy)
        return;

    const QString localPath = urlToLocalPath(localFileUrl);
    const QFileInfo source(localPath);
    if (!source.exists()) {
        finishAndRefresh(false, QStringLiteral("Local file does not exist."));
        return;
    }

    beginOperation(QStringLiteral("Upload"), -1, source.fileName());

    if (!m_remote) {
        const QString destination = pathJoin(m_currentPath, source.fileName());
        const QString program = source.isDir() ? QStringLiteral("/bin/cp") : QStringLiteral("/bin/cp");
        QStringList args { QStringLiteral("-a"), QStringLiteral("--"), localPath, destination };
        runProcess(program, args, [this](int code, QProcess::ExitStatus status, const QByteArray &, const QByteArray &err) {
            const bool ok = status == QProcess::NormalExit && code == 0;
            finishAndRefresh(ok, ok ? QStringLiteral("Upload completed.") : QString::fromLocal8Bit(err).trimmed());
        });
        return;
    }

    QStringList args = scpBaseArgs();
    if (source.isDir())
        args << QStringLiteral("-r");
    args << localPath << (target() + QStringLiteral(":") + m_currentPath + QStringLiteral("/"));

    runProcess(QStandardPaths::findExecutable(QStringLiteral("scp")), args,
               [this](int code, QProcess::ExitStatus status, const QByteArray &, const QByteArray &err) {
        const bool ok = status == QProcess::NormalExit && code == 0;
        finishAndRefresh(ok, ok ? QStringLiteral("Upload completed.") : QString::fromLocal8Bit(err).trimmed());
    });
}

void FileManagerController::downloadEntry(int row, const QUrl &localFolderUrl)
{
    if (m_busy)
        return;

    const FileEntry *entry = m_entries.entryAt(row);
    if (!entry)
        return;

    const QString localFolder = urlToLocalPath(localFolderUrl);
    if (localFolder.isEmpty())
        return;

    beginOperation(QStringLiteral("Download"), -1, entry->name);

    if (!m_remote) {
        const QString destination = pathJoin(localFolder, entry->name);
        runProcess(QStringLiteral("/bin/cp"),
                   {QStringLiteral("-a"), QStringLiteral("--"), entry->path, destination},
                   [this](int code, QProcess::ExitStatus status, const QByteArray &, const QByteArray &err) {
            const bool ok = status == QProcess::NormalExit && code == 0;
            setBusy(false);
            const QString message = ok ? QStringLiteral("Download completed.") : QString::fromLocal8Bit(err).trimmed();
            setStatus(message);
            emit operationFinished(ok, message);
        });
        return;
    }

    QStringList args = scpBaseArgs();
    if (entry->directory)
        args << QStringLiteral("-r");
    args << (target() + QStringLiteral(":") + entry->path) << localFolder;

    runProcess(QStandardPaths::findExecutable(QStringLiteral("scp")), args,
               [this](int code, QProcess::ExitStatus status, const QByteArray &, const QByteArray &err) {
        const bool ok = status == QProcess::NormalExit && code == 0;
        setBusy(false);
        const QString message = ok ? QStringLiteral("Download completed.") : QString::fromLocal8Bit(err).trimmed();
        setStatus(message);
        emit operationFinished(ok, message);
    });
}

void FileManagerController::createFolder(const QString &name)
{
    const QString clean = name.trimmed();
    if (clean.isEmpty() || clean == QStringLiteral(".") || clean == QStringLiteral("..") || clean.contains('/')) {
        emit operationFinished(false, QStringLiteral("Invalid folder name."));
        return;
    }

    const QString destination = pathJoin(m_currentPath, clean);
    const QString remoteCommand = QStringLiteral("cd -- %1 && mkdir -- %2")
        .arg(remoteCdTarget(), shellQuote(clean));
    runFileOperation(QStringLiteral("/bin/mkdir"), {QStringLiteral("--"), destination},
                     remoteCommand, QStringLiteral("Folder created."));
}

void FileManagerController::renameEntry(int row, const QString &newName)
{
    const FileEntry *entry = m_entries.entryAt(row);
    const QString clean = newName.trimmed();
    if (!entry || clean.isEmpty() || clean == QStringLiteral(".") || clean == QStringLiteral("..") || clean.contains('/')) {
        emit operationFinished(false, QStringLiteral("Invalid new name."));
        return;
    }

    const QString destination = pathJoin(m_currentPath, clean);
    runFileOperation(QStringLiteral("/bin/mv"), {QStringLiteral("--"), entry->path, destination},
                     QStringLiteral("mv -- %1 %2").arg(shellQuote(entry->path), shellQuote(destination)),
                     QStringLiteral("Renamed."));
}

void FileManagerController::chmodEntry(int row, const QString &mode)
{
    const FileEntry *entry = m_entries.entryAt(row);
    const QString clean = mode.trimmed();
    static const QRegularExpression octal(QStringLiteral("^[0-7]{3,4}$"));
    static const QRegularExpression symbolic(QStringLiteral("^[ugoa]*[+-=][rwxXstugo]+(?:,[ugoa]*[+-=][rwxXstugo]+)*$"));
    if (!entry || (!octal.match(clean).hasMatch() && !symbolic.match(clean).hasMatch())) {
        emit operationFinished(false, QStringLiteral("Invalid permission mode."));
        return;
    }

    runFileOperation(QStringLiteral("/bin/chmod"), {QStringLiteral("--"), clean, entry->path},
                     QStringLiteral("chmod -- %1 %2").arg(shellQuote(clean), shellQuote(entry->path)),
                     QStringLiteral("Permissions changed."));
}

void FileManagerController::chownEntry(int row, const QString &ownerAndGroup)
{
    const FileEntry *entry = m_entries.entryAt(row);
    const QString clean = ownerAndGroup.trimmed();
    static const QRegularExpression ownerRx(QStringLiteral("^[A-Za-z0-9_.-]+(?::[A-Za-z0-9_.-]+)?$"));
    if (!entry || !ownerRx.match(clean).hasMatch()) {
        emit operationFinished(false, QStringLiteral("Invalid owner or group."));
        return;
    }

    runFileOperation(QStringLiteral("/bin/chown"), {QStringLiteral("--"), clean, entry->path},
                     QStringLiteral("chown -- %1 %2").arg(shellQuote(clean), shellQuote(entry->path)),
                     QStringLiteral("Owner changed."));
}

void FileManagerController::deleteEntry(int row)
{
    if (m_busy)
        return;

    const FileEntry *entry = m_entries.entryAt(row);
    if (!entry) {
        emit operationFinished(false, QStringLiteral("Select a file or folder first."));
        return;
    }

    beginOperation(QStringLiteral("Deleting"), -1, entry->name);
    const QString remoteCommand = QStringLiteral("rm -rf -- %1").arg(shellQuote(entry->path));
    runFileOperation(QStringLiteral("/bin/rm"),
                     {QStringLiteral("-rf"), QStringLiteral("--"), entry->path},
                     remoteCommand,
                     QStringLiteral("Deleted."));
}

void FileManagerController::copyEntry(int row)
{
    const FileEntry *entry = m_entries.entryAt(row);
    if (!entry)
        return;

    m_clipboardPath = entry->path;
    m_clipboardName = entry->name;
    m_clipboardCut = false;
    m_clipboardRemote = m_remote;
    m_clipboardSessionKey = m_remote ? target() + QString::number(m_port) : QStringLiteral("local");
    emit clipboardChanged();
    setStatus(QStringLiteral("Copied %1").arg(entry->name));
}

void FileManagerController::cutEntry(int row)
{
    const FileEntry *entry = m_entries.entryAt(row);
    if (!entry)
        return;

    m_clipboardPath = entry->path;
    m_clipboardName = entry->name;
    m_clipboardCut = true;
    m_clipboardRemote = m_remote;
    m_clipboardSessionKey = m_remote ? target() + QString::number(m_port) : QStringLiteral("local");
    emit clipboardChanged();
    setStatus(QStringLiteral("Cut %1").arg(entry->name));
}

void FileManagerController::pasteEntry()
{
    if (!hasClipboardEntry() || m_busy)
        return;

    const QString currentSessionKey = m_remote ? target() + QString::number(m_port) : QStringLiteral("local");
    if (m_clipboardRemote != m_remote || m_clipboardSessionKey != currentSessionKey) {
        emit operationFinished(false, QStringLiteral("File clipboard belongs to another session."));
        return;
    }

    const QString destination = pathJoin(m_currentPath, m_clipboardName);
    if (m_clipboardPath == destination) {
        emit operationFinished(false, QStringLiteral("Source and destination are the same."));
        return;
    }

    const bool cut = m_clipboardCut;
    const QString source = m_clipboardPath;
    const QString program = cut ? QStringLiteral("/bin/mv") : QStringLiteral("/bin/cp");
    QStringList args;
    if (!cut)
        args << QStringLiteral("-a");
    args << QStringLiteral("--") << source << destination;

    const QString remoteCommand = cut
        ? QStringLiteral("mv -- %1 %2").arg(shellQuote(source), shellQuote(destination))
        : QStringLiteral("cp -a -- %1 %2").arg(shellQuote(source), shellQuote(destination));

    if (m_remote) {
        runProcess(QStandardPaths::findExecutable(QStringLiteral("ssh")), sshBaseArgs() << target() << remoteCommand,
                   [this, cut](int code, QProcess::ExitStatus status, const QByteArray &, const QByteArray &err) {
            const bool ok = status == QProcess::NormalExit && code == 0;
            if (ok && cut)
                clearClipboardEntry();
            finishAndRefresh(ok, ok ? QStringLiteral("Paste completed.") : QString::fromLocal8Bit(err).trimmed());
        });
    } else {
        runProcess(program, args,
                   [this, cut](int code, QProcess::ExitStatus status, const QByteArray &, const QByteArray &err) {
            const bool ok = status == QProcess::NormalExit && code == 0;
            if (ok && cut)
                clearClipboardEntry();
            finishAndRefresh(ok, ok ? QStringLiteral("Paste completed.") : QString::fromLocal8Bit(err).trimmed());
        });
    }
}

QString FileManagerController::defaultArchiveName(int row) const
{
    const FileEntry *entry = m_entries.entryAt(row);
    if (!entry)
        return QStringLiteral("archive.zip");

    QString base = entry->directory ? entry->name : QFileInfo(entry->name).completeBaseName();
    if (base.trimmed().isEmpty())
        base = QStringLiteral("archive");
    return base + QStringLiteral(".zip");
}

QString FileManagerController::defaultExtractFolder(int row) const
{
    const FileEntry *entry = m_entries.entryAt(row);
    if (!entry)
        return QStringLiteral("extracted");

    QString base = QFileInfo(entry->name).completeBaseName();
    if (base.trimmed().isEmpty())
        base = QStringLiteral("extracted");
    return base;
}

void FileManagerController::compressEntry(int row, const QString &archiveName)
{
    if (m_busy)
        return;

    const FileEntry *entry = m_entries.entryAt(row);
    if (!entry) {
        emit operationFinished(false, QStringLiteral("Select a file or folder first."));
        return;
    }

    QString archive = archiveName.trimmed();
    if (archive.isEmpty())
        archive = defaultArchiveName(row);
    if (!archive.endsWith(QStringLiteral(".zip"), Qt::CaseInsensitive))
        archive += QStringLiteral(".zip");

    if (archive == QStringLiteral(".") || archive == QStringLiteral("..") || archive.contains('/') || archive.contains('\\') || archive.contains('\n') || archive.contains('\r')) {
        emit operationFinished(false, QStringLiteral("Invalid archive name."));
        return;
    }

    const QString archiveArg = archive.startsWith('-') ? QStringLiteral("./") + archive : archive;
    const QString destination = pathJoin(m_currentPath, archive);
    if (!m_remote && QFileInfo::exists(destination)) {
        emit operationFinished(false, QStringLiteral("An item named %1 already exists.").arg(archive));
        return;
    }

    beginOperation(QStringLiteral("Compressing"), 0, archive);
    m_parseProgress = true;
    m_progressTotal = 0;
    m_progressDone = 0;
    m_progressBuffer.clear();
    m_liveStdout.clear();

    if (m_remote) {
        const QString command = QStringLiteral(
            "export LC_ALL=C; cd -- %1 || exit 2; "
            "command -v zip >/dev/null 2>&1 || { printf 'zip is not installed on the remote server.\\n' >&2; exit 127; }; "
            "test ! -e %2 || { printf 'Destination already exists.\\n' >&2; exit 3; }; "
            "total=$(find -- %3 -print 2>/dev/null | wc -l); [ \"$total\" -gt 0 ] || total=1; "
            "printf '__MX_TOTAL__%s\\n' \"$total\"; "
            "zip -r %2 %3")
            .arg(remoteCdTarget(), shellQuote(archiveArg), shellQuote(entry->name));

        runProcess(QStandardPaths::findExecutable(QStringLiteral("ssh")), sshBaseArgs() << target() << command,
                   [this](int code, QProcess::ExitStatus status, const QByteArray &, const QByteArray &err) {
            const bool ok = status == QProcess::NormalExit && code == 0;
            finishAndRefresh(ok, ok ? QStringLiteral("ZIP archive created.") : QString::fromLocal8Bit(err).trimmed());
        });
        return;
    }

    if (QStandardPaths::findExecutable(QStringLiteral("zip")).isEmpty()) {
        finishAndRefresh(false, QStringLiteral("zip is not installed. Install the 'zip' package first."));
        return;
    }
    const QString shell = QStandardPaths::findExecutable(QStringLiteral("sh"));
    if (shell.isEmpty()) {
        finishAndRefresh(false, QStringLiteral("sh was not found."));
        return;
    }
    const QString command = QStringLiteral(
        "export LC_ALL=C; cd -- %1 || exit 2; "
        "total=$(find -- %2 -print 2>/dev/null | wc -l); [ \"$total\" -gt 0 ] || total=1; "
        "printf '__MX_TOTAL__%s\\n' \"$total\"; "
        "zip -r %3 %2")
        .arg(shellQuote(m_currentPath), shellQuote(entry->name), shellQuote(archiveArg));
    runProcess(shell, {QStringLiteral("-c"), command},
               [this](int code, QProcess::ExitStatus status, const QByteArray &, const QByteArray &err) {
        const bool ok = status == QProcess::NormalExit && code == 0;
        finishAndRefresh(ok, ok ? QStringLiteral("ZIP archive created.") : QString::fromLocal8Bit(err).trimmed());
    });
}

void FileManagerController::extractZipEntry(int row, const QString &destinationFolder)
{
    if (m_busy)
        return;

    const FileEntry *entry = m_entries.entryAt(row);
    if (!entry || entry->directory || !entry->name.endsWith(QStringLiteral(".zip"), Qt::CaseInsensitive)) {
        emit operationFinished(false, QStringLiteral("Select a ZIP archive first."));
        return;
    }

    QString folder = destinationFolder.trimmed();
    if (folder.isEmpty())
        folder = defaultExtractFolder(row);
    if (folder == QStringLiteral(".") || folder == QStringLiteral("..") || folder.contains('/') || folder.contains('\\') || folder.contains('\n') || folder.contains('\r')) {
        emit operationFinished(false, QStringLiteral("Invalid destination folder name."));
        return;
    }

    const QString archiveArg = entry->name.startsWith('-') ? QStringLiteral("./") + entry->name : entry->name;
    const QString destination = pathJoin(m_currentPath, folder);
    if (!m_remote && QFileInfo::exists(destination)) {
        emit operationFinished(false, QStringLiteral("Destination folder already exists."));
        return;
    }

    beginOperation(QStringLiteral("Extracting"), 0, entry->name);
    m_parseProgress = true;
    m_progressTotal = 0;
    m_progressDone = 0;
    m_progressBuffer.clear();
    m_liveStdout.clear();

    // Archives are pre-checked for absolute paths and parent-directory traversal before extraction.
    // The destination folder must not already exist, which also reduces symlink-based surprises.
    const QString validation = QStringLiteral(
        "unzip -Z1 %1 | awk 'BEGIN{bad=0} {n=$0; gsub(/\\\\/,\"/\",n); if (n ~ /^\\// || n ~ /^[A-Za-z]:\\//) bad=1; c=split(n,a,\"/\"); for(i=1;i<=c;i++) if(a[i]==\"..\") bad=1} END{exit bad?1:0}'")
        .arg(shellQuote(archiveArg));

    const QString extractCommand = QStringLiteral(
        "export LC_ALL=C; cd -- %1 || exit 2; "
        "command -v unzip >/dev/null 2>&1 || { printf 'unzip is not installed.\\n' >&2; exit 127; }; "
        "test ! -e %2 || { printf 'Destination folder already exists.\\n' >&2; exit 3; }; "
        "%3 || { printf 'Archive contains an unsafe path.\\n' >&2; exit 4; }; "
        "total=$(unzip -Z1 %4 | wc -l); [ \"$total\" -gt 0 ] || total=1; printf '__MX_TOTAL__%s\\n' \"$total\"; "
        "mkdir -- %2 && unzip %4 -d %2")
        .arg(m_remote ? remoteCdTarget() : shellQuote(m_currentPath),
             shellQuote(folder), validation, shellQuote(archiveArg));

    if (m_remote) {
        runProcess(QStandardPaths::findExecutable(QStringLiteral("ssh")), sshBaseArgs() << target() << extractCommand,
                   [this](int code, QProcess::ExitStatus status, const QByteArray &, const QByteArray &err) {
            const bool ok = status == QProcess::NormalExit && code == 0;
            finishAndRefresh(ok, ok ? QStringLiteral("ZIP archive extracted.") : QString::fromLocal8Bit(err).trimmed());
        });
        return;
    }

    const QString shell = QStandardPaths::findExecutable(QStringLiteral("sh"));
    if (shell.isEmpty() || QStandardPaths::findExecutable(QStringLiteral("unzip")).isEmpty()) {
        finishAndRefresh(false, QStringLiteral("unzip is not installed. Install the 'unzip' package first."));
        return;
    }

    runProcess(shell, {QStringLiteral("-c"), extractCommand},
               [this](int code, QProcess::ExitStatus status, const QByteArray &, const QByteArray &err) {
        const bool ok = status == QProcess::NormalExit && code == 0;
        finishAndRefresh(ok, ok ? QStringLiteral("ZIP archive extracted.") : QString::fromLocal8Bit(err).trimmed());
    });
}

void FileManagerController::beginOperation(const QString &name, int progress, const QString &detail)
{
    m_operationName = name;
    m_operationProgress = progress;
    m_operationDetail = detail;
    emit operationChanged();
}

void FileManagerController::setOperationProgress(int progress, const QString &detail)
{
    m_operationProgress = progress < 0 ? -1 : qBound(0, progress, 100);
    if (!detail.isNull())
        m_operationDetail = detail;
    emit operationChanged();
}

void FileManagerController::parseOperationProgress(const QByteArray &chunk)
{
    m_progressBuffer += chunk;
    m_progressBuffer.replace('\r', '\n');
    const QList<QByteArray> lines = m_progressBuffer.split('\n');
    if (!m_progressBuffer.endsWith('\n'))
        m_progressBuffer = lines.isEmpty() ? QByteArray() : lines.last();
    else
        m_progressBuffer.clear();

    for (int i = 0; i < lines.size(); ++i) {
        if (i == lines.size() - 1 && !chunk.endsWith('\n') && !chunk.endsWith('\r'))
            break;
        const QByteArray line = lines.at(i).trimmed();
        if (line.startsWith("__MX_TOTAL__")) {
            bool ok = false;
            const int total = line.mid(sizeof("__MX_TOTAL__") - 1).toInt(&ok);
            if (ok && total > 0) m_progressTotal = total;
            continue;
        }
        if (line.contains("adding:") || line.contains("updating:") || line.contains("inflating:") ||
            line.contains("extracting:") || line.contains("creating:")) {
            ++m_progressDone;
            if (m_progressTotal > 0)
                setOperationProgress(qMin(99, (m_progressDone * 100) / m_progressTotal), QString::fromLocal8Bit(line));
        }
    }
}

void FileManagerController::setBusy(bool busy)
{
    if (m_busy == busy)
        return;
    m_busy = busy;
    emit busyChanged();
}

void FileManagerController::setStatus(const QString &status)
{
    if (m_statusText == status)
        return;
    m_statusText = status;
    emit statusTextChanged();
}

QString FileManagerController::target() const
{
    return m_user.isEmpty() ? m_host : m_user + QStringLiteral("@") + m_host;
}

QString FileManagerController::shellQuote(const QString &value) const
{
    QString escaped = value;
    escaped.replace('\'', QStringLiteral("'\\''"));
    return QStringLiteral("'") + escaped + QStringLiteral("'");
}

QString FileManagerController::pathJoin(const QString &base, const QString &name) const
{
    if (base == QStringLiteral("/"))
        return QStringLiteral("/") + name;
    if (base.endsWith('/'))
        return base + name;
    return base + QStringLiteral("/") + name;
}

QString FileManagerController::remoteCdTarget() const
{
    return m_currentPath == QStringLiteral("~") ? QStringLiteral("~") : shellQuote(m_currentPath);
}

QStringList FileManagerController::sshBaseArgs() const
{
    return SshSecurity::commonOptions(m_port, m_controlPath, m_securityProfile, m_keyFile, true);
}

QStringList FileManagerController::scpBaseArgs() const
{
    QStringList args = SshSecurity::commonOptions(m_port, m_controlPath, m_securityProfile, m_keyFile, true);
    if (args.size() >= 2 && args.at(0) == QStringLiteral("-p"))
        args[0] = QStringLiteral("-P");
    return args;
}

void FileManagerController::runProcess(const QString &program, const QStringList &arguments,
                                       Completion completion, const QByteArray &stdinData,
                                       const QString &workingDirectory)
{
    if (m_busy)
        return;

    if (program.trimmed().isEmpty()) {
        const QString message = QStringLiteral("Required executable was not found on this system.");
        setStatus(message);
        emit operationFinished(false, message);
        return;
    }

    if (m_process) {
        m_process->deleteLater();
        m_process = nullptr;
    }

    m_liveStdout.clear();
    setBusy(true);
    if (m_operationName.isEmpty())
        beginOperation(QStringLiteral("Working"), -1);
    setStatus(QStringLiteral("Working…"));

    m_process = new QProcess(this);
    QProcess *process = m_process;

    connect(process, &QProcess::readyReadStandardOutput, this, [this, process] {
        const QByteArray chunk = process->readAllStandardOutput();
        m_liveStdout += chunk;
        if (m_parseProgress)
            parseOperationProgress(chunk);
    });

    connect(process, &QProcess::finished, this,
            [this, process, completion = std::move(completion)](int code, QProcess::ExitStatus status) mutable {
        const QByteArray tail = process->readAllStandardOutput();
        if (!tail.isEmpty()) {
            m_liveStdout += tail;
            if (m_parseProgress) parseOperationProgress(tail);
        }
        const QByteArray out = m_liveStdout;
        m_liveStdout.clear();
        const QByteArray err = process->readAllStandardError();
        if (completion)
            completion(code, status, out, err);
        m_parseProgress = false;
        if (m_process == process)
            m_process = nullptr;
        process->deleteLater();
    });

    connect(process, &QProcess::errorOccurred, this, [this, process](QProcess::ProcessError) {
        if (process->state() == QProcess::NotRunning) {
            const QString message = process->errorString();
            setBusy(false);
            setStatus(message);
            emit operationFinished(false, message);
            if (m_process == process)
                m_process = nullptr;
            process->deleteLater();
        }
    });

    if (!workingDirectory.isEmpty())
        process->setWorkingDirectory(workingDirectory);

    process->start(program, arguments);
    if (!stdinData.isEmpty()) {
        if (process->waitForStarted(1500)) {
            process->write(stdinData);
            process->closeWriteChannel();
        }
    }
}

void FileManagerController::refreshLocal()
{
    QDir dir(m_currentPath);
    if (!dir.exists()) {
        setStatus(QStringLiteral("Path does not exist."));
        emit operationFinished(false, m_statusText);
        return;
    }

    m_currentPath = dir.absolutePath();
    emit currentPathChanged();

    QVector<FileEntry> entries;
    const QFileInfoList list = dir.entryInfoList(QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden | QDir::System,
                                                 QDir::DirsFirst | QDir::Name | QDir::IgnoreCase);
    entries.reserve(list.size());
    for (const QFileInfo &info : list) {
        FileEntry entry;
        entry.name = info.fileName();
        entry.path = info.absoluteFilePath();
        entry.permissions = modeToSymbolic(info);
        entry.owner = info.owner();
        entry.group = info.group();
        entry.size = info.size();
        entry.directory = info.isDir();
        entry.modified = info.lastModified();
        entries.push_back(std::move(entry));
    }

    m_entries.setEntries(std::move(entries));
    setStatus(QStringLiteral("%1 items").arg(m_entries.rowCount()));
}

void FileManagerController::refreshRemote()
{
    const QString command = QStringLiteral(
        "cd -- %1 || exit 2; "
        "printf 'PWD\\t%s\\n' \"$PWD\"; "
        "find . -mindepth 1 -maxdepth 1 -printf 'E\\t%y\\t%f\\t%s\\t%m\\t%u\\t%g\\t%T@\\n'")
        .arg(remoteCdTarget());

    runProcess(QStandardPaths::findExecutable(QStringLiteral("ssh")), sshBaseArgs() << target() << command,
               [this](int code, QProcess::ExitStatus status, const QByteArray &out, const QByteArray &err) {
        const bool ok = status == QProcess::NormalExit && code == 0;
        if (!ok) {
            setBusy(false);
            QString message = QString::fromLocal8Bit(err).trimmed();
            const bool waitingForAuth = message.contains(QStringLiteral("Permission denied"), Qt::CaseInsensitive)
                || message.contains(QStringLiteral("Control socket"), Qt::CaseInsensitive)
                || message.contains(QStringLiteral("master running"), Qt::CaseInsensitive);
            if (m_remote && waitingForAuth && m_authRetryRemaining > 0) {
                --m_authRetryRemaining;
                setStatus(QStringLiteral("Waiting for SSH authentication…"));
                m_authRetryTimer.start();
                return;
            }
            if (message.isEmpty())
                message = QStringLiteral("Unable to read remote directory.");
            else if (waitingForAuth)
                message = QStringLiteral("SSH file channel is not authenticated. Complete login in the terminal and try Refresh.");
            setStatus(message);
            emit operationFinished(false, message);
            return;
        }

        m_authRetryTimer.stop();
        m_authRetryRemaining = 0;

        QVector<FileEntry> entries;
        const QList<QByteArray> lines = out.split('\n');
        for (const QByteArray &line : lines) {
            if (line.startsWith("PWD\t")) {
                const QString path = QString::fromUtf8(line.mid(4));
                if (!path.isEmpty() && path != m_currentPath) {
                    m_currentPath = path;
                    emit currentPathChanged();
                }
                continue;
            }
            if (!line.startsWith("E\t"))
                continue;

            const QList<QByteArray> fields = line.split('\t');
            if (fields.size() < 8)
                continue;

            FileEntry entry;
            entry.directory = fields[1] == "d";
            entry.name = QString::fromUtf8(fields[2]);
            entry.path = pathJoin(m_currentPath, entry.name);
            entry.size = fields[3].toLongLong();
            entry.permissions = QString::fromUtf8(fields[4]);
            entry.owner = QString::fromUtf8(fields[5]);
            entry.group = QString::fromUtf8(fields[6]);
            entry.modified = QDateTime::fromSecsSinceEpoch(static_cast<qint64>(fields[7].toDouble()));
            entries.push_back(std::move(entry));
        }

        m_entries.setEntries(std::move(entries));
        setBusy(false);
        const QString message = QStringLiteral("%1 items").arg(m_entries.rowCount());
        setStatus(message);
        emit operationFinished(true, message);
    });
}

void FileManagerController::runFileOperation(const QString &localProgram, const QStringList &localArgs,
                                             const QString &remoteCommand, const QString &successMessage)
{
    if (m_busy)
        return;

    if (m_remote) {
        runProcess(QStandardPaths::findExecutable(QStringLiteral("ssh")), sshBaseArgs() << target() << remoteCommand,
                   [this, successMessage](int code, QProcess::ExitStatus status, const QByteArray &, const QByteArray &err) {
            const bool ok = status == QProcess::NormalExit && code == 0;
            finishAndRefresh(ok, ok ? successMessage : QString::fromLocal8Bit(err).trimmed());
        });
    } else {
        runProcess(localProgram, localArgs,
                   [this, successMessage](int code, QProcess::ExitStatus status, const QByteArray &, const QByteArray &err) {
            const bool ok = status == QProcess::NormalExit && code == 0;
            finishAndRefresh(ok, ok ? successMessage : QString::fromLocal8Bit(err).trimmed());
        });
    }
}

void FileManagerController::finishAndRefresh(bool success, const QString &message)
{
    if (success && !m_operationName.isEmpty())
        setOperationProgress(100, message);
    setBusy(false);
    setStatus(message.isEmpty() ? (success ? QStringLiteral("Done.") : QStringLiteral("Operation failed.")) : message);
    emit operationFinished(success, m_statusText);
    if (success)
        refresh();
}

void FileManagerController::clearClipboardEntry()
{
    if (m_clipboardPath.isEmpty())
        return;
    m_clipboardPath.clear();
    m_clipboardName.clear();
    m_clipboardCut = false;
    m_clipboardRemote = false;
    m_clipboardSessionKey.clear();
    emit clipboardChanged();
}
