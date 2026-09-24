#include "FtpClientController.h"

#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QTimer>
#include <QUrl>

#include <algorithm>
#include <utility>

namespace {
QString urlToLocalPath(const QUrl &url)
{
    return url.isLocalFile() ? url.toLocalFile() : url.toString();
}

QString permissionsFromUnixMode(const QString &mode)
{
    if (mode.size() >= 10)
        return mode.mid(1, 9);
    return QStringLiteral("---------");
}
}

FtpClientController::FtpClientController(QObject *parent)
    : QObject(parent), m_entries(this)
{
}

FtpClientController::~FtpClientController()
{
    if (m_commandProcess) {
        m_commandProcess->kill();
        m_commandProcess->deleteLater();
    }
    for (TransferJob *job : std::as_const(m_jobs)) {
        if (job->process) {
            job->process->kill();
            job->process->deleteLater();
        }
        delete job;
    }
    m_password.fill(QChar('\0'));
}

void FtpClientController::configure(const QString &protocol,
                                    const QString &host,
                                    const QString &user,
                                    int port,
                                    const QString &password,
                                    const QString &keyFile,
                                    bool ftpTls,
                                    bool passive,
                                    int maxParallel,
                                    bool overwriteExisting,
                                    bool ignoreTlsCertificate)
{
    const QString normalized = protocol.trimmed().toLower();
    m_protocol = normalized == QStringLiteral("sftp") ? QStringLiteral("sftp") : QStringLiteral("ftp");
    m_host = host.trimmed();
    m_user = user.trimmed();
    m_port = port > 0 && port <= 65535 ? port : (m_protocol == QStringLiteral("sftp") ? 22 : 21);
    m_password.fill(QChar('\0'));
    m_password = password;
    m_keyFile = keyFile.trimmed();
    m_ftpTls = ftpTls;
    m_ignoreTlsCertificate = ignoreTlsCertificate;
    m_tlsPromptIssued = false;
    m_passive = passive;
    setMaxParallel(maxParallel);
    setOverwriteExisting(overwriteExisting);
    m_currentPath = m_protocol == QStringLiteral("sftp") ? QStringLiteral("~") : QStringLiteral("/");
    m_sessionLabel = QStringLiteral("%1 • %2@%3:%4")
        .arg(m_protocol.toUpper(), m_user.isEmpty() ? QStringLiteral("anonymous") : m_user, m_host)
        .arg(m_port);
    m_entries.setEntries({});
    emit sessionChanged();
    emit currentPathChanged();
    // Defer the first listing until QML has finished binding the session
    // properties and the workspace is fully constructed.
    QTimer::singleShot(0, this, [this] { refresh(); });
}

QVariantList FtpClientController::transfers() const
{
    QVariantList result;
    result.reserve(m_jobs.size());
    for (TransferJob *job : m_jobs) {
        QVariantMap item;
        item.insert(QStringLiteral("id"), job->id);
        item.insert(QStringLiteral("direction"), job->direction);
        item.insert(QStringLiteral("label"), job->label);
        item.insert(QStringLiteral("progress"), job->progress);
        item.insert(QStringLiteral("state"), job->state);
        item.insert(QStringLiteral("detail"), job->detail);
        result.push_back(item);
    }
    return result;
}

int FtpClientController::activeTransferCount() const
{
    int count = 0;
    for (TransferJob *job : m_jobs) {
        if (job->state == QStringLiteral("Queued") || job->state == QStringLiteral("Running"))
            ++count;
    }
    return count;
}

int FtpClientController::overallProgress() const
{
    int count = 0;
    int total = 0;
    for (TransferJob *job : m_jobs) {
        if (job->state == QStringLiteral("Queued") || job->state == QStringLiteral("Running")) {
            ++count;
            total += qBound(0, job->progress, 100);
        }
    }
    if (count == 0)
        return 100;
    return total / count;
}

void FtpClientController::setMaxParallel(int value)
{
    const int bounded = qBound(1, value, 8);
    if (m_maxParallel == bounded)
        return;
    m_maxParallel = bounded;
    emit maxParallelChanged();
    startQueuedTransfers();
}

void FtpClientController::setOverwriteExisting(bool value)
{
    if (m_overwriteExisting == value)
        return;
    m_overwriteExisting = value;
    emit overwriteExistingChanged();
}

QString FtpClientController::curlProgram() const
{
    return QStandardPaths::findExecutable(QStringLiteral("curl"));
}

QByteArray FtpClientController::escapeCurlConfig(const QString &value)
{
    QByteArray out = value.toUtf8();
    out.replace("\\", "\\\\");
    out.replace("\"", "\\\"");
    out.replace("\r", "");
    out.replace("\n", "");
    return out;
}

QByteArray FtpClientController::secretConfig() const
{
    QByteArray config;
    config += "user = \"";
    config += escapeCurlConfig(m_user + QStringLiteral(":") + m_password);
    config += "\"\n";
    return config;
}

