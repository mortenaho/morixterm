#include "../src/PtyProcess.h"

#include <QFile>
#include <QFileInfo>
#include <QSignalSpy>
#include <QTest>

namespace {
void recordPty(const char *name, const QByteArray &output, int exits, int errors)
{
    QFile file(QStringLiteral("pty-trace.txt"));
    if (!file.open(QIODevice::Append | QIODevice::Text))
        return;
    const QString text = QString::fromLocal8Bit(output).replace(QLatin1Char('\r'), QLatin1Char(' ')).left(400);
    file.write(QStringLiteral("%1 exits=%2 errors=%3 bytes=%4 text=[%5]\n")
                   .arg(QLatin1String(name)).arg(exits).arg(errors).arg(output.size()).arg(text)
                   .toUtf8());
}
}

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
    QTest::qWait(3000);
    recordPty("interactive", output, exited.size(), errors.size());
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
    QTest::qWait(3000);
    recordPty("ssh-v", output, exited.size(), errors.size());
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
