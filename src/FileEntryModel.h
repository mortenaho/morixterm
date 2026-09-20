#pragma once

#include <QAbstractListModel>
#include <QDateTime>
#include <QVector>

struct FileEntry
{
    QString name;
    QString path;
    QString permissions;
    QString owner;
    QString group;
    qint64 size = 0;
    bool directory = false;
    QDateTime modified;
};

class FileEntryModel : public QAbstractListModel
{
    Q_OBJECT

public:
    enum Roles {
        NameRole = Qt::UserRole + 1,
        PathRole,
        PermissionsRole,
        OwnerRole,
        GroupRole,
        SizeRole,
        DirectoryRole,
        ModifiedRole
    };

    explicit FileEntryModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    void setEntries(QVector<FileEntry> entries);
    const FileEntry *entryAt(int row) const;

private:
    QVector<FileEntry> m_entries;
};
