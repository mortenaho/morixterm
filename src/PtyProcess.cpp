#include "PtyProcess.h"

#include <QDir>
#include <QFileInfo>
#include <QMetaObject>
#include <QProcess>
#include <QRegularExpression>
#include <QStandardPaths>

#include <exception>
#include <utility>

#ifdef Q_OS_WIN

namespace {
void closeHandle(HANDLE &handle)
{
    if (handle) {
        CloseHandle(handle);
        handle = nullptr;
    }
}

QString windowsError(DWORD code)
{
    wchar_t buffer[512] {};
    const DWORD count = FormatMessageW(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
                                       nullptr, code, 0, buffer, 512, nullptr);
    return count ? QString::fromWCharArray(buffer, qsizetype(count)).trimmed()
                 : QStringLiteral("Windows error %1").arg(code);
}

// CreateProcessW receives a command-line string, not an argv array. Quote each
// argument with the Windows C runtime rules so paths containing spaces/quotes
// are passed to OpenSSH unchanged and never interpreted by cmd.exe.
QString quoteWindowsArgument(const QString &value)
{
    if (!value.isEmpty() && !value.contains(QRegularExpression(QStringLiteral("[\\s\"]"))))
        return value;
    QString result = QStringLiteral("\"");
    int slashes = 0;
    for (const QChar ch : value) {
        if (ch == QLatin1Char('\\')) {
            ++slashes;
        } else if (ch == QLatin1Char('"')) {
            result += QString(slashes * 2 + 1, QLatin1Char('\\')) + ch;
            slashes = 0;
        } else {
            result += QString(slashes, QLatin1Char('\\')) + ch;
            slashes = 0;
        }
    }
    result += QString(slashes * 2, QLatin1Char('\\')) + QLatin1Char('"');
    return result;
}
}

PtyProcess::PtyProcess(QObject *parent) : QObject(parent)
{
}

PtyProcess::~PtyProcess() { terminate(); }

