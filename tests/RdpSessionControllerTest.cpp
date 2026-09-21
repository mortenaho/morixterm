#include "../src/RdpSessionController.h"

#include <QSignalSpy>
#include <QTest>

class RdpSessionControllerTest : public QObject
{
    Q_OBJECT

private slots:
    void exposesNativeClient();
    void startRequiresHost();
};

void RdpSessionControllerTest::exposesNativeClient()
{
    RdpSessionController controller;
    QCOMPARE(controller.clientBinary(), QStringLiteral("native"));
    QVERIFY(controller.client() != nullptr);
    QVERIFY(!controller.running());
}

void RdpSessionControllerTest::startRequiresHost()
{
    RdpSessionController controller;
    QSignalSpy errors(&controller, &RdpSessionController::errorOccurred);
    QVERIFY(!controller.start({}, {}, {}, {}, 3389, 800, 600, false, true, 100, {}));
    QTRY_VERIFY_WITH_TIMEOUT(errors.size() >= 1, 2000);
}

QTEST_MAIN(RdpSessionControllerTest)
#include "RdpSessionControllerTest.moc"
