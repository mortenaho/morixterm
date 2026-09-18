#pragma once

#include <QAbstractListModel>
#include <QList>
#include <QString>
#include <QVariantMap>

struct SessionEntry
{
    QString id;
    QString name;
    QString host;
    int port = 22;
    QString username;
    QString protocol = QStringLiteral("ssh");
    QString folder;
    QString color;
};

class SessionModel final : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)
    Q_PROPERTY(QString searchText READ searchText WRITE setSearchText NOTIFY searchTextChanged)

public:
    enum Role {
        IdRole = Qt::UserRole + 1,
        NameRole,
        HostRole,
        PortRole,
        UsernameRole,
        ProtocolRole,
        FolderRole,
        ColorRole
    };

    explicit SessionModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    QString searchText() const;
    void setSearchText(const QString &searchText);

    Q_INVOKABLE QVariantMap get(int row) const;
    Q_INVOKABLE bool addSession(const QVariantMap &values);
    Q_INVOKABLE bool updateSession(int row, const QVariantMap &values);
    Q_INVOKABLE bool removeSession(int row);

signals:
    void countChanged();
    void searchTextChanged();
    void persistenceError(const QString &message);

private:
    static SessionEntry fromMap(const QVariantMap &values, const QString &existingId = {});
    QVariantMap toMap(const SessionEntry &entry) const;
    int sourceRow(int visibleRow) const;
    void rebuildFilter();
    void load();
    bool save();
    QString storagePath() const;

    QList<SessionEntry> m_sessions;
    QList<int> m_visibleRows;
    QString m_searchText;
};