bool PtyProcess::start(const QString &program, const QStringList &arguments, const QString &password)
{
    terminate();

    QString executable = program;
    if (!QFileInfo(program).isAbsolute())
        executable = QStandardPaths::findExecutable(program);
    if (executable.isEmpty()) {
        emit errorOccurred(QStringLiteral("SSH client was not found: %1").arg(program));
        return false;
    }

    HANDLE inputRead = nullptr;
    HANDLE inputWrite = nullptr;
    HANDLE outputRead = nullptr;
    HANDLE outputWrite = nullptr;
    HPCON console = nullptr;
    LPPROC_THREAD_ATTRIBUTE_LIST attributes = nullptr;
    bool attributesInitialized = false;

    auto fail = [&](const QString &message) {
        if (attributesInitialized)
            DeleteProcThreadAttributeList(attributes);
        if (attributes)
            HeapFree(GetProcessHeap(), 0, attributes);
        if (console) {
            // No reader thread exists yet on this failure path. Break the
            // output pipe before closing ConPTY so its final frame cannot
            // block on an undrained buffer.
            closeHandle(outputRead);
            ClosePseudoConsole(console);
        }
        closeHandle(inputRead);
        closeHandle(inputWrite);
        closeHandle(outputRead);
        closeHandle(outputWrite);
        emit errorOccurred(message);
        return false;
    };

    if (!CreatePipe(&inputRead, &inputWrite, nullptr, 0)
        || !CreatePipe(&outputRead, &outputWrite, nullptr, 0))
        return fail(QStringLiteral("Could not create Windows terminal pipes: %1")
                        .arg(windowsError(GetLastError())));

    const COORD initialSize {static_cast<SHORT>(m_columns), static_cast<SHORT>(m_rows)};
    const HRESULT result = CreatePseudoConsole(initialSize, inputRead, outputWrite, 0, &console);
    if (FAILED(result))
        return fail(QStringLiteral("Could not create Windows ConPTY terminal (Windows 10 1809+ required): %1")
                        .arg(windowsError(HRESULT_CODE(result))));
    // CreatePseudoConsole duplicates these ends. Close the originals before
    // CreateProcess so the child cannot inherit a second copy of the pipes.
    closeHandle(inputRead);
    closeHandle(outputWrite);

    SIZE_T attributeBytes = 0;
    InitializeProcThreadAttributeList(nullptr, 1, 0, &attributeBytes);
    attributes = static_cast<LPPROC_THREAD_ATTRIBUTE_LIST>(HeapAlloc(GetProcessHeap(), 0, attributeBytes));
    if (!attributes)
        return fail(QStringLiteral("Could not allocate Windows terminal startup data."));
    if (!InitializeProcThreadAttributeList(attributes, 1, 0, &attributeBytes))
        return fail(QStringLiteral("Could not initialize Windows terminal: %1")
                        .arg(windowsError(GetLastError())));
    attributesInitialized = true;
    if (!UpdateProcThreadAttribute(attributes, 0, PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE,
                                   console, sizeof(console), nullptr, nullptr))
        return fail(QStringLiteral("Could not attach Windows terminal: %1")
                        .arg(windowsError(GetLastError())));

    STARTUPINFOEXW startup {};
    startup.StartupInfo.cb = sizeof(startup);
    startup.lpAttributeList = attributes;
    PROCESS_INFORMATION process {};
    const QString nativeExecutable = QDir::toNativeSeparators(executable);
    QStringList commandParts {quoteWindowsArgument(nativeExecutable)};
    for (const QString &argument : arguments)
        commandParts << quoteWindowsArgument(argument);
    std::wstring commandLine = commandParts.join(QLatin1Char(' ')).toStdWString();
    commandLine.push_back(L'\0');
    // Bundled Win32-OpenSSH loads sibling DLLs from its own folder; also give
    // the child a sane TERM so remote Linux shells enable colour/line editing.
    const std::wstring workingDirectory =
        QDir::toNativeSeparators(QFileInfo(executable).absolutePath()).toStdWString();
    QStringList environment = QProcess::systemEnvironment();
    bool hasTerm = false;
    for (QString &entry : environment) {
        if (entry.startsWith(QLatin1String("TERM="), Qt::CaseInsensitive)) {
            entry = QStringLiteral("TERM=xterm-256color");
            hasTerm = true;
            break;
        }
    }
    if (!hasTerm)
        environment.append(QStringLiteral("TERM=xterm-256color"));
    std::wstring environmentBlock;
    for (const QString &entry : environment) {
        environmentBlock.append(entry.toStdWString());
        environmentBlock.push_back(L'\0');
    }
    environmentBlock.push_back(L'\0');
    // lpApplicationName must stay null. When it is set, Windows skips
    // PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE and the child inherits the parent
    // console, so terminal input and output never reach this process.
    const BOOL created = CreateProcessW(nullptr, commandLine.data(),
                                        nullptr, nullptr, FALSE,
                                        EXTENDED_STARTUPINFO_PRESENT | CREATE_UNICODE_ENVIRONMENT,
                                        environmentBlock.data(), workingDirectory.c_str(),
                                        &startup.StartupInfo, &process);
    const DWORD createError = created ? ERROR_SUCCESS : GetLastError();
    DeleteProcThreadAttributeList(attributes);
    HeapFree(GetProcessHeap(), 0, attributes);
    attributes = nullptr;
    attributesInitialized = false;
    if (!created)
        return fail(QStringLiteral("Could not start SSH in Windows terminal: %1")
                        .arg(windowsError(createError)));

    closeHandle(inputRead);
    closeHandle(outputWrite);
    closeHandle(process.hThread);
    m_console = console;
    m_inputWrite = inputWrite;
    m_outputRead = outputRead;
    m_processHandle = process.hProcess;
    m_stopping = false;
    m_running = true;
    const auto generation = ++m_generation;

    auto launchThreads = [this, generation] {
        m_reader = std::thread([this, generation] {
            char buffer[8192];
            DWORD count = 0;
            while (ReadFile(m_outputRead, buffer, sizeof(buffer), &count, nullptr) && count > 0) {
                QByteArray data(buffer, qsizetype(count));
                QMetaObject::invokeMethod(this, [this, generation, data = std::move(data)] {
                    if (generation == m_generation && !m_stopping)
                        emit readyRead(data);
                }, Qt::QueuedConnection);
            }
        });
        m_writer = std::thread([this] {
            while (true) {
                QByteArray data;
                {
                    std::unique_lock lock(m_writeMutex);
                    m_writeReady.wait(lock, [this] { return m_stopping || !m_writeQueue.empty(); });
                    if (m_stopping)
                        break;
                    data = std::move(m_writeQueue.front());
                    m_writeQueue.pop_front();
                }
                qsizetype offset = 0;
                while (offset < data.size() && !m_stopping) {
                    DWORD written = 0;
                    const DWORD amount = DWORD(qMin<qsizetype>(data.size() - offset, 8192));
                    if (!WriteFile(m_inputWrite, data.constData() + offset, amount, &written, nullptr)
                        || written == 0)
                        break;
                    offset += written;
                }
            }
        });
        m_waiter = std::thread([this, generation] {
            WaitForSingleObject(m_processHandle, INFINITE);
            DWORD code = 1;
            GetExitCodeProcess(m_processHandle, &code);
            m_running = false;
            QMetaObject::invokeMethod(this, [this, generation, code] {
                if (generation == m_generation && !m_stopping)
                    emit exited(int(code));
            }, Qt::QueuedConnection);
        });
    };
    try {
        launchThreads();
    } catch (const std::exception &error) {
        terminate();
        emit errorOccurred(QStringLiteral("Could not start Windows terminal I/O: %1")
                               .arg(QString::fromLocal8Bit(error.what())));
        return false;
    }

    if (!password.isEmpty())
        emit readyRead(QByteArrayLiteral("\r\n[Windows SSH: type the password at the interactive prompt; saved-password auto-fill is unavailable.]\r\n"));
    return true;
}

