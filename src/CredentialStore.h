#pragma once

#include <QObject>
#include <QString>

class CredentialStore final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool available READ available CONSTANT)
    Q_PROPERTY(QString backend READ backend CONSTANT)

public:
    explicit CredentialStore(QObject *parent = nullptr);

    bool available() const { return m_available; }
    QString backend() const { return m_backend; }

    Q_INVOKABLE bool store(qint64 sessionId, const QString &password);
    Q_INVOKABLE QString read(qint64 sessionId) const;
    Q_INVOKABLE bool remove(qint64 sessionId);

private:
    QString key(qint64 sessionId) const;

    bool m_available = false;
    QString m_backend;
};