QString FtpClientController::normalizeRemotePath(const QString &path) const
{
    QString clean = path.trimmed();
    if (m_protocol == QStringLiteral("sftp")) {
        if (clean.isEmpty() || clean == QStringLiteral("."))
            return QStringLiteral("~");
        if (clean == QStringLiteral("~") || clean.startsWith(QStringLiteral("~/")) || clean.startsWith('/'))
            return QDir::cleanPath(clean);
        return QDir::cleanPath(m_currentPath + QStringLiteral("/") + clean);
    }
    if (clean.isEmpty())
        return QStringLiteral("/");
    if (!clean.startsWith('/'))
        clean.prepend('/');
    return QDir::cleanPath(clean);
}

QString FtpClientController::joinRemote(const QString &base, const QString &name) const
{
    if (base == QStringLiteral("/") || base == QStringLiteral("~"))
        return base + (base.endsWith('/') ? QString() : QStringLiteral("/")) + name;
    return base.endsWith('/') ? base + name : base + QStringLiteral("/") + name;
}

QString FtpClientController::remoteUrl(const QString &path, bool directory) const
{
    QUrl url;
    url.setScheme(m_protocol);
    url.setHost(m_host);
    url.setPort(m_port);

    QString p = normalizeRemotePath(path);
    if (m_protocol == QStringLiteral("sftp") && (p == QStringLiteral("~") || p.startsWith(QStringLiteral("~/")))) {
        p = QStringLiteral("/~") + p.mid(1);
    }
    if (!p.startsWith('/'))
        p.prepend('/');
    if (directory && !p.endsWith('/'))
        p += '/';
    url.setPath(p);
    return url.toString(QUrl::FullyEncoded);
}

QStringList FtpClientController::commonCurlArgs() const
{
    QStringList args;
    args << QStringLiteral("--config") << QStringLiteral("-")
         << QStringLiteral("--connect-timeout") << QStringLiteral("15")
         << QStringLiteral("--retry") << QStringLiteral("1")
         << QStringLiteral("--retry-delay") << QStringLiteral("1");

    if (m_protocol == QStringLiteral("ftp")) {
        if (m_ftpTls) {
            args << QStringLiteral("--ssl-reqd");
            // Keep certificate verification enabled by default. This opt-in is
            // intentionally scoped to the current saved profile / running session,
            // matching the explicit trust flow exposed by the UI.
            if (m_ignoreTlsCertificate)
                args << QStringLiteral("--insecure");
        }
        if (!m_passive)
            args << QStringLiteral("--ftp-port") << QStringLiteral("-");
    } else {
        if (!m_keyFile.isEmpty())
            args << QStringLiteral("--key") << m_keyFile;
        const QString knownHosts = QDir::home().filePath(QStringLiteral(".ssh/known_hosts"));
        if (QFileInfo::exists(knownHosts))
            args << QStringLiteral("--knownhosts") << knownHosts;
    }
    return args;
}

void FtpClientController::writeSecretConfig(QProcess *process) const
{
    if (!process)
        return;
    if (process->waitForStarted(2000)) {
        QByteArray secret = secretConfig();
        process->write(secret);
        secret.fill('\0');
        process->closeWriteChannel();
    }
}

bool FtpClientController::isTlsCertificateError(int exitCode, const QByteArray &stderrData) const
{
    if (m_protocol != QStringLiteral("ftp") || !m_ftpTls || m_ignoreTlsCertificate)
        return false;

    // libcurl uses exit code 60 for peer certificate verification failures.
    // Keep text matching as a fallback because distro builds can wrap the message.
    if (exitCode == 60)
        return true;

    const QByteArray lower = stderrData.toLower();
    return lower.contains("ssl certificate problem") ||
           lower.contains("certificate subject name") ||
           lower.contains("no alternative certificate subject name") ||
           lower.contains("unable to get local issuer certificate") ||
           lower.contains("self-signed certificate");
}

QString FtpClientController::friendlyTlsError(const QByteArray &stderrData) const
{
    QString detail = QString::fromLocal8Bit(stderrData).trimmed();
    if (detail.isEmpty())
        detail = QStringLiteral("The FTPS certificate could not be verified for %1.").arg(m_host);
    return QStringLiteral("TLS certificate verification failed for %1:%2.\n\n%3")
        .arg(m_host)
        .arg(m_port)
        .arg(detail);
}

void FtpClientController::trustTlsForCurrentSession()
{
    if (m_protocol != QStringLiteral("ftp") || !m_ftpTls)
        return;
    if (!m_ignoreTlsCertificate) {
        m_ignoreTlsCertificate = true;
        emit tlsSecurityChanged();
    }
    m_tlsPromptIssued = false;
    setStatus(QStringLiteral("Certificate verification bypassed for this FTPS session."));
    QMetaObject::invokeMethod(this, &FtpClientController::refresh, Qt::QueuedConnection);
}

void FtpClientController::setStatus(const QString &status)
{
    if (m_statusText == status)
        return;
    m_statusText = status;
    emit statusTextChanged();
}

void FtpClientController::setBusy(bool busy)
{
    if (m_busy == busy)
        return;
    m_busy = busy;
    emit busyChanged();
}

