#include "../src/RdpSessionController.h"

#include <QDir>
#include <QFile>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>
#include <QUrl>

class RdpSessionControllerTest : public QObject
{
    Q_OBJECT

private slots:
    void clipboardShareAndZoomArguments();
};

void RdpSessionControllerTest::clipboardShareAndZoomArguments()
{
    QTemporaryDir temporary;
    QVERIFY(temporary.isValid());
    const QString clientPath = temporary.filePath(QStringLiteral("xfreerdp3"));
    QFile client(clientPath);
    QVERIFY(client.open(QIODevice::WriteOnly));
    const QByteArray script =
        "#!/bin/sh\n"
        "if [ \"$1\" = /help ]; then printf 'args-from cert:tofu\\n'; exit 0; fi\n"
        "printf '%s\\n' \"$@\" > \"$MORIXTERM_RDP_TEST_OUTPUT\"\n";
    QCOMPARE(client.write(script), script.size());
    client.close();
    QVERIFY(client.setPermissions(QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner));

    const QByteArray originalPath = qgetenv("PATH");
    qputenv("PATH", QFile::encodeName(temporary.path()) + ':' + originalPath);
    const QString outputPath = temporary.filePath(QStringLiteral("arguments.txt"));
    qputenv("MORIXTERM_RDP_TEST_OUTPUT", QFile::encodeName(outputPath));

    const QString folderPath = temporary.filePath(QStringLiteral("shared folder"));
    QVERIFY(QDir().mkpath(folderPath));
    RdpSessionController controller;
    QCOMPARE(controller.clientBinary(), clientPath);

    QSignalSpy firstExit(&controller, &RdpSessionController::exited);
    QVERIFY(controller.start(QStringLiteral("example.test"), QStringLiteral("user"), {}, {},
                             3389, 1440, 900, false, false, 100, folderPath));
    QTRY_COMPARE_WITH_TIMEOUT(firstExit.size(), 1, 3000);
    QFile output(outputPath);
    QVERIFY(output.open(QIODevice::ReadOnly));
    const QByteArray baseArgs = output.readAll();
    output.close();
    QVERIFY(baseArgs.contains("+clipboard"));
    QVERIFY(baseArgs.contains("/clipboard:direction-to:all,files-to:all"));
    QVERIFY(baseArgs.contains("/clipboard:use-selection:CLIPBOARD"));
    QVERIFY(baseArgs.contains((QStringLiteral("/drive:home,") + folderPath).toUtf8()));
    QVERIFY(baseArgs.contains("/size:1440x900"));
    QVERIFY(baseArgs.contains("+dynamic-resolution"));
    QVERIFY(!baseArgs.contains("smart-sizing"));
    QCOMPARE(controller.sharedFolderPath(), folderPath);

    QSignalSpy secondExit(&controller, &RdpSessionController::exited);
    QVERIFY(controller.start(QStringLiteral("example.test"), {}, {}, {},
                             3389, 1440, 900, false, false, 150,
                             QUrl::fromLocalFile(folderPath).toString()));
    QTRY_COMPARE_WITH_TIMEOUT(secondExit.size(), 1, 3000);
    QVERIFY(output.open(QIODevice::ReadOnly));
    const QByteArray scaledArgs = output.readAll();
    output.close();
    QVERIFY(scaledArgs.contains("/size:960x600"));
    QVERIFY(scaledArgs.contains("/smart-sizing:1440x900"));
    QVERIFY(!scaledArgs.contains("+dynamic-resolution"));
    QVERIFY(!scaledArgs.contains("/scale-desktop:"));

    QSignalSpy thirdExit(&controller, &RdpSessionController::exited);
    QVERIFY(controller.start(QStringLiteral("example.test"), {}, {}, {},
                             3389, 1440, 900, true, false, 150, folderPath));
    QTRY_COMPARE_WITH_TIMEOUT(thirdExit.size(), 1, 3000);
    QVERIFY(output.open(QIODevice::ReadOnly));
    const QByteArray fullscreenArgs = output.readAll();
    output.close();
    QVERIFY(fullscreenArgs.contains("/f"));
    QVERIFY(fullscreenArgs.contains("/smart-sizing:"));
    QVERIFY(!fullscreenArgs.contains("\n/size:"));
    QVERIFY(!fullscreenArgs.contains("+dynamic-resolution"));

    QVERIFY(!controller.start(QStringLiteral("example.test"), {}, {}, {},
                              3389, 1440, 900, false, false, 100,
                              temporary.filePath(QStringLiteral("missing"))));
    QVERIFY(controller.statusText().contains(QStringLiteral("does not exist")));
    qputenv("PATH", originalPath);
}

QTEST_MAIN(RdpSessionControllerTest)
#include "RdpSessionControllerTest.moc"
