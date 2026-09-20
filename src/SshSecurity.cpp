#include "SshSecurity.h"

#include <QDir>
#include <QFile>
#include <QFileDevice>
#include <QHash>
#include <QProcess>
#include <QSet>
#include <QStandardPaths>

namespace {
void addOption(QStringList &args, const QString &option)
{
    args << QStringLiteral("-o") << option;
}

QSet<QString> queryAlgorithms(const QString &category)
{
    static QHash<QString, QSet<QString>> cache;
    if (cache.contains(category))
        return cache.value(category);

    QSet<QString> result;
    const QString ssh = QStandardPaths::findExecutable(QStringLiteral("ssh"));
    if (!ssh.isEmpty()) {
        QProcess p;
        p.start(ssh, {QStringLiteral("-Q"), category});
        if (p.waitForFinished(3000) && p.exitStatus() == QProcess::NormalExit && p.exitCode() == 0) {
            const QString output = QString::fromLocal8Bit(p.readAllStandardOutput());
            for (const QString &line : output.split('\n', Qt::SkipEmptyParts))
                result.insert(line.trimmed());
        }
    }
    cache.insert(category, result);
    return result;
}

void addAvailableAlgorithms(QStringList &args,
                            const QString &optionName,
                            const QString &queryCategory,
                            const QStringList &candidates)
{
    const QSet<QString> available = queryAlgorithms(queryCategory);
    QStringList accepted;
    for (const QString &algorithm : candidates) {
        if (available.isEmpty() || available.contains(algorithm))
            accepted << algorithm;
    }
    if (!accepted.isEmpty())
        addOption(args, optionName + QStringLiteral("=+") + accepted.join(','));
}
}

QString SshSecurity::normalizeProfile(const QString &profile)
{
    const QString p = profile.trimmed().toLower();
    if (p == QStringLiteral("compatible") || p == QStringLiteral("legacy"))
        return p;
    return QStringLiteral("modern");
}

QString SshSecurity::controlPathTemplate()
{
#ifdef Q_OS_UNIX
    const QString base = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation);
    const QString dir = base.isEmpty() ? QDir::tempPath() : base;
    return QDir(dir).filePath(QStringLiteral("morixtrem-%C"));
#else
    return {};
#endif
}

QString SshSecurity::knownHostsFile()
{
    QString configRoot = QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation);
    if (configRoot.isEmpty())
        configRoot = QDir::home().filePath(QStringLiteral(".config"));

    const QString dirPath = QDir(configRoot).filePath(QStringLiteral("morixtrem"));
    QDir().mkpath(dirPath);
#ifdef Q_OS_UNIX
    QFile::setPermissions(dirPath, QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner);
#endif

    const QString filePath = QDir(dirPath).filePath(QStringLiteral("known_hosts"));
    QFile file(filePath);
    if (!file.exists()) {
        if (file.open(QIODevice::WriteOnly | QIODevice::Append))
            file.close();
    }
#ifdef Q_OS_UNIX
    if (QFile::exists(filePath))
        QFile::setPermissions(filePath, QFileDevice::ReadOwner | QFileDevice::WriteOwner);
#endif
    return filePath;
}

QString SshSecurity::hostKeyLookupName(const QString &host, int port)
{
    const QString normalizedHost = host.trimmed();
    if (port < 1 || port > 65535)
        port = 22;
    if (port == 22)
        return normalizedHost;
    return QStringLiteral("[%1]:%2").arg(normalizedHost).arg(port);
}

