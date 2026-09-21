#include "RdpClient.h"
#include "RdpBuffer.h"
#include "RdpPdu.h"

#include <QColor>
#include <QSslConfiguration>

namespace Rdp {

Client::Client(QObject *parent)
    : QObject(parent)
{
    m_socket.setSocketOption(QAbstractSocket::LowDelayOption, 1);
    connect(&m_socket, &QSslSocket::connected, this, [this] {
        setStatus(QStringLiteral("Negotiating RDP…"));
        setState(State::Negotiating);
        sendRaw(buildX224ConnectionRequest(m_user, ProtocolSsl | ProtocolHybrid));
    });
    connect(&m_socket, &QSslSocket::encrypted, this, [this] {
        m_tlsUpgraded = true;
        setStatus(QStringLiteral("MCS connect…"));
        setState(State::McsConnect);
        sendRaw(buildMcsConnectInitial(m_width, m_height, m_selectedProtocol, QStringLiteral("MoriXterm")));
    });
    connect(&m_socket, &QIODevice::readyRead, this, &Client::pump);
    connect(&m_socket, &QAbstractSocket::errorOccurred, this, [this](QAbstractSocket::SocketError) {
        if (m_state != State::Closing && m_state != State::Idle)
            fail(m_socket.errorString());
    });
    connect(&m_socket, &QSslSocket::sslErrors, this, [this](const QList<QSslError> &errors) {
        if (m_ignoreCertificate) {
            m_socket.ignoreSslErrors();
            return;
        }
        QStringList parts;
        for (const QSslError &err : errors)
            parts << err.errorString();
        fail(QStringLiteral("TLS certificate error: %1").arg(parts.join(QStringLiteral("; "))));
    });
    connect(&m_socket, &QAbstractSocket::disconnected, this, [this] {
        if (m_state == State::Closing || m_state == State::Failed || m_state == State::Idle) {
            setState(State::Idle);
            setStatus(QStringLiteral("Disconnected"));
            emit disconnected();
            return;
        }
        fail(QStringLiteral("Server closed the connection"));
    });
}

bool Client::running() const
{
    return m_state != State::Idle && m_state != State::Failed;
}

void Client::connectToHost(const QString &host,
                           quint16 port,
                           const QString &user,
                           const QString &password,
                           const QString &domain,
                           int width,
                           int height,
                           bool ignoreCertificate)
{
    if (running())
        disconnectFromHost();

    m_host = host.trimmed();
    m_user = user;
    m_password = password;
    m_domain = domain;
    m_width = qBound(640, width, 8192);
    m_height = qBound(480, height, 8192);
    m_ignoreCertificate = ignoreCertificate;
    m_recv.clear();
    m_tlsUpgraded = false;
    m_userId = 0;
    m_shareId = 0;
    m_channelsToJoin.clear();
    m_joinsRemaining = 0;
    m_framebuffer = QImage(m_width, m_height, QImage::Format_RGB32);
    m_framebuffer.fill(QColor(0x20, 0x22, 0x24));

    if (m_host.isEmpty()) {
        fail(QStringLiteral("RDP host is required"));
        return;
    }

    setStatus(QStringLiteral("Connecting to %1:%2…").arg(m_host).arg(port));
    setState(State::Connecting);
    m_socket.connectToHost(m_host, port);
}

void Client::disconnectFromHost()
{
    if (m_state == State::Idle)
        return;
    setState(State::Closing);
    setStatus(QStringLiteral("Disconnecting…"));
    m_socket.disconnectFromHost();
    if (m_socket.state() != QAbstractSocket::UnconnectedState)
        m_socket.waitForDisconnected(500);
    setState(State::Idle);
    setStatus(QStringLiteral("Disconnected"));
    emit disconnected();
}

void Client::sendMouse(quint16 flags, int x, int y)
{
    if (m_state != State::Active)
        return;
    const QByteArray events = buildMouseEvent(flags, quint16(qBound(0, x, m_width - 1)), quint16(qBound(0, y, m_height - 1)));
    sendRaw(buildInputPdu(events));
}

void Client::sendKey(quint16 flags, quint16 scanCode)
{
    if (m_state != State::Active)
        return;
    sendRaw(buildInputPdu(buildScanCodeEvent(flags, scanCode)));
}

void Client::setState(State state)
{
    if (m_state == state)
        return;
    m_state = state;
    emit stateChanged();
}

void Client::setStatus(const QString &text)
{
    if (m_status == text)
        return;
    m_status = text;
    emit statusChanged();
}

void Client::fail(const QString &message)
{
    setState(State::Failed);
    setStatus(message);
    emit errorOccurred(message);
    m_socket.abort();
    emit disconnected();
}

void Client::sendRaw(const QByteArray &packet)
{
    if (packet.isEmpty())
        return;
    if (m_socket.write(packet) < 0)
        fail(m_socket.errorString());
}

void Client::pump()
{
    m_recv.append(m_socket.readAll());
    while (true) {
        if (m_recv.size() < 4)
            return;

        // Fast-path updates start with a non-0x03 first byte once the session is active.
        if (m_tlsUpgraded && m_state == State::Active && uchar(m_recv.at(0)) != 0x03) {
            const quint8 header = uchar(m_recv.at(0));
            int length = 0;
            int headerLen = 1;
            if (header & 0x80) {
                if (m_recv.size() < 3)
                    return;
                length = ((header & 0x7F) << 8) | uchar(m_recv.at(1));
                headerLen = 2;
                // optional length2 for large packets not handled yet
            } else {
                if (m_recv.size() < 2)
                    return;
                length = uchar(m_recv.at(1));
                headerLen = 2;
            }
            if (length < headerLen || m_recv.size() < length)
                return;
            const QByteArray packet = m_recv.left(length);
            m_recv.remove(0, length);
            handleFastPath(packet);
            continue;
        }

        if (uchar(m_recv.at(0)) != 0x03) {
            fail(QStringLiteral("Invalid TPKT header"));
            return;
        }
        QByteArray payload;
        if (!takeTpkt(&payload))
            return;
        handlePayload(payload);
    }
}

bool Client::takeTpkt(QByteArray *payload)
{
    if (m_recv.size() < 4)
        return false;
    Reader r(m_recv);
    r.u8();
    r.u8();
    const quint16 len = r.u16Be();
    if (!r.ok() || len < 4)
        return false;
    if (m_recv.size() < len)
        return false;
    *payload = m_recv.mid(4, len - 4);
    m_recv.remove(0, len);
    return true;
}

void Client::handlePayload(const QByteArray &payload)
{
    if (payload.isEmpty())
        return;

    if (m_state == State::Negotiating) {
        quint32 selected = ProtocolSsl;
        quint32 failure = 0;
        QString error;
        if (!parseX224ConnectionConfirm(payload, &selected, &failure, &error)) {
            fail(error.isEmpty() ? QStringLiteral("Negotiation failed") : error);
            return;
        }
        m_selectedProtocol = selected;
        if (selected & ProtocolHybrid || selected & ProtocolHybridEx) {
            fail(QStringLiteral(
                "This server requires NLA/CredSSP. Native CredSSP is not implemented yet. "
                "Temporarily disable Network Level Authentication on the host, or wait for the CredSSP milestone."));
            return;
        }
        if (selected == ProtocolRdp) {
            fail(QStringLiteral(
                "Server selected legacy RDP encryption. MoriXterm's native client currently supports TLS only."));
            return;
        }
        if (!(selected & ProtocolSsl)) {
            fail(QStringLiteral("Unsupported RDP protocol selection %1").arg(selected));
            return;
        }
        setStatus(QStringLiteral("Starting TLS…"));
        setState(State::TlsHandshake);
        QSslConfiguration conf = m_socket.sslConfiguration();
        conf.setPeerVerifyMode(m_ignoreCertificate ? QSslSocket::VerifyNone : QSslSocket::VerifyPeer);
        m_socket.setSslConfiguration(conf);
        m_socket.startClientEncryption();
        return;
    }

    // After X.224 data PDUs: LI + DT + EOT + MCS bytes
    if (payload.size() < 3 || uchar(payload.at(1)) != X224Data)
        return;
    const QByteArray mcs = payload.mid(3);
    handleMcs(mcs);
}

void Client::handleMcs(const QByteArray &mcs)
{
    if (mcs.isEmpty())
        return;
    const quint8 code = uchar(mcs.at(0));

    if (m_state == State::McsConnect) {
        // Connect-Response APPLICATION 102 = 0x7F 0x66
        if (mcs.size() >= 2 && uchar(mcs.at(0)) == 0x7F && uchar(mcs.at(1)) == 0x66) {
            setStatus(QStringLiteral("Erecting MCS domain…"));
            sendRaw(buildMcsErectDomain());
            sendRaw(buildMcsAttachUserRequest());
            setState(State::Channels);
            return;
        }
        fail(QStringLiteral("Unexpected MCS Connect Response"));
        return;
    }

    if (m_state == State::Channels) {
        // AttachUserConfirm = 0x2E (with optional failure 0x2C)
        if ((code & 0xFC) == 0x2C) {
            if (code == 0x2C) {
                fail(QStringLiteral("MCS Attach User failed"));
                return;
            }
            // AttachUserConfirm includes user id
            Reader r(mcs);
            r.u8();
            // optional result skipped when success variant 0x2E
            const quint16 user = r.u16Be();
            m_userId = quint16(user + 1001);
            m_channelsToJoin = {m_userId, IoChannelId, 1004}; // user channel + I/O + cliprdr tentative
            m_joinsRemaining = m_channelsToJoin.size();
            for (quint16 ch : m_channelsToJoin)
                sendRaw(buildMcsChannelJoinRequest(m_userId, ch));
            return;
        }
        if ((code & 0xFC) == 0x3C) {
            // ChannelJoinConfirm
            --m_joinsRemaining;
            if (m_joinsRemaining <= 0) {
                setState(State::SecureSettings);
                setStatus(QStringLiteral("Sending client info…"));
                sendClientInfo();
            }
            return;
        }
    }

    if (code == 0x68) {
        // sendDataIndication
        Reader r(mcs);
        r.u8();
        r.u16Be(); // initiator
        const quint16 channel = r.u16Be();
        Q_UNUSED(channel);
        r.u8(); // dataPriority + segmentation
        int len = 0;
        const quint8 first = r.u8();
        if (!r.ok())
            return;
        if (first & 0x80) {
            if ((first & 0xC0) == 0xC0) {
                len = ((first & 0x3F) << 16) | (int(r.u8()) << 8) | int(r.u8());
            } else {
                len = ((first & 0x7F) << 8) | int(r.u8());
            }
        } else {
            len = first;
        }
        const QByteArray data = r.take(len);
        if (!r.ok())
            return;

        QByteArray sharePayload = data;
        if (data.size() >= 4) {
            Reader peek(data);
            const quint16 secFlags = peek.u16();
            peek.u16();
            if (secFlags & 0x0080) {
                // SEC_LICENSE_PKT — reply with STATUS_VALID_CLIENT
                setState(State::Licensing);
                setStatus(QStringLiteral("Licensing…"));
                Writer fixed;
                fixed.u8(0xFF);
                fixed.u8(0x02);
                fixed.u16(16);
                fixed.u32(0x00000007);
                fixed.u32(0x00000002);
                fixed.u16(0x0004);
                fixed.u16(0);
                Writer secured;
                secured.u16(0x0080);
                secured.u16(0);
                secured.bytes(fixed.data());
                sendRaw(wrapSendDataRequest(m_userId, m_mcsChannelId, secured.data()));
                return;
            }
            // TLS sessions use a basic security header before share control PDUs.
            if (secFlags == 0x0000 || secFlags == 0x0400 || (secFlags & 0x0010) || (secFlags & 0x0008)
                || (secFlags & 0x0020)) {
                sharePayload = data.mid(4);
            }
        }
        handleShareControl(sharePayload);
        return;
    }
}

void Client::handleFastPath(const QByteArray &packet)
{
    if (packet.size() < 3)
        return;
    Reader r(packet);
    const quint8 header = r.u8();
    Q_UNUSED(header);
    if (packet.at(0) & 0x80)
        r.u8(); // already consumed one length byte in header parsing; re-read simply:
    // Reparse cleanly:
    int pos = 1;
    if (uchar(packet.at(0)) & 0x80)
        pos = 2;
    if (packet.size() <= pos)
        return;
    quint8 updateCode = uchar(packet.at(pos));
    // fragmentation / compression bits in high nibble
    const quint8 code = updateCode & 0x0F;
    QByteArray payload = packet.mid(pos + 1);
    if (code == 1) { // FASTPATH_UPDATETYPE_BITMAP
        handleBitmapUpdate(payload);
    }
}

void Client::handleShareControl(const QByteArray &data)
{
    if (data.size() < 6)
        return;
    Reader r(data);
    const quint16 totalLength = r.u16();
    const quint16 pduTypeField = r.u16();
    const quint16 pduSource = r.u16();
    Q_UNUSED(pduSource);
    Q_UNUSED(totalLength);
    const quint16 pduType = pduTypeField & 0x0F;
    const QByteArray payload = data.mid(6);

    if (pduType == PdutypeDemandActive) {
        Reader d(payload);
        m_shareId = quint16(d.u32() & 0xFFFF);
        setStatus(QStringLiteral("Confirming capabilities…"));
        setState(State::Capabilities);
        enterActive(m_shareId);
        return;
    }
    if (pduType == PdutypeData) {
        if (payload.size() < 12)
            return;
        Reader sd(payload);
        sd.u32(); // shareId
        sd.u8();
        sd.u8();
        sd.u16();
        const quint8 pduType2 = sd.u8();
        sd.u8();
        sd.u16();
        const QByteArray body = payload.mid(12);
        if (pduType2 == Pdutype2Update)
            handleUpdate(body);
        else if (pduType2 == Pdutype2SetErrorInfo) {
            Reader er(body);
            const quint32 err = er.u32();
            fail(QStringLiteral("RDP error info 0x%1").arg(err, 8, 16, QLatin1Char('0')));
        }
    }
}

void Client::handleUpdate(const QByteArray &shareDataPayload)
{
    Reader r(shareDataPayload);
    const quint16 updateType = r.u16();
    if (updateType == UpdateTypeBitmap)
        handleBitmapUpdate(shareDataPayload.mid(2));
}

void Client::handleBitmapUpdate(const QByteArray &payload)
{
    Reader r(payload);
    const quint16 count = r.u16();
    if (!r.ok())
        return;
    QRect dirty;
    for (int i = 0; i < count; ++i) {
        const quint16 left = r.u16();
        const quint16 top = r.u16();
        const quint16 right = r.u16();
        const quint16 bottom = r.u16();
        const quint16 width = r.u16();
        const quint16 height = r.u16();
        const quint16 bpp = r.u16();
        const quint16 flags = r.u16();
        const quint16 bitmapLength = r.u16();
        Q_UNUSED(right);
        Q_UNUSED(bottom);
        QByteArray pixels = r.take(bitmapLength);
        if (!r.ok())
            return;
        if (flags & 0x0001) {
            // BITMAP_COMPRESSION — skip compressed rectangles for now
            continue;
        }
        if (bpp != 24 && bpp != 32 && bpp != 16)
            continue;
        const int destW = width;
        const int destH = height;
        if (left + destW > m_framebuffer.width() || top + destH > m_framebuffer.height())
            continue;

        // RDP bitmaps are bottom-up
        for (int y = 0; y < destH; ++y) {
            const int srcY = destH - 1 - y;
            for (int x = 0; x < destW; ++x) {
                QRgb color = qRgb(0, 0, 0);
                if (bpp == 32) {
                    const int idx = (srcY * destW + x) * 4;
                    if (idx + 3 >= pixels.size())
                        break;
                    const uchar b = uchar(pixels.at(idx));
                    const uchar g = uchar(pixels.at(idx + 1));
                    const uchar r8 = uchar(pixels.at(idx + 2));
                    color = qRgb(r8, g, b);
                } else if (bpp == 24) {
                    const int idx = (srcY * destW + x) * 3;
                    if (idx + 2 >= pixels.size())
                        break;
                    const uchar b = uchar(pixels.at(idx));
                    const uchar g = uchar(pixels.at(idx + 1));
                    const uchar r8 = uchar(pixels.at(idx + 2));
                    color = qRgb(r8, g, b);
                } else if (bpp == 16) {
                    const int idx = (srcY * destW + x) * 2;
                    if (idx + 1 >= pixels.size())
                        break;
                    const quint16 v = quint16(uchar(pixels.at(idx))) | (quint16(uchar(pixels.at(idx + 1))) << 8);
                    const int r8 = ((v >> 11) & 0x1F) * 255 / 31;
                    const int g = ((v >> 5) & 0x3F) * 255 / 63;
                    const int b = (v & 0x1F) * 255 / 31;
                    color = qRgb(r8, g, b);
                }
                m_framebuffer.setPixel(left + x, top + y, color);
            }
        }
        dirty = dirty.united(QRect(left, top, destW, destH));
    }
    if (!dirty.isNull())
        emit framebufferChanged(dirty);
}

void Client::sendClientInfo()
{
    sendRaw(buildClientInfoPdu(m_userId, m_mcsChannelId, m_domain, m_user, m_password, m_width, m_height));
    setState(State::Licensing);
}

void Client::enterActive(quint16 shareId)
{
    m_shareId = shareId;
    sendRaw(buildConfirmActive(m_userId, m_mcsChannelId, shareId, m_width, m_height));
    sendRaw(buildSynchronize(m_userId, m_mcsChannelId, shareId));
    sendRaw(buildControl(m_userId, m_mcsChannelId, shareId, 0x0004)); // CTRLACTION_COOPERATE
    sendRaw(buildControl(m_userId, m_mcsChannelId, shareId, 0x0001)); // CTRLACTION_REQUEST_CONTROL
    sendRaw(buildFontList(m_userId, m_mcsChannelId, shareId));
    setState(State::Active);
    setStatus(QStringLiteral("Connected"));
    emit connected();
    emit framebufferChanged(m_framebuffer.rect());
}

QByteArray Client::buildInputPdu(const QByteArray &events)
{
    Writer body;
    body.u16(1); // numEvents
    body.u16(0); // pad
    body.bytes(events);
    Writer sd;
    sd.u32(m_shareId);
    sd.u8(0);
    sd.u8(1);
    sd.u16(quint16(body.size() + 18));
    sd.u8(Pdutype2Input);
    sd.u8(0);
    sd.u16(0);
    sd.bytes(body.data());
    Writer share;
    share.u16(quint16(sd.size() + 6));
    share.u16(quint16(PdutypeData | 0x10));
    share.u16(m_userId);
    share.bytes(sd.data());
    return wrapSendDataRequest(m_userId, m_mcsChannelId, share.data());
}

} // namespace Rdp
