#pragma once

#include <QObject>
#include <QProcess>
#include <QVariantMap>

class ConnectionManager final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool active READ active NOTIFY activeChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(QString title READ title NOTIFY titleChanged)
    Q_PROPERTY(QString statusText READ statusText NOTIFY statusTextChanged)
    Q_PROPERTY(QString output READ output NOTIFY outputChanged)

public:
    explicit ConnectionManager(QObject *parent = nullptr);

    bool active() const;
    bool busy() const;
    QString title() const;
    QString statusText() const;
    QString output() const;

    Q_INVOKABLE void connectSession(const QVariantMap &session);
    Q_INVOKABLE void sendInput(const QString &text);
    Q_INVOKABLE void disconnectSession();
    Q_INVOKABLE void clearOutput();

signals:
    void activeChanged();
    void busyChanged();
    void titleChanged();
    void statusTextChanged();
    void outputChanged();
    void userError(const QString &message);
    void userNotice(const QString &message);

private:
    void appendOutput(const QString &text);
    void setStatusText(const QString &status);
    QString findRdpClient() const;

    QProcess m_process;
    QString m_title;
    QString m_statusText = QStringLiteral("Ready");
    QString m_output;
};
