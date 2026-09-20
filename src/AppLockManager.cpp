#include "AppLockManager.h"

#include <QCoreApplication>
#include <QCryptographicHash>
#include <QEvent>
#include <QDateTime>
#include <QKeyEvent>
#include <QMouseEvent>
#include <QRandomGenerator>
#include <QSettings>
#include <QTimer>
#include <QWheelEvent>

#include <algorithm>

namespace {
constexpr int kPbkdf2Iterations = 350000;
constexpr int kDerivedKeyLength = 32;
constexpr int kSaltLength = 24;

QByteArray hmacSha256(QByteArray key, const QByteArray &message)
{
    constexpr int blockSize = 64;
    if (key.size() > blockSize)
        key = QCryptographicHash::hash(key, QCryptographicHash::Sha256);
    if (key.size() < blockSize)
        key.append(QByteArray(blockSize - key.size(), char(0)));

    QByteArray outer(blockSize, char(0x5c));
    QByteArray inner(blockSize, char(0x36));
    for (int i = 0; i < blockSize; ++i) {
        outer[i] = static_cast<char>(static_cast<unsigned char>(outer[i]) ^ static_cast<unsigned char>(key[i]));
        inner[i] = static_cast<char>(static_cast<unsigned char>(inner[i]) ^ static_cast<unsigned char>(key[i]));
    }

    const QByteArray innerHash = QCryptographicHash::hash(inner + message, QCryptographicHash::Sha256);
    return QCryptographicHash::hash(outer + innerHash, QCryptographicHash::Sha256);
}

bool constantTimeEquals(const QByteArray &a, const QByteArray &b)
{
    if (a.size() != b.size())
        return false;
    unsigned char diff = 0;
    for (qsizetype i = 0; i < a.size(); ++i)
        diff |= static_cast<unsigned char>(a.at(i)) ^ static_cast<unsigned char>(b.at(i));
    return diff == 0;
}

QByteArray pbkdf2Sha256(const QByteArray &password, const QByteArray &salt, int iterations, int keyLength)
{
    QByteArray result;
    result.reserve(keyLength);
    int blockIndex = 1;

    while (result.size() < keyLength) {
        QByteArray block = salt;
        block.append(static_cast<char>((blockIndex >> 24) & 0xff));
        block.append(static_cast<char>((blockIndex >> 16) & 0xff));
        block.append(static_cast<char>((blockIndex >> 8) & 0xff));
        block.append(static_cast<char>(blockIndex & 0xff));

        QByteArray u = hmacSha256(password, block);
        QByteArray t = u;
        for (int i = 1; i < iterations; ++i) {
            u = hmacSha256(password, u);
            for (int j = 0; j < t.size(); ++j)
                t[j] = static_cast<char>(static_cast<unsigned char>(t[j]) ^ static_cast<unsigned char>(u[j]));
        }

        result.append(t);
        ++blockIndex;
    }

    result.truncate(keyLength);
    return result;
}
}


AppLockManager::AppLockManager(QObject *parent)
    : QObject(parent), m_timer(new QTimer(this))
{
    m_timer->setSingleShot(true);
    connect(m_timer, &QTimer::timeout, this, &AppLockManager::lockNow);

    loadSettings();

    if (qApp)
        qApp->installEventFilter(this);

    if (hasPassword()) {
        if (m_lockOnStartup)
            QTimer::singleShot(0, this, &AppLockManager::lockNow);
        else if (m_lockEnabled)
            restartTimer();
    }
}

void AppLockManager::setLockEnabled(bool enabled)
{
    if (enabled && !hasPassword()) {
        setStatusMessage(QStringLiteral("Set an application password before enabling auto-lock."));
        return;
    }

    if (m_lockEnabled == enabled)
        return;

    m_lockEnabled = enabled;
    if (m_lockEnabled)
        restartTimer();
    else
        m_timer->stop();

    saveSettings();
    emit settingsChanged();
}

void AppLockManager::setTimeoutMinutes(int minutes)
{
    minutes = std::clamp(minutes, 1, 1440);
    if (m_timeoutMinutes == minutes)
        return;

    m_timeoutMinutes = minutes;
    if (m_lockEnabled && !m_locked)
        restartTimer();

    saveSettings();
    emit settingsChanged();
}

void AppLockManager::setLockOnStartup(bool enabled)
{
    if (m_lockOnStartup == enabled)
        return;
    m_lockOnStartup = enabled;
    saveSettings();
    emit settingsChanged();
}

bool AppLockManager::setPassword(const QString &currentPassword, const QString &newPassword)
{
    if (newPassword.size() < 8) {
        setStatusMessage(QStringLiteral("Password must contain at least 8 characters."));
        return false;
    }

    if (hasPassword() && !verifyPassword(currentPassword)) {
        setStatusMessage(QStringLiteral("Current password is incorrect."));
        return false;
    }

    m_salt.resize(kSaltLength);
    for (int i = 0; i < m_salt.size(); ++i)
        m_salt[i] = static_cast<char>(QRandomGenerator::system()->generate() & 0xff);

    m_passwordHash = deriveKey(newPassword, m_salt);
    m_failedUnlockAttempts = 0;
    m_retryUnlockAfterMs = 0;
    saveSettings();
    emit passwordChanged();
    setStatusMessage(QStringLiteral("Application password saved."));

    if (m_lockEnabled && !m_locked)
        restartTimer();
    return true;
}

