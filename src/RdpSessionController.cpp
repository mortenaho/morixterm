#include "RdpSessionController.h"

#include <QHash>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QTimer>

#include <utility>

namespace {
QString sanitizedLine(QString value)
{
    value.replace(QRegularExpression(QStringLiteral("[\\r\\n]")), QString());
    return value;
}

struct FreeRdpCapabilities {
    bool argsFrom = false;
    bool fromStdin = false;
    bool certTofu = false;
};

FreeRdpCapabilities capabilitiesFor(const QString &binary)
{
    static QHash<QString, FreeRdpCapabilities> cache;
    if (cache.contains(binary))
        return cache.value(binary);

    FreeRdpCapabilities result;
    QProcess probe;
    probe.setProgram(binary);
    probe.setArguments({QStringLiteral("/help")});
    probe.setProcessChannelMode(QProcess::MergedChannels);
    probe.start();
    if (probe.waitForStarted(1500)) {
        probe.waitForFinished(3000);
        const QString help = QString::fromLocal8Bit(probe.readAll()).toLower();
        result.argsFrom = help.contains(QStringLiteral("args-from"));
        result.fromStdin = help.contains(QStringLiteral("from-stdin"));
        result.certTofu = help.contains(QStringLiteral("cert:tofu")) || help.contains(QStringLiteral("cert-tofu"));
    }

    cache.insert(binary, result);
    return result;
}

QString compactProcessOutput(QByteArray output)
{
    output.replace('\r', '\n');
    const QList<QByteArray> lines = output.split('\n');

    QStringList allUseful;
    QStringList diagnostics;
    for (const QByteArray &raw : lines) {
        const QString line = QString::fromLocal8Bit(raw).trimmed();
        if (line.isEmpty())
            continue;

        const QString lower = line.toLower();
        const bool xkbNoise = lower.contains(QStringLiteral("load_map_from_xkbfile"))
            && lower.contains(QStringLiteral("no rdp scancode found"));
        const bool stdinTtyNoise = lower.contains(QStringLiteral("freerdp.utils.passphrase"))
            && (lower.contains(QStringLiteral("tcsetattr")) || lower.contains(QStringLiteral("tcgetattr")))
            && lower.contains(QStringLiteral("inappropriate ioctl for device"));
        if (!xkbNoise && !stdinTtyNoise)
            allUseful << line;

        if (lower.contains(QStringLiteral("[error]"))
            || lower.contains(QStringLiteral("errconnect_"))
            || lower.contains(QStringLiteral("authentication"))
            || lower.contains(QStringLiteral("logon"))
            || lower.contains(QStringLiteral("certificate"))
            || lower.contains(QStringLiteral("transport"))
            || lower.contains(QStringLiteral("tls"))
            || lower.contains(QStringLiteral("connect failed"))
            || lower.contains(QStringLiteral("connection failure"))) {
            diagnostics << line;
        }
    }

    QStringList chosen = diagnostics.isEmpty() ? allUseful : diagnostics;
    constexpr qsizetype MaxLines = 12;
    if (chosen.size() > MaxLines)
        chosen = chosen.mid(chosen.size() - MaxLines);

    QString joined = chosen.join(QStringLiteral("\n"));
    if (joined.size() > 1800)
        joined = joined.right(1800);
    return joined;
}

QString freeRdpExitDescription(int code)
{
    switch (code) {
    case 128: return QStringLiteral("Invalid FreeRDP arguments");
    case 131: return QStringLiteral("Connection setup failed");
    case 132: return QStringLiteral("Authentication failed");
    case 133: return QStringLiteral("Security negotiation failed");
    case 134: return QStringLiteral("Logon failed");
    case 135: return QStringLiteral("Account locked out");
    case 139: return QStringLiteral("DNS error");
    case 140: return QStringLiteral("Host name not found");
    case 141: return QStringLiteral("Connection failed");
    case 142: return QStringLiteral("Initial RDP/MCS connection failed");
    case 143: return QStringLiteral("TLS connection failed");
    case 144: return QStringLiteral("Insufficient privileges");
    case 145: return QStringLiteral("Connection cancelled");
    case 147: return QStringLiteral("Transport connection failed");
    case 148: return QStringLiteral("Password expired");
    case 149: return QStringLiteral("Password must be changed");
    case 150: return QStringLiteral("Domain controller/KDC unreachable");
    case 151: return QStringLiteral("Account disabled");
    case 154: return QStringLiteral("Wrong username or password");
    case 155: return QStringLiteral("Access denied");
    case 156: return QStringLiteral("Account restriction");
    case 157: return QStringLiteral("Account expired");
    case 158: return QStringLiteral("Remote logon type is not granted");
    case 159: return QStringLiteral("Credentials are missing");
    case 160: return QStringLiteral("Remote target is still booting");
    default: return {};
    }
}
}

