#pragma once

#include <QObject>
#include <QByteArray>

class QTimer;

class AppLockManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool lockEnabled READ lockEnabled WRITE setLockEnabled NOTIFY settingsChanged)
    Q_PROPERTY(bool locked READ locked NOTIFY lockedChanged)
    Q_PROPERTY(bool hasPassword READ hasPassword NOTIFY passwordChanged)
    Q_PROPERTY(int timeoutMinutes READ timeoutMinutes WRITE setTimeoutMinutes NOTIFY settingsChanged)
    Q_PROPERTY(bool lockOnStartup READ lockOnStartup WRITE setLockOnStartup NOTIFY settingsChanged)
    Q_PROPERTY(QString statusMessage READ statusMessage NOTIFY statusMessageChanged)

public:
    explicit AppLockManager(QObject *parent = nullptr);

    bool lockEnabled() const { return m_lockEnabled; }
    bool locked() const { return m_locked; }
    bool hasPassword() const { return !m_passwordHash.isEmpty() && !m_salt.isEmpty(); }
    int timeoutMinutes() const { return m_timeoutMinutes; }
    bool lockOnStartup() const { return m_lockOnStartup; }
    QString statusMessage() const { return m_statusMessage; }

    void setLockEnabled(bool enabled);
    void setTimeoutMinutes(int minutes);
    void setLockOnStartup(bool enabled);

    Q_INVOKABLE bool setPassword(const QString &currentPassword, const QString &newPassword);
    Q_INVOKABLE bool removePassword(const QString &currentPassword);
    Q_INVOKABLE bool unlock(const QString &password);
    Q_INVOKABLE void lockNow();
    Q_INVOKABLE void resetActivityTimer();

signals:
    void settingsChanged();
    void lockedChanged();
    void passwordChanged();
    void statusMessageChanged();

protected:
    bool eventFilter(QObject *watched, QEvent *event) override;

private:
    QByteArray deriveKey(const QString &password, const QByteArray &salt) const;
    bool verifyPassword(const QString &password) const;
    void loadSettings();
    void saveSettings();
    void restartTimer();
    void setStatusMessage(const QString &message);

    QTimer *m_timer = nullptr;
    bool m_lockEnabled = false;
    bool m_locked = false;
    bool m_lockOnStartup = true;
    int m_timeoutMinutes = 10;
    QByteArray m_salt;
    QByteArray m_passwordHash;
    QString m_statusMessage;
    int m_failedUnlockAttempts = 0;
    qint64 m_retryUnlockAfterMs = 0;
};