void FtpClientController::refresh()
{
    if (m_busy)
        return;
    if (m_host.isEmpty()) {
        setStatus(QStringLiteral("Host is empty."));
        return;
    }
    if (curlProgram().isEmpty()) {
        setStatus(QStringLiteral("curl is required for FTP/SFTP sessions."));
        emit operationFinished(false, m_statusText);
        return;
    }
    runListCommand(m_protocol == QStringLiteral("ftp"));
}

void FtpClientController::runListCommand(bool ftpMlsd)
{
    if (m_commandProcess)
        return;

    setBusy(true);
    setStatus(QStringLiteral("Loading remote directory…"));
    m_commandProcess = new QProcess(this);
    QProcess *process = m_commandProcess;

    QStringList args = commonCurlArgs();
    args << QStringLiteral("--silent") << QStringLiteral("--show-error") << QStringLiteral("--fail-with-body");
    if (ftpMlsd)
        args << QStringLiteral("--request") << QStringLiteral("MLSD");
    args << QStringLiteral("--url") << remoteUrl(m_currentPath, true);

    connect(process, &QProcess::finished, this,
            [this, process, ftpMlsd](int code, QProcess::ExitStatus status) {
        const QByteArray out = process->readAllStandardOutput();
        const QByteArray err = process->readAllStandardError();
        const bool ok = status == QProcess::NormalExit && code == 0;
        if (ok) {
            parseListing(out, ftpMlsd);
            setStatus(QStringLiteral("%1 items • %2").arg(m_entries.rowCount()).arg(m_protocol.toUpper()));
        } else if (isTlsCertificateError(code, err)) {
            const QString message = friendlyTlsError(err);
            setStatus(QStringLiteral("TLS certificate verification failed."));
            if (!m_tlsPromptIssued) {
                m_tlsPromptIssued = true;
                emit tlsCertificateError(message);
            }
            emit operationFinished(false, message);
        } else if (ftpMlsd) {
            // Some FTP servers do not implement MLSD. Fall back to a regular LIST request.
            // Certificate failures are handled above and must never be mistaken for an
            // unsupported MLSD command.
            m_commandProcess = nullptr;
            process->deleteLater();
            setBusy(false);
            runListCommand(false);
            return;
        } else {
            setStatus(QString::fromLocal8Bit(err).trimmed());
            emit operationFinished(false, m_statusText);
        }
        setBusy(false);
        if (m_commandProcess == process)
            m_commandProcess = nullptr;
        process->deleteLater();
    });
    connect(process, &QProcess::errorOccurred, this, [this, process](QProcess::ProcessError) {
        if (process->state() != QProcess::NotRunning)
            return;
        setBusy(false);
        setStatus(process->errorString());
        emit operationFinished(false, m_statusText);
        if (m_commandProcess == process)
            m_commandProcess = nullptr;
        process->deleteLater();
    });

    process->start(curlProgram(), args);
    writeSecretConfig(process);
}

void FtpClientController::parseListing(const QByteArray &output, bool mlsd)
{
    QVector<FileEntry> entries = mlsd ? parseMlsd(output, m_currentPath) : parseLongListing(output, m_currentPath);
    if (entries.isEmpty() && !output.trimmed().isEmpty()) {
        const QList<QByteArray> lines = output.split('\n');
        for (QByteArray line : lines) {
            line = line.trimmed();
            if (line.isEmpty() || line == "." || line == "..")
                continue;
            FileEntry e;
            e.name = QString::fromUtf8(line);
            e.path = joinRemote(m_currentPath, e.name);
            e.permissions = QStringLiteral("---------");
            entries.push_back(e);
        }
    }
    m_entries.setEntries(std::move(entries));
}

QVector<FileEntry> FtpClientController::parseMlsd(const QByteArray &output, const QString &parentPath) const
{
    QVector<FileEntry> entries;
    const QList<QByteArray> lines = output.split('\n');
    for (QByteArray raw : lines) {
        raw = raw.trimmed();
        if (raw.isEmpty())
            continue;
        const int split = raw.indexOf(' ');
        if (split <= 0)
            continue;
        const QByteArray factsPart = raw.left(split);
        const QString name = QString::fromUtf8(raw.mid(split + 1).trimmed());
        if (name.isEmpty() || name == QStringLiteral(".") || name == QStringLiteral(".."))
            continue;

        QHash<QByteArray, QByteArray> facts;
        const QList<QByteArray> chunks = factsPart.split(';');
        for (const QByteArray &chunk : chunks) {
            const int eq = chunk.indexOf('=');
            if (eq > 0)
                facts.insert(chunk.left(eq).toLower(), chunk.mid(eq + 1));
        }
        const QByteArray type = facts.value("type").toLower();
        if (type == "cdir" || type == "pdir")
            continue;

        FileEntry e;
        e.name = name;
        e.path = joinRemote(parentPath, name);
        e.directory = type == "dir";
        e.size = facts.value("size").toLongLong();
        e.permissions = QString::fromLatin1(facts.value("unix.mode"));
        if (e.permissions.isEmpty())
            e.permissions = QStringLiteral("---------");
        entries.push_back(std::move(e));
    }
    return entries;
}

