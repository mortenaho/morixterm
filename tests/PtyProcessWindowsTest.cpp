#include "../src/PtyProcess.h"

#include <QFileInfo>
#include <QSignalSpy>
#include <QTest>

class PtyProcessWindowsTest : public QObject
{
    Q_OBJECT

private slots:
    void interactiveConsole();
    void bundledOpenSsh();
};

void PtyProcessWindowsTest::interactiveConsole()
{
    QByteArray output;
    PtyProcess terminal;
    connect(&terminal, &PtyProcess::readyRead, this,
            [&output](const QByteArray &data) { output.append(data); });
    QSignalSpy exited(&terminal, &PtyProcess::exited);
    QSignalSpy errors(&terminal, &PtyProcess::errorOccurred);

    const QString shell = qEnvironmentVariable("ComSpec", "cmd.exe");
    QVERIFY(terminal.start(shell));
    terminal.resize(30, 100);
    terminal.writeData(QByteArrayLiteral("echo MORIXTERM_CONPTY_READY\r\n"));
    QTRY_VERIFY2_WITH_TIMEOUT(output.contains("MORIXTERM_CONPTY_READY"),
                              qPrintable(QStringLiteral("captured: %1")
                                             .arg(QString::fromLocal8Bit(output).replace(QLatin1Char('\r'), QLatin1Char(' ')).left(300))),
                              10000);
    terminal.writeData(QByteArrayLiteral("exit\r"));
    QTRY_COMPARE_WITH_TIMEOUT(exited.size(), 1, 10000);
    QCOMPARE(exited.at(0).at(0).toInt(), 0);
    QCOMPARE(errors.size(), 0);
}

void PtyProcessWindowsTest::bundledOpenSsh()
{
    const QString ssh = qEnvironmentVariable("MORIXTERM_TEST_SSH_EXE");
    if (ssh.isEmpty())
        QSKIP("Set MORIXTERM_TEST_SSH_EXE to test the packaged OpenSSH binary.");
    QVERIFY2(QFileInfo::exists(ssh), qPrintable(ssh));

    QByteArray output;
    PtyProcess terminal;
    connect(&terminal, &PtyProcess::readyRead, this,
            [&output](const QByteArray &data) { output.append(data); });
    QSignalSpy exited(&terminal, &PtyProcess::exited);
    QSignalSpy errors(&terminal, &PtyProcess::errorOccurred);

    QVERIFY(terminal.start(ssh, {QStringLiteral("-V")}));
    QTRY_COMPARE_WITH_TIMEOUT(exited.size(), 1, 10000);
    QTRY_VERIFY2_WITH_TIMEOUT(output.contains("OpenSSH"),
                              qPrintable(QStringLiteral("captured: %1")
                                             .arg(QString::fromLocal8Bit(output).replace(QLatin1Char('\r'), QLatin1Char(' ')).left(300))),
                              10000);
    QCOMPARE(exited.at(0).at(0).toInt(), 0);
    QCOMPARE(errors.size(), 0);
}

QTEST_GUILESS_MAIN(PtyProcessWindowsTest)
#include "PtyProcessWindowsTest.moc"