QStringList SshSecurity::commonOptions(int port,
                                       const QString &controlPath,
                                       const QString &profile,
                                       const QString &keyFile,
                                       bool batchMode)
{
    if (port < 1 || port > 65535)
        port = 22;

    QStringList args {QStringLiteral("-p"), QString::number(port)};

    // MoriXterm owns a dedicated known_hosts file. First-seen host keys are
    // accepted automatically, but changed keys remain a hard failure until the
    // user explicitly replaces the stored key from the in-app warning dialog.
    addOption(args, QStringLiteral("StrictHostKeyChecking=accept-new"));
    addOption(args, QStringLiteral("UserKnownHostsFile=") + knownHostsFile());
#ifdef Q_OS_WIN
    addOption(args, QStringLiteral("GlobalKnownHostsFile=NUL"));
#else
    addOption(args, QStringLiteral("GlobalKnownHostsFile=/dev/null"));
#endif
    addOption(args, QStringLiteral("HashKnownHosts=yes"));
    addOption(args, QStringLiteral("UpdateHostKeys=yes"));
    addOption(args, QStringLiteral("VisualHostKey=yes"));
    addOption(args, QStringLiteral("ServerAliveInterval=30"));
    addOption(args, QStringLiteral("ServerAliveCountMax=3"));
    addOption(args, QStringLiteral("ConnectTimeout=10"));
    // Remote sessions should not silently inherit powerful forwarding features.
    addOption(args, QStringLiteral("ForwardAgent=no"));
    addOption(args, QStringLiteral("ForwardX11=no"));
    addOption(args, QStringLiteral("ForwardX11Trusted=no"));
    addOption(args, QStringLiteral("PermitLocalCommand=no"));

#ifdef Q_OS_UNIX
    if (!controlPath.isEmpty()) {
        addOption(args, QStringLiteral("ControlMaster=auto"));
        // Reuse the connection only while the owning SSH tab is alive. This lets
        // the file manager share authentication without leaving a background
        // master connection behind after the user closes the tab.
        addOption(args, QStringLiteral("ControlPersist=no"));
        addOption(args, QStringLiteral("ControlPath=") + controlPath);
    }
#endif

    if (batchMode)
        addOption(args, QStringLiteral("BatchMode=yes"));

    if (!keyFile.trimmed().isEmpty()) {
        args << QStringLiteral("-i") << keyFile.trimmed();
        addOption(args, QStringLiteral("IdentitiesOnly=yes"));
    }

    const QString normalized = normalizeProfile(profile);
    if (normalized == QStringLiteral("compatible")) {
        addAvailableAlgorithms(args, QStringLiteral("HostKeyAlgorithms"), QStringLiteral("key"),
                               {QStringLiteral("ssh-rsa")});
        addAvailableAlgorithms(args, QStringLiteral("PubkeyAcceptedAlgorithms"), QStringLiteral("key"),
                               {QStringLiteral("ssh-rsa")});
        addAvailableAlgorithms(args, QStringLiteral("KexAlgorithms"), QStringLiteral("kex"),
                               {QStringLiteral("diffie-hellman-group14-sha1")});
        addAvailableAlgorithms(args, QStringLiteral("MACs"), QStringLiteral("mac"),
                               {QStringLiteral("hmac-sha1")});
    } else if (normalized == QStringLiteral("legacy")) {
        addAvailableAlgorithms(args, QStringLiteral("HostKeyAlgorithms"), QStringLiteral("key"),
                               {QStringLiteral("ssh-rsa"), QStringLiteral("ssh-dss")});
        addAvailableAlgorithms(args, QStringLiteral("PubkeyAcceptedAlgorithms"), QStringLiteral("key"),
                               {QStringLiteral("ssh-rsa"), QStringLiteral("ssh-dss")});
        addAvailableAlgorithms(args, QStringLiteral("KexAlgorithms"), QStringLiteral("kex"),
                               {QStringLiteral("diffie-hellman-group14-sha1"),
                                QStringLiteral("diffie-hellman-group1-sha1"),
                                QStringLiteral("diffie-hellman-group-exchange-sha1")});
        addAvailableAlgorithms(args, QStringLiteral("Ciphers"), QStringLiteral("cipher"),
                               {QStringLiteral("aes128-cbc"), QStringLiteral("aes192-cbc"),
                                QStringLiteral("aes256-cbc"), QStringLiteral("3des-cbc")});
        addAvailableAlgorithms(args, QStringLiteral("MACs"), QStringLiteral("mac"),
                               {QStringLiteral("hmac-sha1"), QStringLiteral("hmac-sha1-96")});
    }
    return args;
}

QStringList SshSecurity::clientArguments(const QString &host,
                                         const QString &user,
                                         int port,
                                         const QString &controlPath,
                                         const QString &profile,
                                         const QString &keyFile)
{
    QStringList args = commonOptions(port, controlPath, profile, keyFile, false);
    const QString target = user.trimmed().isEmpty() ? host.trimmed()
                                                    : user.trimmed() + QStringLiteral("@") + host.trimmed();
    args << target;
    return args;
}

QStringList SshSecurityController::buildArguments(const QString &host,
                                                  const QString &user,
                                                  int port,
                                                  const QString &profile,
                                                  const QString &keyFile) const
{
    return SshSecurity::clientArguments(host, user, port, controlPathTemplate(), profile, keyFile);
}

QString SshSecurityController::profileWarning(const QString &profile) const
{
    const QString p = SshSecurity::normalizeProfile(profile);
    if (p == QStringLiteral("legacy"))
        return QStringLiteral("Legacy mode requests only deprecated algorithms that your installed OpenSSH still reports as available. Use it only for equipment that cannot be upgraded.");
    if (p == QStringLiteral("compatible"))
        return QStringLiteral("Compatible mode adds available RSA/SHA-1, group14/SHA-1 and HMAC-SHA1 fallbacks while keeping modern defaults enabled.");
    return QStringLiteral("Modern mode uses the algorithms enabled by your installed OpenSSH client and does not weaken its defaults.");
}

void SshSecurityController::setLastError(const QString &message)
{
    if (m_lastError == message)
        return;
    m_lastError = message;
    emit lastErrorChanged();
}

bool SshSecurityController::replaceHostKey(const QString &host, int port)
{
    const QString cleanHost = host.trimmed();
    if (cleanHost.isEmpty()) {
        setLastError(QStringLiteral("SSH host is empty."));
        return false;
    }
    if (port < 1 || port > 65535)
        port = 22;

    const QString keygen = QStandardPaths::findExecutable(QStringLiteral("ssh-keygen"));
    if (keygen.isEmpty()) {
        setLastError(QStringLiteral("ssh-keygen was not found. Install the OpenSSH client package."));
        return false;
    }

    const QString filePath = SshSecurity::knownHostsFile();
    const QString lookup = SshSecurity::hostKeyLookupName(cleanHost, port);

    QProcess process;
    process.start(keygen, {QStringLiteral("-f"), filePath, QStringLiteral("-R"), lookup});
    if (!process.waitForStarted(3000)) {
        setLastError(QStringLiteral("Could not start ssh-keygen: %1").arg(process.errorString()));
        return false;
    }
    if (!process.waitForFinished(5000)) {
        process.kill();
        process.waitForFinished(1000);
        setLastError(QStringLiteral("Timed out while removing the stored SSH host key."));
        return false;
    }

    const QByteArray err = process.readAllStandardError();
    if (process.exitStatus() != QProcess::NormalExit || process.exitCode() != 0) {
        QString detail = QString::fromLocal8Bit(err).trimmed();
        if (detail.isEmpty())
            detail = QStringLiteral("ssh-keygen exited with code %1.").arg(process.exitCode());
        setLastError(detail);
        return false;
    }

#ifdef Q_OS_UNIX
    QFile::setPermissions(filePath, QFileDevice::ReadOwner | QFileDevice::WriteOwner);
#endif
    setLastError(QString());
    return true;
}