QVector<FileEntry> FtpClientController::parseLongListing(const QByteArray &output, const QString &parentPath) const
{
    QVector<FileEntry> entries;
    static const QRegularExpression unixRx(
        QStringLiteral("^([bcdlps-][rwxStTs-]{9})\\s+\\d+\\s+(\\S+)\\s+(\\S+)\\s+(\\d+)\\s+\\S+\\s+\\d+\\s+[\\d:]+\\s+(.+)$"));
    static const QRegularExpression dosRx(
        QStringLiteral("^(\\d{2}-\\d{2}-\\d{2})\\s+(\\d{2}:\\d{2}[AP]M)\\s+(<DIR>|\\d+)\\s+(.+)$"),
        QRegularExpression::CaseInsensitiveOption);

    const QString text = QString::fromUtf8(output);
    const QStringList lines = text.split('\n', Qt::SkipEmptyParts);
    for (const QString &raw : lines) {
        const QString line = raw.trimmed();
        auto unixMatch = unixRx.match(line);
        if (unixMatch.hasMatch()) {
            FileEntry e;
            const QString mode = unixMatch.captured(1);
            e.directory = mode.startsWith('d');
            e.permissions = permissionsFromUnixMode(mode);
            e.owner = unixMatch.captured(2);
            e.group = unixMatch.captured(3);
            e.size = unixMatch.captured(4).toLongLong();
            e.name = unixMatch.captured(5);
            const int arrow = e.name.indexOf(QStringLiteral(" -> "));
            if (arrow > 0)
                e.name = e.name.left(arrow);
            if (e.name == QStringLiteral(".") || e.name == QStringLiteral(".."))
                continue;
            e.path = joinRemote(parentPath, e.name);
            entries.push_back(std::move(e));
            continue;
        }
        auto dosMatch = dosRx.match(line);
        if (dosMatch.hasMatch()) {
            FileEntry e;
            e.directory = dosMatch.captured(3).compare(QStringLiteral("<DIR>"), Qt::CaseInsensitive) == 0;
            e.size = e.directory ? 0 : dosMatch.captured(3).toLongLong();
            e.name = dosMatch.captured(4);
            e.path = joinRemote(parentPath, e.name);
            e.permissions = QStringLiteral("---------");
            entries.push_back(std::move(e));
        }
    }
    return entries;
}

void FtpClientController::goUp()
{
    if (m_busy)
        return;
    if (m_currentPath == QStringLiteral("/") || m_currentPath == QStringLiteral("~"))
        return;
    const int slash = m_currentPath.lastIndexOf('/');
    if (slash <= 0) {
        m_currentPath = m_protocol == QStringLiteral("sftp") ? QStringLiteral("~") : QStringLiteral("/");
    } else {
        m_currentPath = m_currentPath.left(slash);
        if (m_currentPath.isEmpty())
            m_currentPath = QStringLiteral("/");
    }
    emit currentPathChanged();
    refresh();
}

void FtpClientController::goToPath(const QString &path)
{
    if (m_busy || path.trimmed().isEmpty())
        return;
    m_currentPath = normalizeRemotePath(path);
    emit currentPathChanged();
    refresh();
}

void FtpClientController::openEntry(int row)
{
    const FileEntry *entry = m_entries.entryAt(row);
    if (!entry || !entry->directory || m_busy)
        return;
    m_currentPath = entry->path;
    emit currentPathChanged();
    refresh();
}

QString FtpClientController::entryPath(int row) const
{
    const FileEntry *entry = m_entries.entryAt(row);
    return entry ? entry->path : QString();
}

QString FtpClientController::entryName(int row) const
{
    const FileEntry *entry = m_entries.entryAt(row);
    return entry ? entry->name : QString();
}

bool FtpClientController::entryIsDirectory(int row) const
{
    const FileEntry *entry = m_entries.entryAt(row);
    return entry && entry->directory;
}

void FtpClientController::runRemoteCommand(const QStringList &quoteCommands, const QString &successMessage)
{
    runRemoteCommandQueue(quoteCommands, successMessage);
}

