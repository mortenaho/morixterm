#include "../src/RdpSessionController.h"
#include "../src/RdpClipboardBridge.h"

#include <QClipboard>
#include <QDir>
#include <QFile>
#include <QGuiApplication>
#include <QMimeData>
#include <QScopeGuard>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>
#include <QUrl>

class RdpSessionControllerTest : public QObject
{
    Q_OBJECT

private slots:
    void localFileClipboard_data();
    void localFileClipboard();
    void clipboardClientSelection_data();
    void clipboardClientSelection();
    void clipboardShareAndZoomArguments();
};

void RdpSessionControllerTest::localFileClipboard_data()
{
    QTest::addColumn<QString>("mimeType");
    QTest::addColumn<QByteArray>("prefix");
    QTest::newRow("gnome-copy") << QStringLiteral("x-special/gnome-copied-files") << QByteArray("copy\n");
    QTest::newRow("mate-copy") << QStringLiteral("x-special/mate-copied-files") << QByteArray("copy\n");
    QTest::newRow("uri-list") << QStringLiteral("text/uri-list") << QByteArray();
}

void RdpSessionControllerTest::localFileClipboard()
{
    QFETCH(QString, mimeType);
    QFETCH(QByteArray, prefix);
    if (QGuiApplication::platformName() != QStringLiteral("offscreen"))
        QSKIP("Use QT_QPA_PLATFORM=offscreen to avoid changing the desktop clipboard");
    QTemporaryDir temporary;
    QVERIFY(temporary.isValid());
    QFile file(temporary.filePath(QString::fromUtf8("گزارش test.txt")));
    QVERIFY(file.open(QIODevice::WriteOnly));
    file.close();
    const QByteArray uri = QUrl::fromLocalFile(file.fileName()).toEncoded();
    auto *mime = new QMimeData;
    // File managers can offer only their native file MIME, without text/uri-list.
    mime->setData(mimeType, prefix + uri + '\n');
    QGuiApplication::clipboard()->setMimeData(mime);
    RdpClipboardBridge bridge;
    const auto payload = bridge.payloadFromQt();
    QGuiApplication::clipboard()->clear();
    // Qt serializes URI lists with CRLF; native file-manager offers often use LF.
    QCOMPARE(payload.uriList.trimmed(), uri);
    QCOMPARE(QUrl::fromEncoded(payload.uriList.trimmed()).toLocalFile(), file.fileName());
    QVERIFY(!payload.gnome.isEmpty());
    QVERIFY(!payload.mate.isEmpty());
}

void RdpSessionControllerTest::clipboardClientSelection_data()
{
    QTest::addColumn<QByteArray>("wayland");
    QTest::addColumn<QByteArray>("display");
    QTest::addColumn<QString>("expectedClient");
    QTest::newRow("x11") << QByteArray() << QByteArray(":99") << QStringLiteral("xfreerdp3");
    QTest::newRow("wayland-with-xwayland")
        << QByteArray("wayland-test") << QByteArray(":99") << QStringLiteral("xfreerdp3");
    QTest::newRow("wayland-without-xwayland")
        << QByteArray("wayland-test") << QByteArray() << QStringLiteral("sdl-freerdp3");
}

