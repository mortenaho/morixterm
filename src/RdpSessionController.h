#pragma once

#include <QByteArray>
#include <QElapsedTimer>
#include <QObject>
#include <QProcess>

class RdpSessionController : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool running READ running NOTIFY runningChanged)
    Q_PROPERTY(QString statusText READ statusText NOTIFY statusTextChanged)
    Q_PROPERTY(QString clientBinary READ clientBinary NOTIFY clientBinaryChanged)
    Q_PROPERTY(QString sharedFolderPath READ sharedFolderPath NOTIFY sharedFolderPathChanged)

public:
    explicit RdpSessionController(QObject *parent = nullptr);
    ~RdpSessionController() override;

    bool running() const;
    QString statusText() const { return m_statusText; }
    QString clientBinary() const { return m_clientBinary; }
    QString sharedFolderPath() const { return m_sharedFolderPath; }

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
    QString findClient() const;
    void setStatus(const QString &text);
    void startClipboardBridge();
    void stopClipboardBridge();

    QProcess m_process;
    QString m_statusText = QStringLiteral("Ready");
    QString m_clientBinary;
    QString m_sharedFolderPath;
    QString m_targetDisplay;
    QByteArray m_outputBuffer;
    QElapsedTimer m_startedAt;
    class RdpClipboardBridge *m_clipboardBridge = nullptr;
};
