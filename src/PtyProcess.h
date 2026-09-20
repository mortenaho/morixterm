#pragma once

#include <QByteArray>
#include <QObject>
#include <QStringList>

#ifdef Q_OS_WIN
#include <QProcess>
#endif

class QSocketNotifier;
class QTimer;

class PtyProcess final : public QObject
{
    Q_OBJECT
public:
    explicit PtyProcess(QObject *parent = nullptr);
    ~PtyProcess() override;

    bool start(const QString &program, const QStringList &arguments = {}, const QString &password = {});
    void writeData(const QByteArray &data);
    void resize(int rows, int columns);
    void terminate();
    bool isRunning() const;

signals:
    void readyRead(const QByteArray &data);
    void exited(int exitCode);
    void errorOccurred(const QString &message);

private slots:
#ifndef Q_OS_WIN
    void onReadable();
    void checkChild();
#endif

private:
#ifdef Q_OS_WIN
    QProcess m_process;
#else
    int m_masterFd = -1;
    qint64 m_childPid = -1;
    QSocketNotifier *m_notifier = nullptr;
    QTimer *m_waitTimer = nullptr;
#endif
};
