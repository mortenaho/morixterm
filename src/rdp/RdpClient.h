#pragma once

#include "RdpConstants.h"

#include <QImage>
#include <QObject>
#include <QSslSocket>
#include <QString>
#include <QTimer>

namespace Rdp {

class Client : public QObject
{
    Q_OBJECT
public:
    explicit Client(QObject *parent = nullptr);

    State state() const { return m_state; }
    QString statusText() const { return m_status; }
    QImage framebuffer() const { return m_framebuffer; }
    bool running() const;

    void connectToHost(const QString &host,
                       quint16 port,
                       const QString &user,
                       const QString &password,
                       const QString &domain,
                       int width,
                       int height,
                       bool ignoreCertificate);
    void disconnectFromHost();

    void sendMouse(quint16 flags, int x, int y);
    void sendKey(quint16 flags, quint16 scanCode);

signals:
    void stateChanged();
    void statusChanged();
    void framebufferChanged(const QRect &region);
    void errorOccurred(const QString &message);
    void connected();
    void disconnected();

private:
    void setState(State state);
    void setStatus(const QString &text);
    void fail(const QString &message);
    void sendRaw(const QByteArray &packet);
    void pump();
    bool takeTpkt(QByteArray *payload);
    void handlePayload(const QByteArray &payload);
    void handleMcs(const QByteArray &x224Data);
    void handleFastPath(const QByteArray &packet);
    void handleShareControl(const QByteArray &data);
    void handleUpdate(const QByteArray &shareDataPayload);
    void handleBitmapUpdate(const QByteArray &payload);
    void joinChannels();
    void sendClientInfo();
    void enterActive(quint16 shareId);
    QByteArray buildInputPdu(const QByteArray &events);

    QSslSocket m_socket;
    QByteArray m_recv;
    State m_state = State::Idle;
    QString m_status = QStringLiteral("Ready");
    QString m_host;
    QString m_user;
    QString m_password;
    QString m_domain;
    int m_width = 1280;
    int m_height = 800;
    bool m_ignoreCertificate = false;
    quint32 m_selectedProtocol = ProtocolSsl;
    quint16 m_userId = 0;
    quint16 m_mcsChannelId = IoChannelId;
    quint16 m_shareId = 0;
    QList<quint16> m_channelsToJoin;
    int m_joinsRemaining = 0;
    QImage m_framebuffer;
    bool m_tlsUpgraded = false;
};

} // namespace Rdp
