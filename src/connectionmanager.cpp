#include "connectionmanager.h"

#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QStandardPaths>

ConnectionManager::ConnectionManager(QObject *parent)
    : QObject(parent)
{
    m_process.setProcessChannelMode(QProcess::MergedChannels);
    connect(&m_process, &QProcess::readyRead, this, [this] {
        appendOutput(QString::fromLocal8Bit(m_process.readAll()));
    });
    connect(&m_process, &QProcess::started, this, [this] {
        setStatusText(tr("Connected"));
        emit activeChanged();
        emit busyChanged();
    });
    connect(&m_process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart)
            emit userError(tr("The connection client could not be started."));
        setStatusText(tr("Connection failed"));
        emit activeChanged();
        emit busyChanged();
    });
    connect(&m_process, qOverload<int, QProcess::ExitStatus>(&QProcess::finished), this,
            [this](int exitCode, QProcess::ExitStatus) {
        appendOutput(tr("\n[process exited with code %1]\n").arg(exitCode));
        setStatusText(tr("Disconnected"));
        emit activeChanged();
        emit busyChanged();
    });
}

bool ConnectionManager::active() const { return m_process.state() != QProcess::NotRunning; }
bool ConnectionManager::busy() const { return m_process.state() == QProcess::Starting; }
QString ConnectionManager::title() const { return m_title; }
QString ConnectionManager::statusText() const { return m_statusText; }
QString ConnectionManager::output() const { return m_output; }

void ConnectionManager::connectSession(const QVariantMap &session)
{
    if (active()) {
        emit userError(tr("Disconnect the active session first."));
        return;
    }

    const auto host = session.value(QStringLiteral("host")).toString().trimmed();
    const auto username = session.value(QStringLiteral("username")).toString().trimmed();
    const auto protocol = session.value(QStringLiteral("protocol")).toString().toLower();
    const int port = session.value(QStringLiteral("port"), protocol == QStringLiteral("rdp") ? 3389 : 22).toInt();
    if (host.isEmpty() || port < 1 || port > 65535) {
        emit userError(tr("Session host or port is invalid."));
        return;
    }

    m_title = session.value(QStringLiteral("name"), host).toString();
    m_output.clear();
    emit titleChanged();
    emit outputChanged();
    setStatusText(tr("Connecting…"));
    emit busyChanged();

    if (protocol == QStringLiteral("rdp")) {
        const auto client = findRdpClient();
        if (client.isEmpty()) {
            setStatusText(tr("RDP client unavailable"));
            emit busyChanged();
            emit userError(tr("Install xfreerdp or wlfreerdp to open RDP sessions."));
            return;
        }
        QStringList arguments{QStringLiteral("/v:%1:%2").arg(host).arg(port), QStringLiteral("/cert:tofu")};
        if (!username.isEmpty())
            arguments.append(QStringLiteral("/u:%1").arg(username));
        if (!QProcess::startDetached(client, arguments)) {
            setStatusText(tr("Connection failed"));
            emit busyChanged();
            emit userError(tr("The RDP client could not be started."));
            return;
        }
        setStatusText(tr("RDP opened externally"));
        appendOutput(tr("RDP session launched with %1.\n").arg(QFileInfo(client).fileName()));
        emit userNotice(tr("RDP session opened in the system client."));
        return;
    }

    const auto ssh = QStandardPaths::findExecutable(QStringLiteral("ssh"));
    if (ssh.isEmpty()) {
        setStatusText(tr("SSH client unavailable"));
        emit busyChanged();
        emit userError(tr("OpenSSH is required for SSH sessions."));
        return;
    }

    const auto target = username.isEmpty() ? host : QStringLiteral("%1@%2").arg(username, host);
    m_process.start(ssh, {
        QStringLiteral("-tt"), QStringLiteral("-p"), QString::number(port),
        QStringLiteral("-o"), QStringLiteral("ServerAliveInterval=30"),
        QStringLiteral("-o"), QStringLiteral("StrictHostKeyChecking=ask"), target
    });
    emit activeChanged();
    emit busyChanged();
}

void ConnectionManager::sendInput(const QString &text)
{
    if (!active())
        return;
    m_process.write(text.toUtf8());
    m_process.write("\n");
}

void ConnectionManager::disconnectSession()
{
    if (!active())
        return;
    m_process.write("exit\n");
    m_process.terminate();
    if (!m_process.waitForFinished(1200))
        m_process.kill();
}

void ConnectionManager::clearOutput()
{
    if (m_output.isEmpty())
        return;
    m_output.clear();
    emit outputChanged();
}

void ConnectionManager::appendOutput(const QString &text)
{
    m_output.append(text);
    constexpr qsizetype maxOutput = 400000;
    if (m_output.size() > maxOutput)
        m_output.remove(0, m_output.size() - maxOutput);
    emit outputChanged();
}

void ConnectionManager::setStatusText(const QString &status)
{
    if (m_statusText == status)
        return;
    m_statusText = status;
    emit statusTextChanged();
}

QString ConnectionManager::findRdpClient() const
{
    const QStringList candidates = qEnvironmentVariableIsEmpty("WAYLAND_DISPLAY")
        ? QStringList{QStringLiteral("xfreerdp3"), QStringLiteral("xfreerdp"),
                      QStringLiteral("wlfreerdp3"), QStringLiteral("wlfreerdp"),
                      QStringLiteral("sdl-freerdp3"), QStringLiteral("sdl-freerdp")}
        : QStringList{QStringLiteral("wlfreerdp3"), QStringLiteral("wlfreerdp"),
                      QStringLiteral("sdl-freerdp3"), QStringLiteral("sdl-freerdp"),
                      QStringLiteral("xfreerdp3"), QStringLiteral("xfreerdp")};
    const QStringList extraDirs {
        QDir(QStandardPaths::writableLocation(QStandardPaths::HomeLocation))
            .filePath(QStringLiteral(".local/bin")),
        QCoreApplication::applicationDirPath()
    };
    for (const auto &candidate : candidates) {
        const auto executable = QStandardPaths::findExecutable(candidate);
        if (!executable.isEmpty())
            return executable;
        for (const QString &dir : extraDirs) {
            const QFileInfo info(QDir(dir).filePath(candidate));
            if (info.isFile() && info.isExecutable())
                return info.absoluteFilePath();
        }
    }
    return {};
}
