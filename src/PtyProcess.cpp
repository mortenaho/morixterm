#include "PtyProcess.h"

#include <QStandardPaths>

#ifdef Q_OS_WIN

PtyProcess::PtyProcess(QObject *parent) : QObject(parent)
{
    m_process.setProcessChannelMode(QProcess::MergedChannels);
    connect(&m_process, &QProcess::readyRead, this, [this] {
        const QByteArray data = m_process.readAll();
        if (!data.isEmpty())
            emit readyRead(data);
    });
    connect(&m_process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError) {
        emit errorOccurred(m_process.errorString());
    });
    connect(&m_process, qOverload<int, QProcess::ExitStatus>(&QProcess::finished), this,
            [this](int code, QProcess::ExitStatus) { emit exited(code); });
}

PtyProcess::~PtyProcess() { terminate(); }

bool PtyProcess::start(const QString &program, const QStringList &arguments, const QString &password)
{
    terminate();
    if (!password.isEmpty())
        emit errorOccurred(QStringLiteral("Saved-password injection for SSH is unavailable on the Windows fallback terminal; OpenSSH will prompt interactively."));
    m_process.setProgram(program);
    m_process.setArguments(arguments);
    m_process.start();
    return m_process.waitForStarted(3000);
}

void PtyProcess::writeData(const QByteArray &data)
{
    if (m_process.state() != QProcess::NotRunning && !data.isEmpty())
        m_process.write(data);
}

void PtyProcess::resize(int, int) {}

void PtyProcess::terminate()
{
    if (m_process.state() == QProcess::NotRunning)
        return;
    m_process.terminate();
    if (!m_process.waitForFinished(500))
        m_process.kill();
}

bool PtyProcess::isRunning() const { return m_process.state() != QProcess::NotRunning; }

#else

#include <QSocketNotifier>
#include <QTimer>

#include <cerrno>
#include <csignal>
#include <cstring>
#include <fcntl.h>
#include <pty.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <unistd.h>
#include <vector>

PtyProcess::PtyProcess(QObject *parent) : QObject(parent)
{
    m_waitTimer = new QTimer(this);
    m_waitTimer->setInterval(250);
    connect(m_waitTimer, &QTimer::timeout, this, &PtyProcess::checkChild);
}

PtyProcess::~PtyProcess() { terminate(); }

bool PtyProcess::start(const QString &program, const QStringList &arguments, const QString &password)
{
    terminate();

    const QString sshpass = password.isEmpty() ? QString() : QStandardPaths::findExecutable(QStringLiteral("sshpass"));
    int passwordPipe[2] {-1, -1};
    const bool useSshpass = !password.isEmpty() && !sshpass.isEmpty();
    if (useSshpass && ::pipe(passwordPipe) != 0) {
        emit errorOccurred(QStringLiteral("Could not create secure password pipe: %1").arg(QString::fromLocal8Bit(std::strerror(errno))));
        return false;
    }

    int masterFd = -1;
    const pid_t pid = ::forkpty(&masterFd, nullptr, nullptr, nullptr);
    if (pid < 0) {
        if (passwordPipe[0] >= 0) ::close(passwordPipe[0]);
        if (passwordPipe[1] >= 0) ::close(passwordPipe[1]);
        emit errorOccurred(QStringLiteral("forkpty failed: %1").arg(QString::fromLocal8Bit(std::strerror(errno))));
        return false;
    }

    if (pid == 0) {
        ::setenv("TERM", "xterm-256color", 1);
        ::setenv("COLORTERM", "truecolor", 1);

        QString execProgram = program;
        QStringList execArgs = arguments;
        if (useSshpass) {
            ::close(passwordPipe[1]);
            if (passwordPipe[0] != 3) {
                ::dup2(passwordPipe[0], 3);
                ::close(passwordPipe[0]);
            }
            execProgram = sshpass;
            execArgs = {QStringLiteral("-d"), QStringLiteral("3"), program};
            execArgs.append(arguments);
        }

        const QByteArray programBytes = execProgram.toLocal8Bit();
        QList<QByteArray> argStorage;
        argStorage.reserve(execArgs.size() + 1);
        argStorage.push_back(programBytes);
        for (const QString &arg : execArgs)
            argStorage.push_back(arg.toLocal8Bit());

        std::vector<char *> argv;
        argv.reserve(static_cast<size_t>(argStorage.size()) + 1);
        for (QByteArray &arg : argStorage)
            argv.push_back(arg.data());
        argv.push_back(nullptr);
        ::execvp(programBytes.constData(), argv.data());
        ::_exit(127);
    }

    if (useSshpass) {
        ::close(passwordPipe[0]);
        QByteArray secret = password.toUtf8();
        secret.append('\n');
        qsizetype offset = 0;
        while (offset < secret.size()) {
            const ssize_t written = ::write(passwordPipe[1], secret.constData() + offset,
                                            static_cast<size_t>(secret.size() - offset));
            if (written > 0) offset += written;
            else if (written < 0 && errno == EINTR) continue;
            else break;
        }
        secret.fill('\0');
        ::close(passwordPipe[1]);
    } else if (!password.isEmpty()) {
        emit errorOccurred(QStringLiteral("sshpass is not installed; SSH will prompt for the password interactively."));
    }

    m_masterFd = masterFd;
    m_childPid = pid;
    const int flags = ::fcntl(m_masterFd, F_GETFL, 0);
    if (flags >= 0)
        ::fcntl(m_masterFd, F_SETFL, flags | O_NONBLOCK);

    m_notifier = new QSocketNotifier(m_masterFd, QSocketNotifier::Read, this);
    connect(m_notifier, &QSocketNotifier::activated, this, &PtyProcess::onReadable);
    m_waitTimer->start();
    return true;
}

