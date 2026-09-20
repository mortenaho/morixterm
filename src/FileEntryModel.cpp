#include "FileEntryModel.h"

#include <algorithm>

FileEntryModel::FileEntryModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

int FileEntryModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : static_cast<int>(m_entries.size());
}

QVariant FileEntryModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= static_cast<int>(m_entries.size()))
        return {};

    const FileEntry &entry = m_entries[index.row()];
    switch (role) {
    case NameRole: return entry.name;
    case PathRole: return entry.path;
    case PermissionsRole: return entry.permissions;
    case OwnerRole: return entry.owner;
    case GroupRole: return entry.group;
    case SizeRole: return entry.size;
    case DirectoryRole: return entry.directory;
    case ModifiedRole: return entry.modified;
    default: return {};
    }
}

QHash<int, QByteArray> FileEntryModel::roleNames() const
{
    return {
        {NameRole, "name"},
        {PathRole, "path"},
        {PermissionsRole, "permissions"},
        {OwnerRole, "owner"},
        {GroupRole, "group"},
        {SizeRole, "size"},
        {DirectoryRole, "directory"},
        {ModifiedRole, "modified"}
    };
}

void FileEntryModel::setEntries(QVector<FileEntry> entries)
{
    std::sort(entries.begin(), entries.end(), [](const FileEntry &a, const FileEntry &b) {
        if (a.directory != b.directory)
            return a.directory > b.directory;
        return a.name.compare(b.name, Qt::CaseInsensitive) < 0;
    });

    beginResetModel();
    m_entries = std::move(entries);
    endResetModel();
}

const FileEntry *FileEntryModel::entryAt(int row) const
{
    if (row < 0 || row >= static_cast<int>(m_entries.size()))
        return nullptr;
    return &m_entries[row];
}
