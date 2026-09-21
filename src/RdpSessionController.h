#pragma once

#include "rdp/RdpClient.h"

#include <QObject>
#include <QString>

class RdpSessionController : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool running READ running NOTIFY runningChanged)
    Q_PROPERTY(QString statusText READ statusText NOTIFY statusTextChanged)
    Q_PROPERTY(QString clientBinary READ clientBinary NOTIFY clientBinaryChanged)
    Q_PROPERTY(QString sharedFolderPath READ sharedFolderPath NOTIFY sharedFolderPathChanged)
    Q_PROPERTY(Rdp::Client *client READ client CONSTANT)

public:
    explicit RdpSessionController(QObject *parent = nullptr);

    bool running() const;
    QString statusText() const { return m_client.statusText(); }
    QString clientBinary() const { return QStringLiteral("native"); }
    QString sharedFolderPath() const { return m_sharedFolderPath; }
    Rdp::Client *client() { return &m_client; }

    Q_INVOKABLE bool start(const QString &host,
                           const QString &user,
                           const QString &password,
                           const QString &domain = QString(),
                           int port = 3389,
                           int width = 1440,
                           int height = 900,
                           bool fullscreen = false,
                           bool ignoreCertificate = false,
                           int scale = 100,
                           const QString &sharedFolder = QString());
    Q_INVOKABLE void stop();

signals:
    void runningChanged();
    void statusTextChanged();
    void clientBinaryChanged();
    void sharedFolderPathChanged();
    void exited(int exitCode);
    void errorOccurred(const QString &message);

private:
    Rdp::Client m_client;
    QString m_sharedFolderPath;
    bool m_wasRunning = false;
};
