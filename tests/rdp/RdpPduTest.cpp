#include "rdp/RdpPdu.h"
#include "rdp/RdpConstants.h"
#include "rdp/RdpBuffer.h"

#include <QTest>

class RdpPduTest : public QObject
{
    Q_OBJECT

private slots:
    void x224ConnectionRequestHasTpktAndNegotiation();
    void parseConfirmWithoutNegotiationDefaultsToRdp();
};

void RdpPduTest::x224ConnectionRequestHasTpktAndNegotiation()
{
    const QByteArray packet = Rdp::buildX224ConnectionRequest(QStringLiteral("alice"),
                                                              Rdp::ProtocolSsl | Rdp::ProtocolHybrid);
    QVERIFY(packet.size() > 20);
    QCOMPARE(uchar(packet.at(0)), 0x03);
    QVERIFY(packet.contains("Cookie: mstshash=alice"));
    QVERIFY(packet.contains(QByteArray::fromHex("01000800"))); // NegReq header
}

void RdpPduTest::parseConfirmWithoutNegotiationDefaultsToRdp()
{
    Rdp::Writer x224;
    x224.u8(6);
    x224.u8(Rdp::X224ConnectConfirm);
    x224.u16Be(0);
    x224.u16Be(0);
    x224.u8(0);
    quint32 selected = 0xFFFF;
    quint32 failure = 1;
    QString error;
    QVERIFY(Rdp::parseX224ConnectionConfirm(x224.data(), &selected, &failure, &error));
    QCOMPARE(selected, Rdp::ProtocolRdp);
}

QTEST_MAIN(RdpPduTest)
#include "RdpPduTest.moc"