void PtyProcess::writeData(const QByteArray &data)
{
    if (!m_running || data.isEmpty())
        return;
    {
        std::lock_guard lock(m_writeMutex);
        m_writeQueue.push_back(data);
    }
    m_writeReady.notify_one();
}

void PtyProcess::resize(int rows, int columns)
{
    m_rows = qBound(1, rows, 32767);
    m_columns = qBound(1, columns, 32767);
    if (m_console)
        ResizePseudoConsole(m_console, COORD {static_cast<SHORT>(m_columns), static_cast<SHORT>(m_rows)});
}

void PtyProcess::terminate()
{
    m_stopping = true;
    ++m_generation;
    m_running = false;
    {
        std::lock_guard lock(m_writeMutex);
        m_writeQueue.clear();
    }
    m_writeReady.notify_all();
    if (m_processHandle) {
        DWORD code = 0;
        if (GetExitCodeProcess(m_processHandle, &code) && code == STILL_ACTIVE)
            TerminateProcess(m_processHandle, 1);
    }
    if (m_writer.joinable()) {
        CancelSynchronousIo(m_writer.native_handle());
        m_writer.join();
    }
    closeHandle(m_inputWrite);
    if (m_console) {
        ClosePseudoConsole(m_console);
        m_console = nullptr;
    }
    if (m_waiter.joinable())
        m_waiter.join();
    if (m_reader.joinable()) {
        CancelSynchronousIo(m_reader.native_handle());
        m_reader.join();
    }
    closeHandle(m_outputRead);
    closeHandle(m_processHandle);
}

bool PtyProcess::isRunning() const { return m_running; }

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