void FtpClientController::runRemoteCommandQueue(QStringList remainingCommands, const QString &successMessage)
{
    if (m_busy || curlProgram().isEmpty())
        return;
    if (remainingCommands.isEmpty()) {
        emit operationFinished(false, QStringLiteral("Nothing to do."));
        return;
    }

    constexpr int batchSize = 40;
    const QStringList batch = remainingCommands.mid(0, batchSize);
    remainingCommands = remainingCommands.mid(batchSize);

    setBusy(true);
    setStatus(remainingCommands.isEmpty()
                  ? QStringLiteral("Working…")
                  : QStringLiteral("Working… %1 commands remaining").arg(remainingCommands.size()));
    m_commandProcess = new QProcess(this);
    QProcess *process = m_commandProcess;
    QStringList args = commonCurlArgs();
    args << QStringLiteral("--silent") << QStringLiteral("--show-error") << QStringLiteral("--fail-with-body");
    for (const QString &command : batch)
        args << QStringLiteral("--quote") << command;
    args << QStringLiteral("--url") << remoteUrl(m_currentPath, true);

    connect(process, &QProcess::finished, this,
            [this, process, successMessage, remainingCommands](int code, QProcess::ExitStatus status) {
        const bool ok = status == QProcess::NormalExit && code == 0;
        const QByteArray err = process->readAllStandardError();
        const QString message = ok ? successMessage
                                   : (isTlsCertificateError(code, err) ? friendlyTlsError(err)
                                                                       : QString::fromLocal8Bit(err).trimmed());
        if (!ok && isTlsCertificateError(code, err) && !m_tlsPromptIssued) {
            m_tlsPromptIssued = true;
            emit tlsCertificateError(message);
        }
        setBusy(false);
        if (m_commandProcess == process)
            m_commandProcess = nullptr;
        process->deleteLater();

        if (!ok) {
            setStatus(message.isEmpty() ? process->errorString() : message);
            emit operationFinished(false, m_statusText);
            return;
        }

        if (!remainingCommands.isEmpty()) {
            runRemoteCommandQueue(remainingCommands, successMessage);
            return;
        }

        setStatus(successMessage);
        emit operationFinished(true, successMessage);
        refresh();
    });
    connect(process, &QProcess::errorOccurred, this, [this, process](QProcess::ProcessError) {
        if (process->state() != QProcess::NotRunning)
            return;
        setBusy(false);
        setStatus(process->errorString());
        emit operationFinished(false, m_statusText);
        if (m_commandProcess == process)
            m_commandProcess = nullptr;
        process->deleteLater();
    });

    process->start(curlProgram(), args);
    writeSecretConfig(process);
}

QString FtpClientController::relativeToCurrent(const QString &absolutePath) const
{
    QString current = m_currentPath;
    QString path = absolutePath;
    while (current.endsWith('/'))
        current.chop(1);
    while (path.endsWith('/') && path.size() > 1)
        path.chop(1);

    if (path == current)
        return {};
    if (current == QStringLiteral("/") && path.startsWith('/'))
        return path.mid(1);
    if (path.startsWith(current + QLatin1Char('/')))
        return path.mid(current.size() + 1);
    return path.section('/', -1);
}

bool FtpClientController::listRemoteDirectory(const QString &absolutePath, QVector<FileEntry> &entries, QString *errorMessage)
{
    entries.clear();
    if (curlProgram().isEmpty()) {
        if (errorMessage)
            *errorMessage = QStringLiteral("curl is required for FTP/SFTP sessions.");
        return false;
    }

    auto runList = [&](bool ftpMlsd) -> bool {
        QProcess process;
        QStringList args = commonCurlArgs();
        args << QStringLiteral("--silent") << QStringLiteral("--show-error") << QStringLiteral("--fail-with-body");
        if (ftpMlsd)
            args << QStringLiteral("--request") << QStringLiteral("MLSD");
        args << QStringLiteral("--url") << remoteUrl(absolutePath, true);
        process.start(curlProgram(), args);
        writeSecretConfig(&process);
        if (!process.waitForFinished(60000)) {
            process.kill();
            process.waitForFinished(2000);
            if (errorMessage)
                *errorMessage = QStringLiteral("Timed out while listing %1.").arg(absolutePath);
            return false;
        }
        const QByteArray out = process.readAllStandardOutput();
        const QByteArray err = process.readAllStandardError();
        if (process.exitStatus() != QProcess::NormalExit || process.exitCode() != 0) {
            if (ftpMlsd && m_protocol == QStringLiteral("ftp"))
                return false;
            if (errorMessage) {
                *errorMessage = QString::fromLocal8Bit(err).trimmed();
                if (errorMessage->isEmpty())
                    *errorMessage = process.errorString();
            }
            return false;
        }
        entries = ftpMlsd ? parseMlsd(out, absolutePath) : parseLongListing(out, absolutePath);
        if (entries.isEmpty() && !out.trimmed().isEmpty()) {
            const QList<QByteArray> lines = out.split('\n');
            for (QByteArray line : lines) {
                line = line.trimmed();
                if (line.isEmpty() || line == "." || line == "..")
                    continue;
                FileEntry e;
                e.name = QString::fromUtf8(line);
                e.path = joinRemote(absolutePath, e.name);
                e.permissions = QStringLiteral("---------");
                entries.push_back(e);
            }
        }
        return true;
    };

    if (m_protocol == QStringLiteral("ftp")) {
        if (runList(true))
            return true;
        return runList(false);
    }
    return runList(false);
}