bool AppLockManager::removePassword(const QString &currentPassword)
{
    if (!hasPassword())
        return true;

    if (!verifyPassword(currentPassword)) {
        setStatusMessage(QStringLiteral("Current password is incorrect."));
        return false;
    }

    m_passwordHash.clear();
    m_salt.clear();
    m_failedUnlockAttempts = 0;
    m_retryUnlockAfterMs = 0;
    m_lockEnabled = false;
    m_locked = false;
    m_timer->stop();
    saveSettings();
    emit passwordChanged();
    emit settingsChanged();
    emit lockedChanged();
    setStatusMessage(QStringLiteral("Application password removed."));
    return true;
}

bool AppLockManager::unlock(const QString &password)
{
    if (!m_locked)
        return true;

    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    if (now < m_retryUnlockAfterMs) {
        const int seconds = static_cast<int>((m_retryUnlockAfterMs - now + 999) / 1000);
        setStatusMessage(QStringLiteral("Too many failed attempts. Try again in %1 second(s).").arg(seconds));
        return false;
    }

    if (!verifyPassword(password)) {
        ++m_failedUnlockAttempts;
        if (m_failedUnlockAttempts >= 5) {
            const int exponent = std::min(m_failedUnlockAttempts - 5, 5);
            const int delaySeconds = std::min(60, 2 << exponent);
            m_retryUnlockAfterMs = now + static_cast<qint64>(delaySeconds) * 1000;
            setStatusMessage(QStringLiteral("Incorrect password. Unlock is temporarily rate-limited."));
        } else {
            setStatusMessage(QStringLiteral("Incorrect password."));
        }
        return false;
    }

    m_failedUnlockAttempts = 0;
    m_retryUnlockAfterMs = 0;
    m_locked = false;
    emit lockedChanged();
    setStatusMessage(QString());
    restartTimer();
    return true;
}

void AppLockManager::lockNow()
{
    if (!hasPassword() || m_locked)
        return;

    m_locked = true;
    m_timer->stop();
    emit lockedChanged();
    setStatusMessage(QString());
}

void AppLockManager::resetActivityTimer()
{
    if (m_lockEnabled && !m_locked)
        restartTimer();
}

bool AppLockManager::eventFilter(QObject *watched, QEvent *event)
{
    Q_UNUSED(watched)

    if (!m_lockEnabled || m_locked)
        return false;

    switch (event->type()) {
    case QEvent::KeyPress:
    case QEvent::MouseButtonPress:
    case QEvent::MouseButtonRelease:
    case QEvent::MouseMove:
    case QEvent::Wheel:
    case QEvent::TouchBegin:
    case QEvent::TouchUpdate:
        restartTimer();
        break;
    default:
        break;
    }

    return false;
}

QByteArray AppLockManager::deriveKey(const QString &password, const QByteArray &salt) const
{
    QByteArray passwordBytes = password.toUtf8();
    QByteArray result = pbkdf2Sha256(passwordBytes, salt, kPbkdf2Iterations, kDerivedKeyLength);
    passwordBytes.fill('\0');
    return result;
}

bool AppLockManager::verifyPassword(const QString &password) const
{
    if (!hasPassword())
        return false;
    return constantTimeEquals(deriveKey(password, m_salt), m_passwordHash);
}

void AppLockManager::loadSettings()
{
    QSettings settings;
    settings.beginGroup(QStringLiteral("security"));
    m_lockEnabled = settings.value(QStringLiteral("lockEnabled"), false).toBool();
    m_timeoutMinutes = std::clamp(settings.value(QStringLiteral("timeoutMinutes"), 10).toInt(), 1, 1440);
    m_lockOnStartup = settings.value(QStringLiteral("lockOnStartup"), true).toBool();
    m_salt = QByteArray::fromBase64(settings.value(QStringLiteral("salt")).toByteArray());
    m_passwordHash = QByteArray::fromBase64(settings.value(QStringLiteral("passwordHash")).toByteArray());
    settings.endGroup();

    if (!hasPassword())
        m_lockEnabled = false;
}

void AppLockManager::saveSettings()
{
    QSettings settings;
    settings.beginGroup(QStringLiteral("security"));
    settings.setValue(QStringLiteral("lockEnabled"), m_lockEnabled);
    settings.setValue(QStringLiteral("timeoutMinutes"), m_timeoutMinutes);
    settings.setValue(QStringLiteral("lockOnStartup"), m_lockOnStartup);
    settings.setValue(QStringLiteral("salt"), m_salt.toBase64());
    settings.setValue(QStringLiteral("passwordHash"), m_passwordHash.toBase64());
    settings.endGroup();
    settings.sync();
}

void AppLockManager::restartTimer()
{
    if (!m_lockEnabled || m_locked || !hasPassword()) {
        m_timer->stop();
        return;
    }
    m_timer->start(m_timeoutMinutes * 60 * 1000);
}

void AppLockManager::setStatusMessage(const QString &message)
{
    if (m_statusMessage == message)
        return;
    m_statusMessage = message;
    emit statusMessageChanged();
}
