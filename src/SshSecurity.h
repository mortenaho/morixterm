#pragma once

#include <QObject>
#include <QStringList>

namespace SshSecurity {
QString executable(const QString &name);
QString normalizeProfile(const QString &profile);
QString controlPathTemplate();
QString knownHostsFile();
QString hostKeyLookupName(const QString &host, int port);
QStringList commonOptions(int port,
                          const QString &controlPath,
                          const QString &profile,
                          const QString &keyFile,
                          bool batchMode);
QStringList clientArguments(const QString &host,
                            const QString &user,
                            int port,
                            const QString &controlPath,
                            const QString &profile,
                            const QString &keyFile);
}

class SshSecurityController final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString controlPathTemplate READ controlPathTemplate CONSTANT)
    Q_PROPERTY(QString knownHostsFile READ knownHostsFile CONSTANT)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)
public:
    explicit SshSecurityController(QObject *parent = nullptr) : QObject(parent) {}
    QString controlPathTemplate() const { return SshSecurity::controlPathTemplate(); }
    QString knownHostsFile() const { return SshSecurity::knownHostsFile(); }
    QString lastError() const { return m_lastError; }
    Q_INVOKABLE QString clientExecutable() const { return SshSecurity::executable(QStringLiteral("ssh")); }

    Q_INVOKABLE QStringList buildArguments(const QString &host,
                                           const QString &user,
                                           int port,
                                           const QString &profile,
                                           const QString &keyFile = QString()) const;
    Q_INVOKABLE QString profileWarning(const QString &profile) const;
    Q_INVOKABLE bool replaceHostKey(const QString &host, int port = 22);

signals:
    void lastErrorChanged();

private:
    void setLastError(const QString &message);
    QString m_lastError;
};