void FtpClientController::appendRecursiveDeleteCommands(const QString &absolutePath, bool directory,
                                                        QStringList &commands, QString *errorMessage)
{
    const QString target = relativeToCurrent(absolutePath);
    if (target.isEmpty() || target == QStringLiteral(".") || target == QStringLiteral("..")
        || target.contains(QStringLiteral("../")) || target.startsWith(QStringLiteral("../"))) {
        if (errorMessage)
            *errorMessage = QStringLiteral("Refusing to delete an unsafe path.");
        return;
    }

    if (directory) {
        QVector<FileEntry> children;
        QString listError;
        if (!listRemoteDirectory(absolutePath, children, &listError)) {
            if (errorMessage)
                *errorMessage = listError.isEmpty() ? QStringLiteral("Could not list folder contents.") : listError;
            return;
        }
        for (const FileEntry &child : children) {
            appendRecursiveDeleteCommands(child.path, child.directory, commands, errorMessage);
            if (errorMessage && !errorMessage->isEmpty())
                return;
        }
        commands << (m_protocol == QStringLiteral("sftp")
                         ? QStringLiteral("rmdir %1").arg(target)
                         : QStringLiteral("RMD %1").arg(target));
        return;
    }

    commands << (m_protocol == QStringLiteral("sftp")
                     ? QStringLiteral("rm %1").arg(target)
                     : QStringLiteral("DELE %1").arg(target));
}

void FtpClientController::createFolder(const QString &name)
{
    const QString clean = name.trimmed();
    if (clean.isEmpty() || clean == QStringLiteral(".") || clean == QStringLiteral("..") || clean.contains('/') || clean.contains('\\')) {
        emit operationFinished(false, QStringLiteral("Invalid folder name."));
        return;
    }
    if (m_protocol == QStringLiteral("sftp"))
        runRemoteCommand({QStringLiteral("mkdir %1").arg(clean)}, QStringLiteral("Folder created."));
    else
        runRemoteCommand({QStringLiteral("MKD %1").arg(clean)}, QStringLiteral("Folder created."));
}

void FtpClientController::renameEntry(int row, const QString &newName)
{
    const FileEntry *entry = m_entries.entryAt(row);
    const QString clean = newName.trimmed();
    if (!entry || clean.isEmpty() || clean.contains('/') || clean.contains('\\')) {
        emit operationFinished(false, QStringLiteral("Invalid new name."));
        return;
    }
    if (m_protocol == QStringLiteral("sftp"))
        runRemoteCommand({QStringLiteral("rename %1 %2").arg(entry->name, clean)}, QStringLiteral("Renamed."));
    else
        runRemoteCommand({QStringLiteral("RNFR %1").arg(entry->name), QStringLiteral("RNTO %1").arg(clean)}, QStringLiteral("Renamed."));
}

void FtpClientController::deleteEntry(int row)
{
    deleteEntries(QVariantList{row});
}

void FtpClientController::deleteEntries(const QVariantList &rows)
{
    if (m_busy) {
        emit operationFinished(false, QStringLiteral("Another file operation is already running."));
        return;
    }
    if (rows.isEmpty()) {
        emit operationFinished(false, QStringLiteral("Select one or more files or folders."));
        return;
    }

    QStringList commands;
    QString error;
    int fileCount = 0;
    int folderCount = 0;
    for (const QVariant &value : rows) {
        const FileEntry *entry = m_entries.entryAt(value.toInt());
        if (!entry)
            continue;
        if (entry->directory)
            ++folderCount;
        else
            ++fileCount;
        appendRecursiveDeleteCommands(entry->path, entry->directory, commands, &error);
        if (!error.isEmpty()) {
            emit operationFinished(false, error);
            return;
        }
    }

    if (commands.isEmpty()) {
        emit operationFinished(false, QStringLiteral("Nothing to delete."));
        return;
    }

    setStatus(QStringLiteral("Preparing to delete %1 item(s)…").arg(fileCount + folderCount));
    const QString message = (fileCount + folderCount) == 1
        ? QStringLiteral("Deleted.")
        : QStringLiteral("Deleted %1 item(s).").arg(fileCount + folderCount);
    runRemoteCommandQueue(commands, message);
}

void FtpClientController::chmodEntry(int row, const QString &mode)
{
    const FileEntry *entry = m_entries.entryAt(row);
    static const QRegularExpression modeRx(QStringLiteral("^[0-7]{3,4}$"));
    if (!entry || m_protocol != QStringLiteral("sftp") || !modeRx.match(mode.trimmed()).hasMatch()) {
        emit operationFinished(false, QStringLiteral("chmod is available for SFTP and requires an octal mode such as 755."));
        return;
    }
    runRemoteCommand({QStringLiteral("chmod %1 %2").arg(mode.trimmed(), entry->name)}, QStringLiteral("Permissions changed."));
}

void FtpClientController::uploadPaths(const QVariantList &localPaths, bool overwrite)
{
    if (localPaths.isEmpty()) {
        emit operationFinished(false, QStringLiteral("Select one or more local files or folders."));
        return;
    }
    for (const QVariant &value : localPaths) {
        const QString path = value.toString();
        const QFileInfo info(path);
        if (!info.exists())
            continue;
        if (info.isDir())
            enqueueDirectoryUpload(info.absoluteFilePath(), joinRemote(m_currentPath, info.fileName()), overwrite);
        else
            enqueueFileUpload(info.absoluteFilePath(), joinRemote(m_currentPath, info.fileName()), overwrite);
    }
    setStatus(QStringLiteral("Transfer queue started."));
    emit transfersChanged();
    startQueuedTransfers();
}