RdpSessionController::RdpSessionController(QObject *parent)
    : QObject(parent)
{
    m_clientBinary = findClient();
    m_process.setProcessChannelMode(QProcess::MergedChannels);

    connect(&m_process, &QProcess::started, this, [this] {
        m_startedAt.start();
        setStatus(QStringLiteral("RDP client started (%1)").arg(m_clientBinary));
        emit runningChanged();
    });

    connect(&m_process, &QProcess::readyRead, this, [this] {
        const QByteArray chunk = m_process.readAll();
        if (chunk.isEmpty())
            return;
        m_outputBuffer.append(chunk);
        constexpr qsizetype MaxOutput = 24 * 1024;
        if (m_outputBuffer.size() > MaxOutput)
            m_outputBuffer = m_outputBuffer.right(MaxOutput);
    });

    connect(&m_process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        Q_UNUSED(error)
        const QString message = QStringLiteral("FreeRDP could not start: %1").arg(m_process.errorString());
        setStatus(message);
        emit errorOccurred(message);
        emit runningChanged();
    });

    connect(&m_process, qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
            this, [this](int exitCode, QProcess::ExitStatus status) {
        m_outputBuffer.append(m_process.readAll());
        const QString output = compactProcessOutput(m_outputBuffer);
        const bool shortRun = m_startedAt.isValid() && m_startedAt.elapsed() < 5000;

        QString message;
        if (status == QProcess::CrashExit) {
            message = output.isEmpty()
                ? QStringLiteral("RDP client crashed")
                : QStringLiteral("RDP client crashed:\n%1").arg(output);
        } else if (exitCode == 0) {
            message = QStringLiteral("RDP session closed");
        } else {
            const QString reason = freeRdpExitDescription(exitCode);
            const QString target = m_targetDisplay.isEmpty() ? QStringLiteral("the remote host") : m_targetDisplay;
            const QString heading = reason.isEmpty()
                ? QStringLiteral("FreeRDP exited with code %1").arg(exitCode)
                : QStringLiteral("%1 (FreeRDP code %2)").arg(reason).arg(exitCode);

            if (exitCode == 141 && output.isEmpty()) {
                message = QStringLiteral(
                    "%1 while connecting to %2.\n"
                    "The XKB 'no RDP scancode found' warnings are harmless and are not the cause. "
                    "Check that the RDP port is reachable and that Remote Desktop is enabled on the server.")
                    .arg(heading, target);
            } else if (!output.isEmpty()) {
                message = QStringLiteral("%1 while connecting to %2:\n%3")
                    .arg(heading, target, output);
            } else {
                message = QStringLiteral("%1 while connecting to %2").arg(heading, target);
            }
        }

        setStatus(message);
        emit runningChanged();
        emit exited(exitCode);
        if (exitCode != 0 && shortRun)
            emit errorOccurred(message);
    });
}

RdpSessionController::~RdpSessionController()
{
    if (m_process.state() != QProcess::NotRunning) {
        m_process.terminate();
        if (!m_process.waitForFinished(800)) {
            m_process.kill();
            m_process.waitForFinished(500);
        }
    }
}

bool RdpSessionController::running() const
{
    return m_process.state() != QProcess::NotRunning;
}

