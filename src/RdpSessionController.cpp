#include "RdpSessionController.h"

#include <QDir>
#include <QFileInfo>
#include <QStandardPaths>
#include <QUrl>

RdpSessionController::RdpSessionController(QObject *parent)
    : QObject(parent)
{
    connect(&m_client, &Rdp::Client::statusChanged, this, &RdpSessionController::statusTextChanged);
    connect(&m_client, &Rdp::Client::stateChanged, this, [this] {
        const bool now = running();
        if (m_wasRunning != now) {
            m_wasRunning = now;
            emit runningChanged();
        }
    });
    connect(&m_client, &Rdp::Client::errorOccurred, this, &RdpSessionController::errorOccurred);
    connect(&m_client, &Rdp::Client::disconnected, this, [this] {
        if (m_wasRunning) {
            m_wasRunning = false;
            emit runningChanged();
        }
        emit exited(0);
    });
    emit clientBinaryChanged();
}

bool RdpSessionController::running() const
{
    return m_client.running();
}

bool RdpSessionController::start(const QString &host,
                                 const QString &user,
                                 const QString &password,
                                 const QString &domain,
                                 int port,
                                 int width,
                                 int height,
                                 bool fullscreen,
                                 bool ignoreCertificate,
                                 int scale,
                                 const QString &sharedFolder)
{
    Q_UNUSED(fullscreen);

    if (running()) {
        emit errorOccurred(QStringLiteral("An RDP session is already running in this tab"));
        return false;
    }

    QString folderPath = sharedFolder.trimmed();
    if (folderPath.startsWith(QStringLiteral("file://"), Qt::CaseInsensitive))
        folderPath = QUrl(folderPath).toLocalFile();
    if (folderPath.isEmpty())
        folderPath = QStandardPaths::writableLocation(QStandardPaths::HomeLocation);
    const QFileInfo folderInfo(folderPath);
    if (!folderPath.isEmpty() && folderInfo.isDir() && folderInfo.isReadable()) {
        folderPath = QDir::cleanPath(folderInfo.absoluteFilePath());
        if (m_sharedFolderPath != folderPath) {
            m_sharedFolderPath = folderPath;
            emit sharedFolderPathChanged();
        }
    }

    // Scale maps to requested desktop size for the native client.
    scale = qBound(100, scale, 300);
    int desktopWidth = qBound(640, width, 8192);
    int desktopHeight = qBound(480, height, 8192);
    if (scale != 100) {
        desktopWidth = qMax(640, qRound(desktopWidth * 100.0 / scale));
        desktopHeight = qMax(480, qRound(desktopHeight * 100.0 / scale));
    }

    m_client.connectToHost(host, quint16(qBound(1, port, 65535)), user, password, domain,
                           desktopWidth, desktopHeight, ignoreCertificate);
    return m_client.running() || m_client.state() == Rdp::State::Connecting
        || m_client.state() == Rdp::State::Negotiating;
}

void RdpSessionController::stop()
{
    m_client.disconnectFromHost();
}