void FtpClientController::enqueueDirectoryUpload(const QString &localDirectory, const QString &remoteDirectory, bool overwrite)
{
    QDir base(localDirectory);
    QDirIterator it(localDirectory, QDir::Files | QDir::NoDotAndDotDot | QDir::Hidden | QDir::System,
                    QDirIterator::Subdirectories);
    bool foundFile = false;
    while (it.hasNext()) {
        const QString file = it.next();
        foundFile = true;
        const QString relative = base.relativeFilePath(file).replace('\\', '/');
        enqueueFileUpload(file, joinRemote(remoteDirectory, relative), overwrite);
    }
    if (!foundFile) {
        setStatus(QStringLiteral("Empty directories are not transferred automatically; create the remote folder first if needed."));
    }
}

void FtpClientController::enqueueFileUpload(const QString &localFile, const QString &remoteFile, bool overwrite)
{
    auto *job = new TransferJob;
    job->id = m_nextJobId++;
    job->direction = QStringLiteral("Upload");
    job->label = QFileInfo(localFile).fileName();
    job->localPath = localFile;
    job->remotePath = remoteFile;
    job->overwrite = overwrite;
    m_jobs.push_back(job);
}

void FtpClientController::downloadRows(const QVariantList &rows, const QUrl &localFolderUrl, bool overwrite)
{
    const QString localFolder = urlToLocalPath(localFolderUrl);
    if (localFolder.isEmpty() || !QDir(localFolder).exists()) {
        emit operationFinished(false, QStringLiteral("Choose a valid local destination folder."));
        return;
    }
    for (const QVariant &value : rows) {
        const int row = value.toInt();
        const FileEntry *entry = m_entries.entryAt(row);
        if (!entry)
            continue;
        if (entry->directory) {
            emit operationFinished(false, QStringLiteral("Recursive remote folder download is not enabled in this build. Select files, or open the folder and download its contents."));
            continue;
        }
        enqueueFileDownload(entry->path, QDir(localFolder).filePath(entry->name), overwrite);
    }
    emit transfersChanged();
    startQueuedTransfers();
}

void FtpClientController::enqueueFileDownload(const QString &remoteFile, const QString &localFile, bool overwrite)
{
    auto *job = new TransferJob;
    job->id = m_nextJobId++;
    job->direction = QStringLiteral("Download");
    job->label = QFileInfo(localFile).fileName();
    job->localPath = localFile;
    job->remotePath = remoteFile;
    job->overwrite = overwrite;
    m_jobs.push_back(job);
}

void FtpClientController::startQueuedTransfers()
{
    int running = 0;
    for (TransferJob *job : m_jobs) {
        if (job->state == QStringLiteral("Running"))
            ++running;
    }
    for (TransferJob *job : m_jobs) {
        if (running >= m_maxParallel)
            break;
        if (job->state == QStringLiteral("Queued")) {
            startTransfer(job);
            ++running;
        }
    }
    emit transfersChanged();
}

void FtpClientController::startTransfer(TransferJob *job)
{
    if (!job)
        return;
    const QString curl = curlProgram();
    if (curl.isEmpty()) {
        finishTransfer(job, false, QStringLiteral("curl is not installed."));
        return;
    }

    job->process = new QProcess(this);
    job->state = QStringLiteral("Running");
    job->detail = job->direction == QStringLiteral("Upload") ? QStringLiteral("Uploading…") : QStringLiteral("Downloading…");
    job->progress = 0;

    QStringList args = commonCurlArgs();
    args << QStringLiteral("--show-error") << QStringLiteral("--fail-with-body")
         << QStringLiteral("--progress-bar") << QStringLiteral("--no-buffer");

    if (job->direction == QStringLiteral("Upload")) {
        // FTP STOR and SFTP uploads replace an existing target. This is the desired
        // behavior when overwrite is enabled. The temporary local source is never modified.
        args << QStringLiteral("--ftp-create-dirs")
             << QStringLiteral("--upload-file") << job->localPath
             << QStringLiteral("--url") << remoteUrl(job->remotePath, false);
    } else {
        const QFileInfo localInfo(job->localPath);
        if (localInfo.exists() && !job->overwrite) {
            finishTransfer(job, false, QStringLiteral("Local file already exists and overwrite is disabled."));
            return;
        }
        const QString tempFile = job->localPath + QStringLiteral(".morixtrem-part-%1").arg(job->id);
        job->detail = tempFile;
        args << QStringLiteral("--output") << tempFile
             << QStringLiteral("--url") << remoteUrl(job->remotePath, false);
    }

    QProcess *process = job->process;
    connect(process, &QProcess::readyReadStandardError, this, [this, job, process] {
        parseCurlProgress(job, process->readAllStandardError());
    });
    connect(process, &QProcess::finished, this, [this, job, process](int code, QProcess::ExitStatus status) {
        parseCurlProgress(job, process->readAllStandardError());
        if (job->state == QStringLiteral("Cancelled")) {
            if (job->process == process) job->process = nullptr;
            process->deleteLater();
            emit transfersChanged();
            startQueuedTransfers();
            return;
        }
        const bool ok = status == QProcess::NormalExit && code == 0;
        const QByteArray finalError = process->readAllStandardError();
        QString message;
        if (ok && job->direction == QStringLiteral("Download")) {
            const QString tempFile = job->detail;
            QFile::remove(job->localPath);
            if (!QFile::rename(tempFile, job->localPath)) {
                QFile::remove(tempFile);
                finishTransfer(job, false, QStringLiteral("Could not finalize the downloaded file."));
                return;
            }
            message = QStringLiteral("Downloaded.");
        } else if (ok) {
            message = QStringLiteral("Uploaded.");
        } else {
            if (isTlsCertificateError(code, finalError)) {
                message = friendlyTlsError(finalError);
                if (!m_tlsPromptIssued) {
                    m_tlsPromptIssued = true;
                    emit tlsCertificateError(message);
                }
            } else {
                message = QString::fromLocal8Bit(finalError).trimmed();
                if (message.isEmpty())
                    message = process->errorString();
            }
            if (job->direction == QStringLiteral("Download"))
                QFile::remove(job->detail);
        }
        finishTransfer(job, ok, message);
    });
    connect(process, &QProcess::errorOccurred, this, [this, job, process](QProcess::ProcessError) {
        if (process->state() == QProcess::NotRunning && job->state == QStringLiteral("Running"))
            finishTransfer(job, false, process->errorString());
    });

    process->start(curl, args);
    writeSecretConfig(process);
    emit transfersChanged();
}

