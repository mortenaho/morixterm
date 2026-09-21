#include "RdpPdu.h"
#include "RdpConstants.h"

namespace Rdp {
namespace {

QByteArray berLength(int len)
{
    Writer w;
    if (len < 0x80) {
        w.u8(quint8(len));
    } else if (len < 0x100) {
        w.u8(0x81);
        w.u8(quint8(len));
    } else {
        w.u8(0x82);
        w.u16Be(quint16(len));
    }
    return w.data();
}

QByteArray berOctetString(const QByteArray &value)
{
    Writer w;
    w.u8(0x04);
    w.bytes(berLength(value.size()));
    w.bytes(value);
    return w.data();
}

QByteArray berInteger(int value)
{
    Writer body;
    if (value <= 0x7F && value >= 0) {
        body.u8(quint8(value));
    } else if (value <= 0x7FFF && value >= 0) {
        body.u8(quint8((value >> 8) & 0xFF));
        body.u8(quint8(value & 0xFF));
    } else {
        body.u8(quint8((value >> 16) & 0xFF));
        body.u8(quint8((value >> 8) & 0xFF));
        body.u8(quint8(value & 0xFF));
    }
    Writer w;
    w.u8(0x02);
    w.bytes(berLength(body.size()));
    w.bytes(body.data());
    return w.data();
}

QByteArray berBoolean(bool value)
{
    Writer w;
    w.u8(0x01);
    w.u8(0x01);
    w.u8(value ? 0xFF : 0x00);
    return w.data();
}

QByteArray domainParameters(int maxChannelIds,
                            int maxUserIds,
                            int maxTokenIds,
                            int numPriorities,
                            int minThroughput,
                            int maxHeight,
                            int maxMcsPduSize,
                            int protocolVersion)
{
    Writer inner;
    inner.bytes(berInteger(maxChannelIds));
    inner.bytes(berInteger(maxUserIds));
    inner.bytes(berInteger(maxTokenIds));
    inner.bytes(berInteger(numPriorities));
    inner.bytes(berInteger(minThroughput));
    inner.bytes(berInteger(maxHeight));
    inner.bytes(berInteger(maxMcsPduSize));
    inner.bytes(berInteger(protocolVersion));
    Writer w;
    w.u8(0x30);
    w.bytes(berLength(inner.size()));
    w.bytes(inner.data());
    return w.data();
}

QByteArray perLength(int len)
{
    Writer w;
    if (len <= 0x7F) {
        w.u8(quint8(len));
    } else if (len <= 0x3FFF) {
        w.u8(quint8(0x80 | ((len >> 8) & 0x3F)));
        w.u8(quint8(len & 0xFF));
    } else {
        w.u8(0xC0);
        w.u8(quint8((len >> 16) & 0xFF));
        w.u8(quint8((len >> 8) & 0xFF));
        w.u8(quint8(len & 0xFF));
    }
    return w.data();
}

QByteArray makeUserDataHeader(quint16 type, const QByteArray &payload)
{
    Writer w;
    w.u16(type);
    w.u16(quint16(payload.size() + 4));
    w.bytes(payload);
    return w.data();
}

QByteArray buildCsCore(int width, int height, quint32 serverSelectedProtocol, const QString &clientName)
{
    Writer w(256);
    w.u32(0x00080004);
    w.u16(quint16(width));
    w.u16(quint16(height));
    w.u16(0xCA01);
    w.u16(0xAA03);
    w.u32(0x00000409);
    w.u32(2600);

    QString name = clientName.isEmpty() ? QStringLiteral("MoriXterm") : clientName;
    if (name.size() > 15)
        name = name.left(15);
    for (QChar ch : name)
        w.u16(quint16(ch.unicode()));
    w.u16(0);
    const int nameBytes = (name.size() + 1) * 2;
    if (nameBytes < 32)
        w.zero(32 - nameBytes);

    w.u32(0x00000004);
    w.u32(0);
    w.u32(12);
    w.zero(64);
    w.u16(0xCA01);
    w.u16(1);
    w.u32(0);
    w.u16(24);
    w.u16(0x0007);
    w.u16(0x0001);
    w.zero(64);
    w.u8(0x06);
    w.u8(0);
    w.u32(serverSelectedProtocol);
    return makeUserDataHeader(UdCsCore, w.data());
}

QByteArray buildCsSecurity()
{
    Writer w;
    w.u32(0);
    w.u32(0);
    return makeUserDataHeader(UdCsSecurity, w.data());
}

QByteArray buildCsNet()
{
    Writer channels;
    channels.u32(1);
    channels.bytes(QByteArray("cliprdr\0", 8));
    channels.u32(0x80000000u | 0x40000000u | 0x00800000u | 0x00200000u);
    return makeUserDataHeader(UdCsNet, channels.data());
}

QByteArray buildGccCreateConferenceRequest(int width, int height, quint32 serverSelectedProtocol, const QString &clientName)
{
    Writer userData;
    userData.bytes(buildCsCore(width, height, serverSelectedProtocol, clientName));
    userData.bytes(buildCsSecurity());
    userData.bytes(buildCsNet());

    // userData::value OCTET_STRING = length + blocks
    Writer ducaValue;
    ducaValue.bytes(perLength(userData.size()));
    ducaValue.bytes(userData.data());

    Writer connectPdu;
    connectPdu.u8(0x00); // ConnectGCCPDU choice conferenceCreateRequest
    connectPdu.u8(0x08); // selection: userData present
    // conferenceName numeric "1" with min length 1 → length=0 means 1 char, then byte '1'
    connectPdu.u8(0x00);
    connectPdu.u8('1');
    connectPdu.u8(0x00); // padding
    connectPdu.u8(0x01); // number of sets
    connectPdu.u8(0xC0); // value present + h221NonStandard
    // octet string "Duca" with minLength 4 → length determinate 0, then 4 bytes
    connectPdu.u8(0x00);
    connectPdu.bytes(QByteArray("Duca", 4));
    connectPdu.bytes(ducaValue.data());

    Writer gcc;
    gcc.u8(0x00); // Key choice object
    // OBJECT_IDENTIFIER 0.0.20.124.0.1
    gcc.u8(0x05);
    gcc.u8(0x00);
    gcc.u8(0x14);
    gcc.u8(0x7C);
    gcc.u8(0x00);
    gcc.u8(0x01);
    gcc.bytes(perLength(connectPdu.size()));
    gcc.bytes(connectPdu.data());
    return gcc.data();
}

QByteArray buildShareControlHeader(quint16 pduType, quint16 pduSource, const QByteArray &payload)
{
    Writer w;
    w.u16(quint16(payload.size() + 6));
    w.u16(quint16(pduType | 0x10));
    w.u16(pduSource);
    w.bytes(payload);
    return w.data();
}

QByteArray x224DataHeader()
{
    Writer w;
    w.u8(0x02); // LI
    w.u8(X224Data);
    w.u8(0x80); // EOT
    return w.data();
}

} // namespace

QByteArray buildX224ConnectionRequest(const QString &cookieUser, quint32 requestedProtocols)
{
    const QByteArray cookieBytes = QByteArray("Cookie: mstshash=")
        + (cookieUser.isEmpty() ? QByteArray("MoriXterm") : cookieUser.toUtf8())
        + QByteArray("\r\n");

    Writer neg;
    neg.u8(NegReq);
    neg.u8(0x00);
    neg.u16(0x0008);
    neg.u32(requestedProtocols);

    Writer x224;
    const int li = 6 + cookieBytes.size() + neg.size();
    x224.u8(quint8(li));
    x224.u8(X224ConnectRequest);
    x224.u16Be(0); // dst-ref
    x224.u16Be(0); // src-ref
    x224.u8(0x00); // class 0
    x224.bytes(cookieBytes);
    x224.bytes(neg.data());
    return wrapTpkt(x224.data());
}

bool parseX224ConnectionConfirm(const QByteArray &tpktPayload, quint32 *selectedProtocol, quint32 *failureCode, QString *error)
{
    if (selectedProtocol)
        *selectedProtocol = ProtocolRdp;
    if (failureCode)
        *failureCode = 0;

    Reader r(tpktPayload);
    r.u8(); // LI
    const quint8 code = r.u8();
    if (!r.ok() || code != X224ConnectConfirm) {
        if (error)
            *error = QStringLiteral("Unexpected X.224 Connection Confirm");
        return false;
    }
    r.skip(5);
    if (!r.ok())
        return false;
    if (r.remaining() < 8)
        return true;

    const quint8 type = r.u8();
    r.u8();
    r.u16();
    if (type == NegRsp) {
        if (selectedProtocol)
            *selectedProtocol = r.u32();
        return r.ok();
    }
    if (type == NegFailure) {
        const quint32 codeValue = r.u32();
        if (failureCode)
            *failureCode = codeValue;
        if (error)
            *error = QStringLiteral("RDP negotiation failed (code %1)").arg(codeValue);
        return false;
    }
    if (error)
        *error = QStringLiteral("Unknown RDP negotiation response");
    return false;
}

QByteArray buildMcsConnectInitial(int width, int height, quint32 serverSelectedProtocol, const QString &clientName)
{
    const QByteArray gcc = buildGccCreateConferenceRequest(width, height, serverSelectedProtocol, clientName);

    Writer seq;
    seq.bytes(berOctetString(QByteArray(1, char(0x01)))); // callingDomainSelector
    seq.bytes(berOctetString(QByteArray(1, char(0x01)))); // calledDomainSelector
    seq.bytes(berBoolean(true));
    seq.bytes(domainParameters(34, 2, 0, 1, 0, 1, 0xFFFF, 2));
    seq.bytes(domainParameters(1, 1, 1, 1, 0, 1, 0x420, 2));
    seq.bytes(domainParameters(0xFFFF, 0xFC17, 0xFFFF, 1, 0, 1, 0xFFFF, 2));
    seq.bytes(berOctetString(gcc));

    Writer app;
    app.u8(0x7F);
    app.u8(0x65); // APPLICATION 101
    app.bytes(berLength(seq.size()));
    app.bytes(seq.data());

    Writer payload;
    payload.bytes(x224DataHeader());
    payload.bytes(app.data());
    return wrapTpkt(payload.data());
}

QByteArray buildMcsErectDomain()
{
    Writer per;
    per.u8(0x04);
    per.u8(0x01);
    per.u8(0x00);
    per.u8(0x01);
    per.u8(0x00);
    Writer payload;
    payload.bytes(x224DataHeader());
    payload.bytes(per.data());
    return wrapTpkt(payload.data());
}

QByteArray buildMcsAttachUserRequest()
{
    Writer per;
    per.u8(0x28);
    Writer payload;
    payload.bytes(x224DataHeader());
    payload.bytes(per.data());
    return wrapTpkt(payload.data());
}

QByteArray buildMcsChannelJoinRequest(quint16 userId, quint16 channelId)
{
    Writer per;
    per.u8(0x38);
    per.u16Be(quint16(userId - 1001));
    per.u16Be(channelId);
    Writer payload;
    payload.bytes(x224DataHeader());
    payload.bytes(per.data());
    return wrapTpkt(payload.data());
}

QByteArray wrapSendDataRequest(quint16 userId, quint16 channelId, const QByteArray &data)
{
    Writer per;
    per.u8(0x64);
    per.u16Be(quint16(userId - 1001));
    per.u16Be(channelId);
    per.u8(0x70);
    per.bytes(perLength(data.size()));
    per.bytes(data);
    Writer payload;
    payload.bytes(x224DataHeader());
    payload.bytes(per.data());
    return wrapTpkt(payload.data());
}

QByteArray buildClientInfoPdu(quint16 userId,
                              quint16 mcsChannelId,
                              const QString &domain,
                              const QString &user,
                              const QString &password,
                              int width,
                              int height)
{
    Q_UNUSED(width);
    Q_UNUSED(height);

    auto utf16Bytes = [](const QString &text) {
        QByteArray out;
        out.reserve((text.size() + 1) * 2);
        for (QChar ch : text) {
            const quint16 u = quint16(ch.unicode());
            out.append(char(u & 0xFF));
            out.append(char((u >> 8) & 0xFF));
        }
        out.append(char(0));
        out.append(char(0));
        return out;
    };

    const QByteArray domainU = utf16Bytes(domain);
    const QByteArray userU = utf16Bytes(user);
    const QByteArray passU = utf16Bytes(password);
    const QByteArray shellU = utf16Bytes(QString());
    const QByteArray dirU = utf16Bytes(QString());

    Writer info;
    info.u32(0);
    info.u32(0x00000033);
    info.u16(quint16(qMax(0, domainU.size() - 2)));
    info.u16(quint16(qMax(0, userU.size() - 2)));
    info.u16(quint16(qMax(0, passU.size() - 2)));
    info.u16(quint16(qMax(0, shellU.size() - 2)));
    info.u16(quint16(qMax(0, dirU.size() - 2)));
    info.bytes(domainU);
    info.bytes(userU);
    info.bytes(passU);
    info.bytes(shellU);
    info.bytes(dirU);
    info.u16(0x0002);
    info.u16(2);
    info.u16(0);
    info.u16(2);
    info.u16(0);
    info.zero(172);
    info.u32(0);
    info.u32(0x00000001);
    info.u16(0);
    info.u16(0);
    info.u16(0);

    Writer secured;
    secured.u16(0x0040); // SEC_INFO_PKT
    secured.u16(0);
    secured.bytes(info.data());
    return wrapSendDataRequest(userId, mcsChannelId, secured.data());
}

QByteArray buildConfirmActive(quint16 userId, quint16 mcsChannelId, quint16 shareId, int width, int height)
{
    Writer caps;
    auto addCap = [&](quint16 type, const QByteArray &body) {
        caps.u16(type);
        caps.u16(quint16(body.size() + 4));
        caps.bytes(body);
    };

    {
        Writer b;
        b.u16(1);
        b.u16(3);
        b.u16(0x0200);
        b.u16(0);
        b.u16(0);
        b.u16(0x040D);
        b.u16(0);
        b.u16(0);
        b.u8(0);
        b.u8(0);
        addCap(0x0001, b.data());
    }
    {
        Writer b;
        b.u16(24);
        b.u16(1);
        b.u16(1);
        b.u16(1);
        b.u16(quint16(width));
        b.u16(quint16(height));
        b.u16(0);
        b.u16(1);
        b.u16(1);
        b.u8(0);
        b.u8(1);
        b.u16(1);
        b.u16(0);
        addCap(0x0002, b.data());
    }
    {
        Writer b;
        b.zero(16);
        b.u32(0);
        b.u16(1);
        b.u16(20);
        b.zero(32);
        b.u16(0);
        b.u16(1);
        b.u32(0x00002E00);
        b.u16(0);
        b.u16(0x0464);
        b.u16(0);
        b.u16(0);
        b.u16(0);
        b.zero(4);
        addCap(0x0003, b.data());
    }
    {
        Writer b;
        b.u16(0x0035);
        b.u16(0);
        b.u32(0x00000409);
        b.u32(4);
        b.u32(0);
        b.u32(12);
        b.zero(64);
        addCap(0x000D, b.data());
    }

    Writer confirm;
    confirm.u32(shareId);
    confirm.u16(1002);
    const QByteArray sourceDescriptor = QByteArray("MORI\0", 5);
    confirm.u16(quint16(sourceDescriptor.size()));
    confirm.u16(quint16(caps.size() + 4));
    confirm.bytes(sourceDescriptor);
    confirm.u16(4);
    confirm.u16(0);
    confirm.bytes(caps.data());

    return wrapSendDataRequest(userId, mcsChannelId, buildShareControlHeader(PdutypeConfirmActive, userId, confirm.data()));
}

QByteArray buildSynchronize(quint16 userId, quint16 mcsChannelId, quint16 shareId)
{
    Writer body;
    body.u16(1);
    body.u16(1002);
    Writer sd;
    sd.u32(shareId);
    sd.u8(0);
    sd.u8(1);
    sd.u16(quint16(body.size() + 18));
    sd.u8(Pdutype2Synchronize);
    sd.u8(0);
    sd.u16(0);
    sd.bytes(body.data());
    return wrapSendDataRequest(userId, mcsChannelId, buildShareControlHeader(PdutypeData, userId, sd.data()));
}

QByteArray buildControl(quint16 userId, quint16 mcsChannelId, quint16 shareId, quint16 action)
{
    Writer body;
    body.u16(action);
    body.u16(0);
    body.u32(0);
    Writer sd;
    sd.u32(shareId);
    sd.u8(0);
    sd.u8(1);
    sd.u16(quint16(body.size() + 18));
    sd.u8(Pdutype2Control);
    sd.u8(0);
    sd.u16(0);
    sd.bytes(body.data());
    return wrapSendDataRequest(userId, mcsChannelId, buildShareControlHeader(PdutypeData, userId, sd.data()));
}

QByteArray buildFontList(quint16 userId, quint16 mcsChannelId, quint16 shareId)
{
    Writer body;
    body.u16(0);
    body.u16(0);
    body.u16(0x0003);
    body.u16(0x0032);
    Writer sd;
    sd.u32(shareId);
    sd.u8(0);
    sd.u8(1);
    sd.u16(quint16(body.size() + 18));
    sd.u8(Pdutype2Fontlist);
    sd.u8(0);
    sd.u16(0);
    sd.bytes(body.data());
    return wrapSendDataRequest(userId, mcsChannelId, buildShareControlHeader(PdutypeData, userId, sd.data()));
}

QByteArray buildMouseEvent(quint16 flags, quint16 x, quint16 y)
{
    Writer e;
    e.u16(InputEventMouse);
    e.u16(0);
    e.u32(0);
    e.u16(flags);
    e.u16(x);
    e.u16(y);
    return e.data();
}

QByteArray buildScanCodeEvent(quint16 flags, quint16 code)
{
    Writer e;
    e.u16(InputEventScanCode);
    e.u16(0);
    e.u32(0);
    e.u16(flags);
    e.u16(code);
    e.u16(0);
    return e.data();
}

QByteArray buildInputEvent(quint16 userId, quint16 mcsChannelId, const QByteArray &events)
{
    Q_UNUSED(userId);
    Q_UNUSED(mcsChannelId);
    return events;
}

} // namespace Rdp
