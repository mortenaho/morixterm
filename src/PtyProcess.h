#pragma once

#include <QByteArray>
#include <QObject>
#include <QStringList>

#ifdef Q_OS_WIN
#include <windows.h>

#include <atomic>
#include <condition_variable>
#include <deque>
#include <mutex>
#include <thread>
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
    HPCON m_console = nullptr;
    HANDLE m_processHandle = nullptr;
    HANDLE m_inputWrite = nullptr;
    HANDLE m_outputRead = nullptr;
    std::thread m_reader;
    std::thread m_writer;
    std::thread m_waiter;
    std::mutex m_writeMutex;
    std::condition_variable m_writeReady;
    std::deque<QByteArray> m_writeQueue;
    std::atomic_bool m_running {false};
    std::atomic_bool m_stopping {false};
    std::atomic_uint64_t m_generation {0};
    int m_rows = 24;
    int m_columns = 80;
#else
    int m_masterFd = -1;
    qint64 m_childPid = -1;
    QSocketNotifier *m_notifier = nullptr;
    QTimer *m_waitTimer = nullptr;
#endif
};