void FtpClientController::parseCurlProgress(TransferJob *job, const QByteArray &chunk)
{
    if (!job || chunk.isEmpty())
        return;
    job->progressBuffer += chunk;
    job->progressBuffer.replace('\r', '\n');
    const QList<QByteArray> lines = job->progressBuffer.split('\n');
    if (!job->progressBuffer.endsWith('\n'))
        job->progressBuffer = lines.isEmpty() ? QByteArray() : lines.last();
    else
        job->progressBuffer.clear();

    static const QRegularExpression percentRx(QStringLiteral("(\\d{1,3}(?:\\.\\d+)?)%"));
    for (int i = 0; i < lines.size(); ++i) {
        if (i == lines.size() - 1 && !chunk.endsWith('\n') && !chunk.endsWith('\r'))
            break;
        const QString line = QString::fromLocal8Bit(lines.at(i));
        const auto match = percentRx.match(line);
        if (match.hasMatch()) {
            job->progress = qBound(0, qRound(match.captured(1).toDouble()), 100);
            emit transfersChanged();
        }
    }
}

void FtpClientController::finishTransfer(TransferJob *job, bool success, const QString &message)
{
    if (!job)
        return;
    if (job->process) {
        job->process->deleteLater();
        job->process = nullptr;
    }
    job->state = success ? QStringLiteral("Done") : QStringLiteral("Failed");
    job->progress = success ? 100 : job->progress;
    job->detail = message;
    setStatus(message);
    emit transfersChanged();
    emit operationFinished(success, message);
    if (success && job->direction == QStringLiteral("Upload"))
        QMetaObject::invokeMethod(this, &FtpClientController::refresh, Qt::QueuedConnection);
    startQueuedTransfers();
}

FtpClientController::TransferJob *FtpClientController::findJob(int id) const
{
    for (TransferJob *job : m_jobs) {
        if (job->id == id)
            return job;
    }
    return nullptr;
}

void FtpClientController::cancelTransfer(int jobId)
{
    TransferJob *job = findJob(jobId);
    if (!job || (job->state != QStringLiteral("Queued") && job->state != QStringLiteral("Running")))
        return;
    if (job->process)
        job->process->kill();
    job->state = QStringLiteral("Cancelled");
    job->detail = QStringLiteral("Cancelled by user.");
    if (job->direction == QStringLiteral("Download") && !job->detail.isEmpty())
        QFile::remove(job->localPath + QStringLiteral(".morixtrem-part-%1").arg(job->id));
    emit transfersChanged();
    startQueuedTransfers();
}

void FtpClientController::cancelAllTransfers()
{
    for (TransferJob *job : m_jobs) {
        if (job->state == QStringLiteral("Queued") || job->state == QStringLiteral("Running"))
            cancelTransfer(job->id);
    }
}

void FtpClientController::clearFinishedTransfers()
{
    for (int i = m_jobs.size() - 1; i >= 0; --i) {
        TransferJob *job = m_jobs.at(i);
        if (job->state == QStringLiteral("Done") || job->state == QStringLiteral("Failed") || job->state == QStringLiteral("Cancelled")) {
            m_jobs.removeAt(i);
            delete job;
        }
    }
    emit transfersChanged();
}

void FtpClientController::pruneJobs()
{
    while (m_jobs.size() > 100) {
        TransferJob *job = m_jobs.first();
        if (job->state == QStringLiteral("Queued") || job->state == QStringLiteral("Running"))
            break;
        m_jobs.removeFirst();
        delete job;
    }
}