bool RdpSessionController::start(const QString &host,
                                 const QString &user,
                                 const QString &password,
                                 const QString &domain,
                                 int port,
                                 int width,
                                 int height,
                                 bool fullscreen,
                                 bool ignoreCertificate,
                                 int scale)
{
    if (running()) {
        setStatus(QStringLiteral("An RDP session is already running in this tab"));
        return false;
    }

    const QString cleanHost = sanitizedLine(host.trimmed());
    const QString cleanUser = sanitizedLine(user.trimmed());
    const QString cleanDomain = sanitizedLine(domain.trimmed());

    if (cleanHost.isEmpty()) {
        const QString message = QStringLiteral("RDP host is required");
        setStatus(message);
        emit errorOccurred(message);
        return false;
    }

    if (port < 1 || port > 65535)
        port = 3389;
    width = qBound(640, width, 7680);
    height = qBound(480, height, 4320);
    scale = qBound(100, scale, 300);
    m_targetDisplay = QStringLiteral("%1:%2").arg(cleanHost).arg(port);

    m_clientBinary = findClient();
    emit clientBinaryChanged();
    if (m_clientBinary.isEmpty()) {
#ifdef Q_OS_WIN
        const QString message = QStringLiteral(
            "FreeRDP was not found. Install FreeRDP 3 (wfreerdp) and ensure it is available in PATH.");
#else
        const QString message = QStringLiteral(
            "FreeRDP was not found. Install freerdp3-x11 (or freerdp-x11) and try again.");
#endif
        setStatus(message);
        emit errorOccurred(message);
        return false;
    }

    const FreeRdpCapabilities caps = capabilitiesFor(m_clientBinary);

    // Keep secrets off the command line. For GUI launches we use
    // /args-from:stdin because it accepts a plain pipe and does not require a TTY.
    QStringList args;
    args << QStringLiteral("/v:%1:%2").arg(cleanHost).arg(port);
    if (!cleanUser.isEmpty())
        args << QStringLiteral("/u:%1").arg(cleanUser);
    if (!cleanDomain.isEmpty())
        args << QStringLiteral("/d:%1").arg(cleanDomain);

    args << QStringLiteral("/clipboard:direction-to:all,files-to:all")
         << QStringLiteral("+auto-reconnect")
         << QStringLiteral("/network:auto");

    const QString homePath = QStandardPaths::writableLocation(QStandardPaths::HomeLocation);
    if (!homePath.isEmpty())
        args << QStringLiteral("/drive:home,%1").arg(homePath);

    // /gfx is useful on modern servers but is not required for a connection and
    // has caused compatibility problems with some older gateways. Let FreeRDP
    // negotiate the graphics path itself.
#ifndef Q_OS_WIN
    args << QStringLiteral("/wm-class:MoriXterm-RDP");
#endif

    args << QStringLiteral("/scale-desktop:%1").arg(scale);
    if (fullscreen) {
        args << QStringLiteral("/f");
    } else {
        args << QStringLiteral("/size:%1x%2").arg(width).arg(height)
             << QStringLiteral("+dynamic-resolution");
    }

    if (ignoreCertificate)
        args << QStringLiteral("/cert:ignore");
    else if (caps.certTofu)
        args << QStringLiteral("/cert:tofu");
    else
        args << QStringLiteral("/cert:ignore"); // Legacy FreeRDP lacks TOFU support.

    m_outputBuffer.clear();
    m_process.setProgram(m_clientBinary);
    m_process.setProcessChannelMode(QProcess::MergedChannels);

    QByteArray stdinPayload;
    // GUI applications do not own a controlling TTY. FreeRDP's /from-stdin
    // credential prompt calls tcgetattr/tcsetattr and therefore fails when a
    // QProcess pipe is used ("Inappropriate ioctl for device").  /args-from:stdin
    // is designed for non-interactive pipes: each line is parsed as one command
    // line argument, including the password, and nothing secret is exposed in
    // the process argv or environment.
    if (!password.isEmpty() && caps.argsFrom) {
        QStringList secureArgs = args;
        secureArgs << QStringLiteral("/p:%1").arg(sanitizedLine(password));
        for (const QString &arg : std::as_const(secureArgs)) {
            stdinPayload.append(arg.toUtf8());
            stdinPayload.append('\n');
        }
        m_process.setArguments({QStringLiteral("/args-from:stdin")});
    } else if (!password.isEmpty()) {
        const QString message = caps.fromStdin
            ? QStringLiteral(
                "This FreeRDP build only exposes /from-stdin for password input. "
                "That mode requires a terminal and cannot be used safely from MoriXterm's GUI. "
                "Install a FreeRDP build with /args-from:stdin support (FreeRDP 3.x).")
            : QStringLiteral(
                "This FreeRDP build cannot receive a password securely from MoriXterm. "
                "Install FreeRDP 3.x with /args-from:stdin support or clear the saved password.");
        setStatus(message);
        emit errorOccurred(message);
        return false;
    } else {
        m_process.setArguments(args);
    }

    if (!stdinPayload.isEmpty()) {
        connect(&m_process, &QProcess::started, this,
                [this, payload = std::move(stdinPayload)]() mutable {
            m_process.write(payload);
            // closeWriteChannel() sends EOF after Qt flushes the buffered bytes;
            // avoid blocking the GUI thread with waitForBytesWritten().
            m_process.closeWriteChannel();
            payload.fill('\0');
            payload.clear();
        }, Qt::SingleShotConnection);
    }

    setStatus(QStringLiteral("Starting RDP session with %1…").arg(m_clientBinary));
    m_process.start();
    return true;
}

void RdpSessionController::stop()
{
    if (!running())
        return;

    setStatus(QStringLiteral("Closing RDP session…"));
    m_process.terminate();
}

QString RdpSessionController::findClient() const
{
#ifdef Q_OS_WIN
    const QStringList candidates {
        QStringLiteral("wfreerdp.exe"),
        QStringLiteral("wfreerdp"),
        QStringLiteral("xfreerdp.exe"),
        QStringLiteral("xfreerdp")
    };
#else
    const QStringList candidates {
        QStringLiteral("xfreerdp3"),
        QStringLiteral("xfreerdp"),
        QStringLiteral("sdl-freerdp3"),
        QStringLiteral("sdl-freerdp")
    };
#endif

    for (const QString &candidate : candidates) {
        const QString path = QStandardPaths::findExecutable(candidate);
        if (!path.isEmpty())
            return path;
    }
    return {};
}

void RdpSessionController::setStatus(const QString &text)
{
    if (m_statusText == text)
        return;
    m_statusText = text;
    emit statusTextChanged();
}