void PtyProcess::writeData(const QByteArray &data)
{
    if (m_masterFd < 0 || data.isEmpty()) return;
    qsizetype offset = 0;
    while (offset < data.size()) {
        const ssize_t written = ::write(m_masterFd, data.constData() + offset,
                                        static_cast<size_t>(data.size() - offset));
        if (written > 0) offset += written;
        else if (written < 0 && errno == EINTR) continue;
        else break;
    }
}

void PtyProcess::resize(int rows, int columns)
{
    if (m_masterFd < 0 || rows <= 0 || columns <= 0) return;
    struct winsize size {};
    size.ws_row = static_cast<unsigned short>(rows);
    size.ws_col = static_cast<unsigned short>(columns);
    ::ioctl(m_masterFd, TIOCSWINSZ, &size);
    if (m_childPid > 0) ::kill(static_cast<pid_t>(m_childPid), SIGWINCH);
}

void PtyProcess::terminate()
{
    if (m_notifier) {
        m_notifier->setEnabled(false);
        m_notifier->deleteLater();
        m_notifier = nullptr;
    }
    if (m_masterFd >= 0) {
        ::close(m_masterFd);
        m_masterFd = -1;
    }
    if (m_childPid > 0) {
        ::kill(static_cast<pid_t>(m_childPid), SIGHUP);
        int status = 0;
        ::waitpid(static_cast<pid_t>(m_childPid), &status, WNOHANG);
        m_childPid = -1;
    }
    if (m_waitTimer) m_waitTimer->stop();
}

bool PtyProcess::isRunning() const { return m_childPid > 0; }

void PtyProcess::onReadable()
{
    if (m_masterFd < 0) return;
    QByteArray collected;
    char buffer[8192];
    while (true) {
        const ssize_t count = ::read(m_masterFd, buffer, sizeof(buffer));
        if (count > 0) { collected.append(buffer, static_cast<qsizetype>(count)); continue; }
        if (count < 0 && errno == EINTR) continue;
        break;
    }
    if (!collected.isEmpty()) emit readyRead(collected);
}

void PtyProcess::checkChild()
{
    if (m_childPid <= 0) return;
    int status = 0;
    const pid_t result = ::waitpid(static_cast<pid_t>(m_childPid), &status, WNOHANG);
    if (result <= 0) return;
    int exitCode = -1;
    if (WIFEXITED(status)) exitCode = WEXITSTATUS(status);
    else if (WIFSIGNALED(status)) exitCode = 128 + WTERMSIG(status);
    m_childPid = -1;
    m_waitTimer->stop();
    if (m_notifier) { m_notifier->setEnabled(false); m_notifier->deleteLater(); m_notifier = nullptr; }
    if (m_masterFd >= 0) { ::close(m_masterFd); m_masterFd = -1; }
    emit exited(exitCode);
}

#endif