void RdpSessionControllerTest::clipboardClientSelection()
{
    QFETCH(QByteArray, wayland);
    QFETCH(QByteArray, display);
    QFETCH(QString, expectedClient);
    QTemporaryDir temporary;
    QVERIFY(temporary.isValid());
    const QStringList clients {QStringLiteral("xfreerdp3"), QStringLiteral("xfreerdp"),
                               QStringLiteral("sdl-freerdp3"), QStringLiteral("sdl-freerdp"),
                               QStringLiteral("wlfreerdp3"), QStringLiteral("wlfreerdp")};
    for (const QString &name : clients) {
        QFile client(temporary.filePath(name));
        QVERIFY(client.open(QIODevice::WriteOnly));
        QVERIFY(client.write("#!/bin/sh\nexit 0\n") > 0);
        client.close();
        QVERIFY(client.setPermissions(QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner));
    }

    const QByteArray originalPath = qgetenv("PATH");
    const QByteArray originalWayland = qgetenv("WAYLAND_DISPLAY");
    const QByteArray originalDisplay = qgetenv("DISPLAY");
    qputenv("PATH", QFile::encodeName(temporary.path()));
    qputenv("WAYLAND_DISPLAY", wayland);
    qputenv("DISPLAY", display);
    // Construction only: do not connect to the real desktop clipboard in tests.
    const QString selected = RdpSessionController().clientBinary();
    const auto restore = [](const char *name, const QByteArray &value) {
        if (value.isNull())
            qunsetenv(name);
        else
            qputenv(name, value);
    };
    restore("PATH", originalPath);
    restore("WAYLAND_DISPLAY", originalWayland);
    restore("DISPLAY", originalDisplay);
    QCOMPARE(selected, temporary.filePath(expectedClient));
}

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
    const QByteArray originalWayland = qgetenv("WAYLAND_DISPLAY");
    // Only the fake client may be visible. A system sdl-freerdp would hide it.
    qputenv("PATH", QFile::encodeName(temporary.path()));
    qunsetenv("WAYLAND_DISPLAY");
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
    QVERIFY(baseArgs.contains("/clipboard:direction-to:all,files-to:all,use-selection:CLIPBOARD"));
    QCOMPARE(baseArgs.count("/clipboard:"), 1);
    QVERIFY(baseArgs.contains((QStringLiteral("/drive:morixterm,") + folderPath).toUtf8()));
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

    const QByteArray originalHome = qgetenv("HOME");
    const auto restoreHome = qScopeGuard([&] {
        if (originalHome.isNull())
            qunsetenv("HOME");
        else
            qputenv("HOME", originalHome);
    });
    const QString isolatedHome = temporary.filePath(QStringLiteral("test home"));
    QVERIFY(QDir().mkpath(isolatedHome));
    qputenv("HOME", QFile::encodeName(isolatedHome));
    const QString defaultShare = QDir(isolatedHome).filePath(QStringLiteral("morixterm/share"));
    QVERIFY(!QFileInfo::exists(defaultShare));
    // First connect creates the nested folder; reconnect reuses it.
    for (int attempt = 0; attempt < 2; ++attempt) {
        QSignalSpy defaultExit(&controller, &RdpSessionController::exited);
        QVERIFY(controller.start(QStringLiteral("example.test"), {}, {}, {},
                                 3389, 1440, 900, false, false, 100));
        QTRY_COMPARE_WITH_TIMEOUT(defaultExit.size(), 1, 3000);
        QVERIFY(QFileInfo(defaultShare).isDir());
        QCOMPARE(controller.sharedFolderPath(), defaultShare);
        QVERIFY(output.open(QIODevice::ReadOnly));
        const QList<QByteArray> defaultArgs = output.readAll().split('\n');
        output.close();
        QVERIFY(defaultArgs.contains((QStringLiteral("/drive:morixterm,") + defaultShare).toUtf8()));
        int driveCount = 0;
        for (const QByteArray &arg : defaultArgs) {
            if (arg.startsWith("/drive:"))
                ++driveCount;
        }
        QCOMPARE(driveCount, 1);
    }

    // A creation failure must fail the connection, never fall back to sharing HOME.
    const QString blockedHome = temporary.filePath(QStringLiteral("blocked home"));
    QVERIFY(QDir().mkpath(blockedHome));
    QFile blocker(QDir(blockedHome).filePath(QStringLiteral("morixterm")));
    QVERIFY(blocker.open(QIODevice::WriteOnly));
    blocker.close();
    qputenv("HOME", QFile::encodeName(blockedHome));
    QSignalSpy shareError(&controller, &RdpSessionController::errorOccurred);
    QVERIFY(!controller.start(QStringLiteral("example.test"), {}, {}, {},
                              3389, 1440, 900, false, false, 100));
    QCOMPARE(shareError.size(), 1);
    QVERIFY(controller.statusText().contains(QStringLiteral("Could not create")));
    QVERIFY(!controller.running());
    qputenv("PATH", originalPath);
    if (originalWayland.isEmpty())
        qunsetenv("WAYLAND_DISPLAY");
    else
        qputenv("WAYLAND_DISPLAY", originalWayland);
}

QTEST_MAIN(RdpSessionControllerTest)
#include "RdpSessionControllerTest.moc"
