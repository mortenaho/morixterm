#include "CredentialStore.h"

#include <QByteArray>
#include <QProcess>
#include <QStandardPaths>

#include <string>

#ifdef Q_OS_WIN
#  include <windows.h>
#  include <wincred.h>
#endif

CredentialStore::CredentialStore(QObject *parent)
    : QObject(parent)
{
#ifdef Q_OS_WIN
    m_available = true;
    m_backend = QStringLiteral("Windows Credential Manager");
#elif defined(Q_OS_LINUX)
    m_available = !QStandardPaths::findExecutable(QStringLiteral("secret-tool")).isEmpty();
    m_backend = m_available ? QStringLiteral("Secret Service / libsecret")
                            : QStringLiteral("Unavailable (install libsecret-tools)");
#else
    m_available = false;
    m_backend = QStringLiteral("No secure credential backend configured");
#endif
}

QString CredentialStore::key(qint64 sessionId) const
{
    return QStringLiteral("MoriXterm/session/%1").arg(sessionId);
}

bool CredentialStore::store(qint64 sessionId, const QString &password)
{
    if (!m_available || sessionId <= 0 || password.isEmpty())
        return false;

#ifdef Q_OS_WIN
    const std::wstring target = key(sessionId).toStdWString();
    QByteArray secret = password.toUtf8();

    CREDENTIALW cred {};
    cred.Type = CRED_TYPE_GENERIC;
    cred.TargetName = const_cast<LPWSTR>(target.c_str());
    cred.CredentialBlobSize = static_cast<DWORD>(secret.size());
    cred.CredentialBlob = reinterpret_cast<LPBYTE>(const_cast<char *>(secret.constData()));
    cred.Persist = CRED_PERSIST_LOCAL_MACHINE;
    cred.UserName = const_cast<LPWSTR>(L"MoriXterm");
    const bool ok = CredWriteW(&cred, 0) == TRUE;
    secret.fill('\0');
    return ok;
#elif defined(Q_OS_LINUX)
    QProcess process;
    process.setProgram(QStringLiteral("secret-tool"));
    process.setArguments({QStringLiteral("store"),
                          QStringLiteral("--label=MoriXterm session %1").arg(sessionId),
                          QStringLiteral("service"), QStringLiteral("MoriXterm"),
                          QStringLiteral("session"), QString::number(sessionId)});
    process.start();
    if (!process.waitForStarted(3000))
        return false;
    QByteArray secret = password.toUtf8();
    process.write(secret);
    process.write("\n");
    secret.fill('\0');
    process.closeWriteChannel();
    return process.waitForFinished(8000) && process.exitStatus() == QProcess::NormalExit && process.exitCode() == 0;
#else
    Q_UNUSED(sessionId)
    Q_UNUSED(password)
    return false;
#endif
}

QString CredentialStore::read(qint64 sessionId) const
{
    if (!m_available || sessionId <= 0)
        return {};

#ifdef Q_OS_WIN
    const std::wstring target = key(sessionId).toStdWString();
    PCREDENTIALW cred = nullptr;
    if (!CredReadW(target.c_str(), CRED_TYPE_GENERIC, 0, &cred) || !cred)
        return {};
    const QByteArray secret(reinterpret_cast<const char *>(cred->CredentialBlob),
                            static_cast<int>(cred->CredentialBlobSize));
    CredFree(cred);
    return QString::fromUtf8(secret);
#elif defined(Q_OS_LINUX)
    QProcess process;
    process.setProgram(QStringLiteral("secret-tool"));
    process.setArguments({QStringLiteral("lookup"),
                          QStringLiteral("service"), QStringLiteral("MoriXterm"),
                          QStringLiteral("session"), QString::number(sessionId)});
    process.start();
    if (!process.waitForFinished(5000) || process.exitStatus() != QProcess::NormalExit || process.exitCode() != 0)
        return {};
    QByteArray output = process.readAllStandardOutput();
    while (output.endsWith('\n') || output.endsWith('\r'))
        output.chop(1);
    const QString result = QString::fromUtf8(output);
    output.fill('\0');
    return result;
#else
    Q_UNUSED(sessionId)
    return {};
#endif
}

bool CredentialStore::remove(qint64 sessionId)
{
    if (!m_available || sessionId <= 0)
        return false;

#ifdef Q_OS_WIN
    const std::wstring target = key(sessionId).toStdWString();
    return CredDeleteW(target.c_str(), CRED_TYPE_GENERIC, 0) == TRUE || GetLastError() == ERROR_NOT_FOUND;
#elif defined(Q_OS_LINUX)
    QProcess process;
    process.setProgram(QStringLiteral("secret-tool"));
    process.setArguments({QStringLiteral("clear"),
                          QStringLiteral("service"), QStringLiteral("MoriXterm"),
                          QStringLiteral("session"), QString::number(sessionId)});
    process.start();
    if (!process.waitForFinished(5000))
        return false;
    return process.exitStatus() == QProcess::NormalExit && process.exitCode() == 0;
#else
    Q_UNUSED(sessionId)
    return false;
#endif
}
