#include "sessionmodel.h"

#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>
#include <QStandardPaths>
#include <QUuid>
#include <utility>

SessionModel::SessionModel(QObject *parent)
    : QAbstractListModel(parent)
{
    load();
}

int SessionModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_visibleRows.size();
}

QVariant SessionModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_visibleRows.size())
        return {};

    const auto &entry = m_sessions.at(sourceRow(index.row()));
    switch (role) {
    case IdRole: return entry.id;
    case NameRole: return entry.name;
    case HostRole: return entry.host;
    case PortRole: return entry.port;
    case UsernameRole: return entry.username;
    case ProtocolRole: return entry.protocol;
    case FolderRole: return entry.folder;
    case ColorRole: return entry.color;
    default: return {};
    }
}

QHash<int, QByteArray> SessionModel::roleNames() const
{
    return {
        {IdRole, "sessionId"}, {NameRole, "name"}, {HostRole, "host"},
        {PortRole, "port"}, {UsernameRole, "username"},
        {ProtocolRole, "protocol"}, {FolderRole, "folder"}, {ColorRole, "accentColor"}
    };
}

QString SessionModel::searchText() const
{
    return m_searchText;
}

void SessionModel::setSearchText(const QString &searchText)
{
    if (m_searchText == searchText)
        return;
    m_searchText = searchText;
    beginResetModel();
    rebuildFilter();
    endResetModel();
    emit searchTextChanged();
    emit countChanged();
}

QVariantMap SessionModel::get(int row) const
{
    if (row < 0 || row >= m_visibleRows.size())
        return {};
    return toMap(m_sessions.at(sourceRow(row)));
}

bool SessionModel::addSession(const QVariantMap &values)
{
    const auto entry = fromMap(values);
    if (entry.name.isEmpty() || entry.host.isEmpty() || entry.port < 1 || entry.port > 65535)
        return false;

    beginResetModel();
    m_sessions.append(entry);
    rebuildFilter();
    endResetModel();
    emit countChanged();
    return save();
}

bool SessionModel::updateSession(int row, const QVariantMap &values)
{
    const int source = sourceRow(row);
    if (source < 0 || source >= m_sessions.size())
        return false;

    const auto entry = fromMap(values, m_sessions.at(source).id);
    if (entry.name.isEmpty() || entry.host.isEmpty() || entry.port < 1 || entry.port > 65535)
        return false;

    beginResetModel();
    m_sessions[source] = entry;
    rebuildFilter();
    endResetModel();
    return save();
}

bool SessionModel::removeSession(int row)
{
    const int source = sourceRow(row);
    if (source < 0 || source >= m_sessions.size())
        return false;

    beginResetModel();
    m_sessions.removeAt(source);
    rebuildFilter();
    endResetModel();
    emit countChanged();
    return save();
}

SessionEntry SessionModel::fromMap(const QVariantMap &values, const QString &existingId)
{
    SessionEntry entry;
    entry.id = existingId.isEmpty() ? QUuid::createUuid().toString(QUuid::WithoutBraces) : existingId;
    entry.name = values.value(QStringLiteral("name")).toString().trimmed();
    entry.host = values.value(QStringLiteral("host")).toString().trimmed();
    entry.username = values.value(QStringLiteral("username")).toString().trimmed();
    entry.protocol = values.value(QStringLiteral("protocol"), QStringLiteral("ssh")).toString().toLower();
    if (entry.protocol != QStringLiteral("rdp"))
        entry.protocol = QStringLiteral("ssh");
    const int defaultPort = entry.protocol == QStringLiteral("ssh") ? 22 : 3389;
    entry.port = values.value(QStringLiteral("port"), defaultPort).toInt();
    entry.folder = values.value(QStringLiteral("folder")).toString().trimmed();
    entry.color = values.value(QStringLiteral("color"), entry.protocol == QStringLiteral("ssh")
        ? QStringLiteral("#e6b422") : QStringLiteral("#5b9bd5")).toString();
    return entry;
}

QVariantMap SessionModel::toMap(const SessionEntry &entry) const
{
    return {
        {QStringLiteral("id"), entry.id}, {QStringLiteral("name"), entry.name},
        {QStringLiteral("host"), entry.host}, {QStringLiteral("port"), entry.port},
        {QStringLiteral("username"), entry.username}, {QStringLiteral("protocol"), entry.protocol},
        {QStringLiteral("folder"), entry.folder}, {QStringLiteral("color"), entry.color}
    };
}

int SessionModel::sourceRow(int visibleRow) const
{
    return visibleRow >= 0 && visibleRow < m_visibleRows.size() ? m_visibleRows.at(visibleRow) : -1;
}

void SessionModel::rebuildFilter()
{
    m_visibleRows.clear();
    const auto needle = m_searchText.trimmed();
    for (int i = 0; i < m_sessions.size(); ++i) {
        const auto &entry = m_sessions.at(i);
        if (needle.isEmpty() || entry.name.contains(needle, Qt::CaseInsensitive)
            || entry.host.contains(needle, Qt::CaseInsensitive)
            || entry.username.contains(needle, Qt::CaseInsensitive)
            || entry.folder.contains(needle, Qt::CaseInsensitive)) {
            m_visibleRows.append(i);
        }
    }
}

QString SessionModel::storagePath() const
{
    const auto directory = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    QDir().mkpath(directory);
    return directory + QStringLiteral("/sessions.json");
}

void SessionModel::load()
{
    QFile file(storagePath());
    if (!file.exists()) {
        rebuildFilter();
        return;
    }
    if (!file.open(QIODevice::ReadOnly)) {
        emit persistenceError(tr("Could not read saved sessions."));
        return;
    }

    QJsonParseError error;
    const auto document = QJsonDocument::fromJson(file.readAll(), &error);
    if (error.error != QJsonParseError::NoError || !document.isArray()) {
        emit persistenceError(tr("Saved sessions file is invalid."));
        return;
    }

    for (const auto &value : document.array())
        if (value.isObject())
            m_sessions.append(fromMap(value.toObject().toVariantMap(), value.toObject().value("id").toString()));
    rebuildFilter();
}

bool SessionModel::save()
{
    QJsonArray array;
    for (const auto &entry : std::as_const(m_sessions))
        array.append(QJsonObject::fromVariantMap(toMap(entry)));

    QSaveFile file(storagePath());
    if (!file.open(QIODevice::WriteOnly)
        || file.write(QJsonDocument(array).toJson(QJsonDocument::Indented)) < 0
        || !file.commit()) {
        emit persistenceError(tr("Could not save sessions."));
        return false;
    }
    return true;
}
