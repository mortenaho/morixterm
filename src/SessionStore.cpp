#include "SessionStore.h"
#include "CredentialStore.h"

#include <QDir>
#include <QFile>
#include <QRegularExpression>
#include <QSqlError>
#include <QSqlQuery>
#include <QStandardPaths>
#include <QUuid>

#include <algorithm>
#include <utility>

namespace {
QString trimmedOr(const QString &value, const QString &fallback)
{
    const QString clean = value.trimmed();
    return clean.isEmpty() ? fallback : clean;
}
}

SessionStore::SessionStore(CredentialStore *credentialStore, QObject *parent)
    : QAbstractListModel(parent),
      m_connectionName(QStringLiteral("morixtrem-sessions-%1").arg(QUuid::createUuid().toString(QUuid::WithoutBraces))),
      m_credentialStore(credentialStore)
{
    const QString appData = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    QDir().mkpath(appData);
    QFile::setPermissions(appData, QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner);
    m_databasePath = QDir(appData).filePath(QStringLiteral("morixtrem.db"));

    if (openDatabase() && ensureSchema()) {
        QFile::setPermissions(m_databasePath, QFileDevice::ReadOwner | QFileDevice::WriteOwner);
        reload();
    }
}

SessionStore::~SessionStore()
{
    const QString connectionName = m_connectionName;
    if (m_db.isValid())
        m_db.close();
    m_db = QSqlDatabase();
    QSqlDatabase::removeDatabase(connectionName);
}

int SessionStore::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : static_cast<int>(m_nodes.size());
}

QVariant SessionStore::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_nodes.size())
        return {};

    const SessionNode &node = m_nodes.at(index.row());
    if (node.folder) {
        switch (role) {
        case IsFolderRole: return true;
        case ItemIdRole:
        case FolderIdRole: return node.folderData.id;
        case SessionIdRole: return 0;
        case NameRole: return node.folderData.name;
        case KindRole: return QStringLiteral("folder");
        case DepthRole: return node.depth;
        case ExpandedRole: return m_expandedFolders.contains(node.folderData.id);
        case ChildCountRole: return node.childCount;
        case HostRole:
        case UserRole:
        case DomainRole:
        case SecurityProfileRole:
        case KeyFileRole:
        case LastUsedAtRole: return QString();
        case PortRole: return 0;
        case WidthRole: return 0;
        case HeightRole: return 0;
        case ScaleRole: return 0;
        case FullscreenRole:
        case IgnoreCertificateRole:
        case CredentialSavedRole:
        case FtpTlsRole:
        case FtpPassiveRole:
        case OverwriteExistingRole: return false;
        case MaxParallelRole: return 0;
        default: return {};
        }
    }

    const SavedSession &s = node.sessionData;
    switch (role) {
    case IsFolderRole: return false;
    case ItemIdRole:
    case SessionIdRole: return s.id;
    case FolderIdRole: return s.folderId;
    case NameRole: return s.name;
    case KindRole: return s.kind;
    case HostRole: return s.host;
    case UserRole: return s.user;
    case PortRole: return s.port;
    case DomainRole: return s.domain;
    case WidthRole: return s.width;
    case HeightRole: return s.height;
    case ScaleRole: return s.scale;
    case FullscreenRole: return s.fullscreen;
    case IgnoreCertificateRole: return s.ignoreCertificate;
    case SecurityProfileRole: return s.securityProfile;
    case KeyFileRole: return s.keyFile;
    case CredentialSavedRole: return s.credentialSaved;
    case FtpTlsRole: return s.ftpTls;
    case FtpPassiveRole: return s.ftpPassive;
    case OverwriteExistingRole: return s.overwriteExisting;
    case MaxParallelRole: return s.maxParallel;
    case DepthRole: return node.depth;
    case ExpandedRole: return false;
    case ChildCountRole: return 0;
    case LastUsedAtRole: return s.lastUsedAt;
    default: return {};
    }
}

QHash<int, QByteArray> SessionStore::roleNames() const
{
    return {
        {IsFolderRole, "isFolder"}, {ItemIdRole, "itemId"}, {SessionIdRole, "sessionId"},
        {FolderIdRole, "folderId"}, {NameRole, "name"}, {KindRole, "kind"},
        {HostRole, "host"}, {UserRole, "user"}, {PortRole, "port"}, {DomainRole, "domain"},
        {WidthRole, "rdpWidth"}, {HeightRole, "rdpHeight"}, {ScaleRole, "rdpScale"}, {FullscreenRole, "fullscreen"},
        {IgnoreCertificateRole, "ignoreCertificate"}, {SecurityProfileRole, "securityProfile"},
        {KeyFileRole, "keyFile"}, {CredentialSavedRole, "credentialSaved"}, {DepthRole, "depth"},
        {ExpandedRole, "expanded"}, {ChildCountRole, "childCount"},
        {FtpTlsRole, "ftpTls"}, {FtpPassiveRole, "ftpPassive"},
        {OverwriteExistingRole, "overwriteExisting"}, {MaxParallelRole, "maxParallel"},
        {LastUsedAtRole, "lastUsedAt"}
    };
}

qint64 SessionStore::saveSession(qint64 sessionId,
                                 const QString &name,
                                 const QString &kind,
                                 const QString &host,
                                 const QString &user,
                                 int port,
                                 const QString &password,
                                 bool rememberPassword,
                                 bool removeSavedPassword,
                                 qint64 folderId,
                                 const QString &securityProfile,
                                 const QString &keyFile,
                                 const QString &domain,
                                 int width,
                                 int height,
                                 bool fullscreen,
                                 bool ignoreCertificate,
                                 bool ftpTls,
                                 bool ftpPassive,
                                 bool overwriteExisting,
                                 int maxParallel,
                                 int scale)
{
    if (!m_db.isOpen() && !openDatabase())
        return 0;
    if (!ensureSchema())
        return 0;

    QString cleanKind = kind.trimmed().toLower();
    if (cleanKind != QStringLiteral("ssh") && cleanKind != QStringLiteral("rdp") &&
        cleanKind != QStringLiteral("sftp") && cleanKind != QStringLiteral("ftp"))
        cleanKind = QStringLiteral("ssh");
    const QString cleanHost = host.trimmed();
    const QString cleanUser = user.trimmed();
    if (!validHost(cleanHost)) {
        setLastError(QStringLiteral("Invalid host. Use a hostname or IP address, not an SSH option."));
        return 0;
    }
    if (!validUser(cleanUser)) {
        setLastError(QStringLiteral("Invalid username."));
        return 0;
    }

    if (port < 1 || port > 65535) {
        if (cleanKind == QStringLiteral("rdp")) port = 3389;
        else if (cleanKind == QStringLiteral("ftp")) port = 21;
        else port = 22;
    }
    maxParallel = qBound(1, maxParallel, 8);
    width = qBound(640, width, 7680);
    height = qBound(480, height, 4320);
    scale = qBound(100, scale, 300);

    if (folderId > 0) {
        QSqlQuery check(m_db);
        check.prepare(QStringLiteral("SELECT 1 FROM session_folders WHERE id=?"));
        check.addBindValue(folderId);
        if (!check.exec() || !check.next())
            folderId = 0;
    }

    const QString cleanName = trimmedOr(name, cleanHost);
    const QString profile = normalizedSecurityProfile(securityProfile);
    bool ok = false;

    m_db.transaction();
    if (sessionId > 0) {
        QSqlQuery q(m_db);
        q.prepare(QStringLiteral(
            "UPDATE sessions SET name=?, kind=?, host=?, user_name=?, port=?, domain_name=?, rdp_width=?, rdp_height=?, rdp_scale=?, "
            "fullscreen=?, ignore_certificate=?, folder_id=?, security_profile=?, key_file=?, ftp_tls=?, ftp_passive=?, "
            "overwrite_existing=?, max_parallel=?, updated_at=CURRENT_TIMESTAMP WHERE id=?"));
        q.addBindValue(cleanName);
        q.addBindValue(cleanKind);
        q.addBindValue(cleanHost);
        q.addBindValue(cleanUser);
        q.addBindValue(port);
        q.addBindValue(domain.trimmed());
        q.addBindValue(width);
        q.addBindValue(height);
        q.addBindValue(scale);
        q.addBindValue(fullscreen ? 1 : 0);
        q.addBindValue(ignoreCertificate ? 1 : 0);
        q.addBindValue(folderId > 0 ? QVariant(folderId) : QVariant());
        q.addBindValue(profile);
        q.addBindValue(keyFile.trimmed());
        q.addBindValue(ftpTls ? 1 : 0);
        q.addBindValue(ftpPassive ? 1 : 0);
        q.addBindValue(overwriteExisting ? 1 : 0);
        q.addBindValue(maxParallel);
        q.addBindValue(sessionId);
        ok = q.exec() && q.numRowsAffected() > 0;
        if (!ok)
            setLastError(q.lastError().text());
    } else {
        QSqlQuery q(m_db);
        q.prepare(QStringLiteral(
            "INSERT INTO sessions(name, kind, host, user_name, port, domain_name, rdp_width, rdp_height, rdp_scale, fullscreen, ignore_certificate, "
            "folder_id, security_profile, key_file, ftp_tls, ftp_passive, overwrite_existing, max_parallel, credential_saved, created_at, updated_at) "
            "VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)"));
        q.addBindValue(cleanName);
        q.addBindValue(cleanKind);
        q.addBindValue(cleanHost);
        q.addBindValue(cleanUser);
        q.addBindValue(port);
        q.addBindValue(domain.trimmed());
        q.addBindValue(width);
        q.addBindValue(height);
        q.addBindValue(scale);
        q.addBindValue(fullscreen ? 1 : 0);
        q.addBindValue(ignoreCertificate ? 1 : 0);
        q.addBindValue(folderId > 0 ? QVariant(folderId) : QVariant());
        q.addBindValue(profile);
        q.addBindValue(keyFile.trimmed());
        q.addBindValue(ftpTls ? 1 : 0);
        q.addBindValue(ftpPassive ? 1 : 0);
        q.addBindValue(overwriteExisting ? 1 : 0);
        q.addBindValue(maxParallel);
        ok = q.exec();
        if (ok)
            sessionId = q.lastInsertId().toLongLong();
        else
            setLastError(q.lastError().text());
    }

    if (!ok) {
        m_db.rollback();
        return 0;
    }

    bool credentialSaved = false;
    QSqlQuery existing(m_db);
    existing.prepare(QStringLiteral("SELECT credential_saved FROM sessions WHERE id=?"));
    existing.addBindValue(sessionId);
    if (existing.exec() && existing.next())
        credentialSaved = existing.value(0).toBool();

    if (removeSavedPassword && m_credentialStore) {
        m_credentialStore->remove(sessionId);
        credentialSaved = false;
    }

    if (rememberPassword && !password.isEmpty()) {
        if (!m_credentialStore || !m_credentialStore->available() || !m_credentialStore->store(sessionId, password)) {
            m_db.rollback();
            setLastError(QStringLiteral("The session was not saved because the password could not be stored securely."));
            return 0;
        }
        credentialSaved = true;
    }

    QSqlQuery credentialFlag(m_db);
    credentialFlag.prepare(QStringLiteral("UPDATE sessions SET credential_saved=? WHERE id=?"));
    credentialFlag.addBindValue(credentialSaved ? 1 : 0);
    credentialFlag.addBindValue(sessionId);
    if (!credentialFlag.exec()) {
        m_db.rollback();
        setLastError(credentialFlag.lastError().text());
        return 0;
    }

    if (!m_db.commit()) {
        setLastError(m_db.lastError().text());
        return 0;
    }

    setLastError({});
    reload();
    return sessionId;
}

bool SessionStore::removeSessionById(qint64 sessionId)
{
    if (sessionId <= 0 || !m_db.isOpen())
        return false;
    QSqlQuery q(m_db);
    q.prepare(QStringLiteral("DELETE FROM sessions WHERE id=?"));
    q.addBindValue(sessionId);
    if (!q.exec()) {
        setLastError(q.lastError().text());
        return false;
    }
    if (m_credentialStore)
        m_credentialStore->remove(sessionId);
    reload();
    return true;
}

bool SessionStore::createFolder(const QString &name)
{
    const QString clean = name.trimmed();
    if (clean.isEmpty() || clean.size() > 80) {
        setLastError(QStringLiteral("Folder name is required and must be shorter than 80 characters."));
        return false;
    }
    QSqlQuery q(m_db);
    q.prepare(QStringLiteral("INSERT INTO session_folders(name) VALUES(?)"));
    q.addBindValue(clean);
    if (!q.exec()) {
        setLastError(q.lastError().text());
        return false;
    }
    m_expandedFolders.insert(q.lastInsertId().toLongLong());
    reload();
    emit foldersChanged();
    return true;
}

bool SessionStore::renameFolder(qint64 folderId, const QString &name)
{
    const QString clean = name.trimmed();
    if (folderId <= 0 || clean.isEmpty() || clean.size() > 80)
        return false;
    QSqlQuery q(m_db);
    q.prepare(QStringLiteral("UPDATE session_folders SET name=? WHERE id=?"));
    q.addBindValue(clean);
    q.addBindValue(folderId);
    if (!q.exec()) {
        setLastError(q.lastError().text());
        return false;
    }
    reload();
    emit foldersChanged();
    return true;
}

bool SessionStore::deleteFolder(qint64 folderId)
{
    if (folderId <= 0)
        return false;
    m_db.transaction();
    QSqlQuery move(m_db);
    move.prepare(QStringLiteral("UPDATE sessions SET folder_id=NULL WHERE folder_id=?"));
    move.addBindValue(folderId);
    if (!move.exec()) {
        m_db.rollback();
        setLastError(move.lastError().text());
        return false;
    }
    QSqlQuery q(m_db);
    q.prepare(QStringLiteral("DELETE FROM session_folders WHERE id=?"));
    q.addBindValue(folderId);
    if (!q.exec()) {
        m_db.rollback();
        setLastError(q.lastError().text());
        return false;
    }
    m_db.commit();
    m_expandedFolders.remove(folderId);
    reload();
    emit foldersChanged();
    return true;
}

bool SessionStore::moveSessionToFolder(qint64 sessionId, qint64 folderId)
{
    if (!m_db.isOpen() && !openDatabase())
        return false;
    if (!ensureSchema())
        return false;

    if (sessionId <= 0) {
        setLastError(QStringLiteral("Invalid session."));
        return false;
    }

    QSqlQuery sessionCheck(m_db);
    sessionCheck.prepare(QStringLiteral("SELECT COALESCE(folder_id,0) FROM sessions WHERE id=?"));
    sessionCheck.addBindValue(sessionId);
    if (!sessionCheck.exec() || !sessionCheck.next()) {
        setLastError(QStringLiteral("The session no longer exists."));
        return false;
    }
    const qint64 currentFolderId = sessionCheck.value(0).toLongLong();

    if (folderId > 0) {
        QSqlQuery folderCheck(m_db);
        folderCheck.prepare(QStringLiteral("SELECT 1 FROM session_folders WHERE id=?"));
        folderCheck.addBindValue(folderId);
        if (!folderCheck.exec() || !folderCheck.next()) {
            setLastError(QStringLiteral("The destination folder no longer exists."));
            return false;
        }
    }

    if (currentFolderId == folderId) {
        if (folderId > 0)
            m_expandedFolders.insert(folderId);
        setLastError({});
        reload();
        return true;
    }

    QSqlQuery q(m_db);
    q.prepare(QStringLiteral("UPDATE sessions SET folder_id=?, updated_at=CURRENT_TIMESTAMP WHERE id=?"));
    q.addBindValue(folderId > 0 ? QVariant(folderId) : QVariant());
    q.addBindValue(sessionId);
    if (!q.exec()) {
        setLastError(q.lastError().text());
        return false;
    }
    if (q.numRowsAffected() <= 0) {
        setLastError(QStringLiteral("The session no longer exists."));
        return false;
    }

    if (folderId > 0)
        m_expandedFolders.insert(folderId);
    setLastError({});
    reload();
    return true;
}

void SessionStore::toggleFolder(qint64 folderId)
{
    if (folderId <= 0)
        return;
    if (m_expandedFolders.contains(folderId))
        m_expandedFolders.remove(folderId);
    else
        m_expandedFolders.insert(folderId);
    reload();
}

QVariantList SessionStore::folderOptions() const
{
    QVariantList result;
    QVariantMap root;
    root.insert(QStringLiteral("id"), 0);
    root.insert(QStringLiteral("name"), QStringLiteral("Ungrouped"));
    result.push_back(root);
    for (const auto &folder : m_folders) {
        QVariantMap item;
        item.insert(QStringLiteral("id"), folder.id);
        item.insert(QStringLiteral("name"), folder.name);
        result.push_back(item);
    }
    return result;
}

QVariantList SessionStore::recentSessions(int limit) const
{
    QVariantList result;
    QVector<SavedSession> sessions = m_sessions;
    std::stable_sort(sessions.begin(), sessions.end(), [](const SavedSession &a, const SavedSession &b) {
        return a.lastUsedAt > b.lastUsedAt;
    });
    const int count = std::min(qBound(1, limit, 20), static_cast<int>(sessions.size()));
    for (int i = 0; i < count; ++i) {
        const auto &s = sessions.at(i);
        QVariantMap m;
        m.insert(QStringLiteral("sessionId"), s.id);
        m.insert(QStringLiteral("name"), s.name);
        m.insert(QStringLiteral("kind"), s.kind);
        m.insert(QStringLiteral("host"), s.host);
        m.insert(QStringLiteral("user"), s.user);
        m.insert(QStringLiteral("port"), s.port);
        m.insert(QStringLiteral("domain"), s.domain);
        m.insert(QStringLiteral("rdpWidth"), s.width);
        m.insert(QStringLiteral("rdpHeight"), s.height);
        m.insert(QStringLiteral("rdpScale"), s.scale);
        m.insert(QStringLiteral("fullscreen"), s.fullscreen);
        m.insert(QStringLiteral("ignoreCertificate"), s.ignoreCertificate);
        m.insert(QStringLiteral("folderId"), s.folderId);
        m.insert(QStringLiteral("securityProfile"), s.securityProfile);
        m.insert(QStringLiteral("keyFile"), s.keyFile);
        m.insert(QStringLiteral("credentialSaved"), s.credentialSaved);
        m.insert(QStringLiteral("ftpTls"), s.ftpTls);
        m.insert(QStringLiteral("ftpPassive"), s.ftpPassive);
        m.insert(QStringLiteral("overwriteExisting"), s.overwriteExisting);
        m.insert(QStringLiteral("maxParallel"), s.maxParallel);
        result.push_back(m);
    }
    return result;
}

QString SessionStore::passwordForSession(qint64 sessionId) const
{
    if (!m_credentialStore)
        return {};
    return m_credentialStore->read(sessionId);
}

void SessionStore::markUsed(qint64 sessionId)
{
    if (sessionId <= 0 || !m_db.isOpen())
        return;
    QSqlQuery q(m_db);
    q.prepare(QStringLiteral("UPDATE sessions SET last_used_at=CURRENT_TIMESTAMP WHERE id=?"));
    q.addBindValue(sessionId);
    q.exec();
    reload();
}

bool SessionStore::setIgnoreCertificate(qint64 sessionId, bool enabled)
{
    if (sessionId <= 0 || !m_db.isOpen()) {
        setLastError(QStringLiteral("Invalid session."));
        return false;
    }
    QSqlQuery q(m_db);
    q.prepare(QStringLiteral("UPDATE sessions SET ignore_certificate=?, updated_at=CURRENT_TIMESTAMP WHERE id=?"));
    q.addBindValue(enabled ? 1 : 0);
    q.addBindValue(sessionId);
    if (!q.exec()) {
        setLastError(q.lastError().text());
        return false;
    }
    if (q.numRowsAffected() <= 0) {
        setLastError(QStringLiteral("The session no longer exists."));
        return false;
    }
    setLastError({});
    reload();
    return true;
}

void SessionStore::reload()
{
    if (!m_db.isOpen())
        return;
    // Retry/verify the schema before reading. This is intentionally done here as
    // well as at startup so an interrupted legacy migration cannot leave the UI
    // attached to an old sessions table.
    if (!ensureSchema())
        return;

    QVector<SessionFolder> folders;
    QSqlQuery fq(m_db);
    if (!fq.exec(QStringLiteral("SELECT id, name FROM session_folders ORDER BY name COLLATE NOCASE, id"))) {
        setLastError(fq.lastError().text());
        return;
    }
    while (fq.next()) {
        SessionFolder f;
        f.id = fq.value(0).toLongLong();
        f.name = fq.value(1).toString();
        folders.push_back(f);
        if (!m_expandedFolders.contains(f.id) && m_expandedFolders.isEmpty())
            m_expandedFolders.insert(f.id);
    }

    QVector<SavedSession> sessions;
    QSqlQuery q(m_db);
    if (!q.exec(QStringLiteral(
            "SELECT id, name, kind, host, user_name, port, domain_name, rdp_width, rdp_height, rdp_scale, fullscreen, ignore_certificate, "
            "COALESCE(folder_id,0), security_profile, key_file, credential_saved, ftp_tls, ftp_passive, overwrite_existing, max_parallel, "
            "COALESCE(last_used_at,'') FROM sessions ORDER BY name COLLATE NOCASE, id"))) {
        setLastError(q.lastError().text());
        return;
    }
    while (q.next()) {
        SavedSession s;
        s.id = q.value(0).toLongLong();
        s.name = q.value(1).toString();
        s.kind = q.value(2).toString();
        s.host = q.value(3).toString();
        s.user = q.value(4).toString();
        s.port = q.value(5).toInt();
        s.domain = q.value(6).toString();
        s.width = q.value(7).toInt();
        s.height = q.value(8).toInt();
        s.scale = qBound(100, q.value(9).toInt(), 300);
        s.fullscreen = q.value(10).toBool();
        s.ignoreCertificate = q.value(11).toBool();
        s.folderId = q.value(12).toLongLong();
        s.securityProfile = q.value(13).toString();
        s.keyFile = q.value(14).toString();
        s.credentialSaved = q.value(15).toBool();
        s.ftpTls = q.value(16).toBool();
        s.ftpPassive = q.value(17).toBool();
        s.overwriteExisting = q.value(18).toBool();
        s.maxParallel = qBound(1, q.value(19).toInt(), 8);
        s.lastUsedAt = q.value(20).toString();
        sessions.push_back(std::move(s));
    }

    beginResetModel();
    m_folders = folders;
    m_sessions = sessions;
    rebuildNodes(folders, sessions);
    endResetModel();
    setLastError({});
}

bool SessionStore::openDatabase()
{
    if (!m_db.isValid()) {
        m_db = QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), m_connectionName);
        m_db.setDatabaseName(m_databasePath);
    }
    if (!m_db.open()) {
        setLastError(m_db.lastError().text());
        return false;
    }
    QSqlQuery q(m_db);
    q.exec(QStringLiteral("PRAGMA foreign_keys=ON"));
    q.exec(QStringLiteral("PRAGMA journal_mode=WAL"));
    q.exec(QStringLiteral("PRAGMA synchronous=NORMAL"));
    q.exec(QStringLiteral("PRAGMA secure_delete=ON"));
    q.exec(QStringLiteral("PRAGMA busy_timeout=3000"));
    return true;
}

bool SessionStore::ensureSchema()
{
    QSqlQuery q(m_db);
    if (!q.exec(QStringLiteral(
            "CREATE TABLE IF NOT EXISTS session_folders ("
            " id INTEGER PRIMARY KEY AUTOINCREMENT,"
            " name TEXT NOT NULL UNIQUE COLLATE NOCASE,"
            " created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP"
            ")"))) {
        setLastError(q.lastError().text());
        return false;
    }

    if (!q.exec(QStringLiteral(
            "CREATE TABLE IF NOT EXISTS sessions ("
            " id INTEGER PRIMARY KEY AUTOINCREMENT,"
            " name TEXT NOT NULL,"
            " kind TEXT NOT NULL,"
            " host TEXT NOT NULL,"
            " user_name TEXT NOT NULL DEFAULT '',"
            " port INTEGER NOT NULL,"
            " domain_name TEXT NOT NULL DEFAULT '',"
            " rdp_width INTEGER NOT NULL DEFAULT 1440,"
            " rdp_height INTEGER NOT NULL DEFAULT 900,"
            " rdp_scale INTEGER NOT NULL DEFAULT 100,"
            " fullscreen INTEGER NOT NULL DEFAULT 0,"
            " ignore_certificate INTEGER NOT NULL DEFAULT 0,"
            " folder_id INTEGER REFERENCES session_folders(id) ON DELETE SET NULL,"
            " security_profile TEXT NOT NULL DEFAULT 'modern',"
            " key_file TEXT NOT NULL DEFAULT '',"
            " ftp_tls INTEGER NOT NULL DEFAULT 1,"
            " ftp_passive INTEGER NOT NULL DEFAULT 1,"
            " overwrite_existing INTEGER NOT NULL DEFAULT 1,"
            " max_parallel INTEGER NOT NULL DEFAULT 4,"
            " credential_saved INTEGER NOT NULL DEFAULT 0,"
            " last_used_at TEXT,"
            " created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,"
            " updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP"
            ")"))) {
        setLastError(q.lastError().text());
        return false;
    }

    // Migrate databases created by MoriXterm <= 0.5.
    if (!ensureColumn(QStringLiteral("sessions"), QStringLiteral("folder_id"),
                      QStringLiteral("INTEGER REFERENCES session_folders(id) ON DELETE SET NULL")) ||
        !ensureColumn(QStringLiteral("sessions"), QStringLiteral("security_profile"),
                      QStringLiteral("TEXT NOT NULL DEFAULT 'modern'")) ||
        !ensureColumn(QStringLiteral("sessions"), QStringLiteral("key_file"),
                      QStringLiteral("TEXT NOT NULL DEFAULT ''")) ||
        !ensureColumn(QStringLiteral("sessions"), QStringLiteral("credential_saved"),
                      QStringLiteral("INTEGER NOT NULL DEFAULT 0")) ||
        !ensureColumn(QStringLiteral("sessions"), QStringLiteral("ftp_tls"),
                      QStringLiteral("INTEGER NOT NULL DEFAULT 1")) ||
        !ensureColumn(QStringLiteral("sessions"), QStringLiteral("rdp_scale"),
                      QStringLiteral("INTEGER NOT NULL DEFAULT 100")) ||
        !ensureColumn(QStringLiteral("sessions"), QStringLiteral("ftp_passive"),
                      QStringLiteral("INTEGER NOT NULL DEFAULT 1")) ||
        !ensureColumn(QStringLiteral("sessions"), QStringLiteral("overwrite_existing"),
                      QStringLiteral("INTEGER NOT NULL DEFAULT 1")) ||
        !ensureColumn(QStringLiteral("sessions"), QStringLiteral("max_parallel"),
                      QStringLiteral("INTEGER NOT NULL DEFAULT 4")) ||
        !ensureColumn(QStringLiteral("sessions"), QStringLiteral("last_used_at"), QStringLiteral("TEXT")) ||
        // SQLite ALTER TABLE cannot add a column with a non-constant CURRENT_TIMESTAMP default.
        // Existing databases therefore get a nullable column which is backfilled below; new
        // databases still use the stricter CREATE TABLE definition above.
        !ensureColumn(QStringLiteral("sessions"), QStringLiteral("updated_at"), QStringLiteral("TEXT")))
        return false;

    // Schema repair for legacy versions. Older releases constrained `kind` to
    // ssh/rdp (or later to a fixed four-value list). SQLite cannot alter a CHECK
    // constraint in-place. We therefore perform a one-time table rebuild and
    // deliberately remove the database CHECK: SessionStore validates protocol
    // values in C++, which also makes future protocol additions migration-free.
    constexpr int kSessionSchemaVersion = 906;
    int userVersion = 0;
    {
        QSqlQuery versionQuery(m_db);
        if (versionQuery.exec(QStringLiteral("PRAGMA user_version")) && versionQuery.next())
            userVersion = versionQuery.value(0).toInt();
        versionQuery.finish();
    }

    QString sessionsSql;
    {
        QSqlQuery schemaQuery(m_db);
        schemaQuery.prepare(QStringLiteral("SELECT sql FROM sqlite_master WHERE type='table' AND name='sessions'"));
        if (!schemaQuery.exec() || !schemaQuery.next()) {
            setLastError(schemaQuery.lastError().text().isEmpty()
                         ? QStringLiteral("Unable to inspect the sessions database schema.")
                         : schemaQuery.lastError().text());
            return false;
        }
        sessionsSql = schemaQuery.value(0).toString();
        // IMPORTANT: finalize the sqlite_master reader before DDL. Keeping this
        // query active can prevent ALTER/DROP TABLE on some SQLite/Qt builds.
        schemaQuery.finish();
    }

    const QString normalizedSql = sessionsSql.simplified().toLower();
    const bool hasLegacyKindCheck = normalizedSql.contains(QStringLiteral("check")) &&
                                    normalizedSql.contains(QStringLiteral("kind"));
    const bool needsRebuild = userVersion < kSessionSchemaVersion || hasLegacyKindCheck;

    if (needsRebuild) {
        QSqlQuery pragma(m_db);
        if (!pragma.exec(QStringLiteral("PRAGMA foreign_keys=OFF"))) {
            setLastError(pragma.lastError().text());
            return false;
        }
        pragma.finish();

        QSqlQuery migrate(m_db);
        if (!migrate.exec(QStringLiteral("BEGIN IMMEDIATE"))) {
            setLastError(migrate.lastError().text());
            QSqlQuery restore(m_db); restore.exec(QStringLiteral("PRAGMA foreign_keys=ON"));
            return false;
        }

        bool migrated = migrate.exec(QStringLiteral("DROP TABLE IF EXISTS sessions_morixtrem_legacy_096"));
        if (migrated)
            migrated = migrate.exec(QStringLiteral("ALTER TABLE sessions RENAME TO sessions_morixtrem_legacy_096"));

        const QString createNew = QStringLiteral(
            "CREATE TABLE sessions ("
            " id INTEGER PRIMARY KEY AUTOINCREMENT,"
            " name TEXT NOT NULL,"
            " kind TEXT NOT NULL,"
            " host TEXT NOT NULL,"
            " user_name TEXT NOT NULL DEFAULT '',"
            " port INTEGER NOT NULL,"
            " domain_name TEXT NOT NULL DEFAULT '',"
            " rdp_width INTEGER NOT NULL DEFAULT 1440,"
            " rdp_height INTEGER NOT NULL DEFAULT 900,"
            " rdp_scale INTEGER NOT NULL DEFAULT 100,"
            " fullscreen INTEGER NOT NULL DEFAULT 0,"
            " ignore_certificate INTEGER NOT NULL DEFAULT 0,"
            " folder_id INTEGER REFERENCES session_folders(id) ON DELETE SET NULL,"
            " security_profile TEXT NOT NULL DEFAULT 'modern',"
            " key_file TEXT NOT NULL DEFAULT '',"
            " ftp_tls INTEGER NOT NULL DEFAULT 1,"
            " ftp_passive INTEGER NOT NULL DEFAULT 1,"
            " overwrite_existing INTEGER NOT NULL DEFAULT 1,"
            " max_parallel INTEGER NOT NULL DEFAULT 4,"
            " credential_saved INTEGER NOT NULL DEFAULT 0,"
            " last_used_at TEXT,"
            " created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,"
            " updated_at TEXT"
            ")");
        if (migrated)
            migrated = migrate.exec(createNew);
        if (migrated) {
            migrated = migrate.exec(QStringLiteral(
                "INSERT INTO sessions(id,name,kind,host,user_name,port,domain_name,rdp_width,rdp_height,rdp_scale,fullscreen,ignore_certificate,"
                "folder_id,security_profile,key_file,ftp_tls,ftp_passive,overwrite_existing,max_parallel,credential_saved,last_used_at,created_at,updated_at) "
                "SELECT id,name,kind,host,user_name,port,domain_name,rdp_width,rdp_height,rdp_scale,fullscreen,ignore_certificate,"
                "folder_id,security_profile,key_file,ftp_tls,ftp_passive,overwrite_existing,max_parallel,credential_saved,last_used_at,created_at,updated_at "
                "FROM sessions_morixtrem_legacy_096"));
        }
        if (migrated)
            migrated = migrate.exec(QStringLiteral("DROP TABLE sessions_morixtrem_legacy_096"));
        if (migrated)
            migrated = migrate.exec(QStringLiteral("PRAGMA user_version=906"));
        if (migrated)
            migrated = migrate.exec(QStringLiteral("COMMIT"));

        if (!migrated) {
            const QString error = migrate.lastError().text();
            QSqlQuery rollback(m_db); rollback.exec(QStringLiteral("ROLLBACK"));
            QSqlQuery restore(m_db); restore.exec(QStringLiteral("PRAGMA foreign_keys=ON"));
            setLastError(error.isEmpty() ? QStringLiteral("Unable to upgrade the sessions database schema.") : error);
            return false;
        }

        QSqlQuery restore(m_db);
        restore.exec(QStringLiteral("PRAGMA foreign_keys=ON"));
        restore.finish();

        // Verify that the old protocol CHECK is actually gone before allowing a
        // save. This turns silent migration failures into a clear actionable error.
        QSqlQuery verify(m_db);
        verify.prepare(QStringLiteral("SELECT sql FROM sqlite_master WHERE type='table' AND name='sessions'"));
        if (!verify.exec() || !verify.next()) {
            setLastError(QStringLiteral("The sessions database was upgraded but could not be verified."));
            return false;
        }
        const QString verifiedSql = verify.value(0).toString().simplified().toLower();
        verify.finish();
        if (verifiedSql.contains(QStringLiteral("check")) && verifiedSql.contains(QStringLiteral("kind"))) {
            setLastError(QStringLiteral("The legacy session protocol constraint is still present after migration."));
            return false;
        }
    }

    q.exec(QStringLiteral("UPDATE sessions SET updated_at=COALESCE(updated_at, created_at, CURRENT_TIMESTAMP) WHERE updated_at IS NULL OR updated_at=''"));
    q.exec(QStringLiteral("CREATE INDEX IF NOT EXISTS idx_sessions_folder ON sessions(folder_id)"));
    q.exec(QStringLiteral("CREATE INDEX IF NOT EXISTS idx_sessions_last_used ON sessions(last_used_at)"));
    return true;
}

bool SessionStore::ensureColumn(const QString &table, const QString &column, const QString &definition)
{
    QSqlQuery info(m_db);
    if (!info.exec(QStringLiteral("PRAGMA table_info(%1)").arg(table))) {
        setLastError(info.lastError().text());
        return false;
    }
    while (info.next()) {
        if (info.value(1).toString() == column)
            return true;
    }
    QSqlQuery alter(m_db);
    if (!alter.exec(QStringLiteral("ALTER TABLE %1 ADD COLUMN %2 %3").arg(table, column, definition))) {
        // SQLite rejects non-constant defaults in ALTER TABLE on some versions.
        if (column == QStringLiteral("updated_at")) {
            QSqlQuery fallback(m_db);
            if (fallback.exec(QStringLiteral("ALTER TABLE sessions ADD COLUMN updated_at TEXT")))
                return true;
        }
        setLastError(alter.lastError().text());
        return false;
    }
    return true;
}

bool SessionStore::validHost(const QString &host) const
{
    if (host.isEmpty() || host.size() > 253 || host.startsWith('-') || host.contains(QRegularExpression(QStringLiteral("[\\s\\r\\n]"))))
        return false;
    static const QRegularExpression rx(QStringLiteral("^[A-Za-z0-9._:\\[\\]-]+$"));
    return rx.match(host).hasMatch();
}

bool SessionStore::validUser(const QString &user) const
{
    if (user.isEmpty())
        return true;
    static const QRegularExpression rx(QStringLiteral("^[A-Za-z0-9._+-]{1,128}$"));
    return rx.match(user).hasMatch();
}

QString SessionStore::normalizedSecurityProfile(const QString &profile) const
{
    const QString p = profile.toLower().trimmed();
    if (p == QStringLiteral("compatible") || p == QStringLiteral("legacy"))
        return p;
    return QStringLiteral("modern");
}

void SessionStore::rebuildNodes(const QVector<SessionFolder> &folders, const QVector<SavedSession> &sessions)
{
    m_nodes.clear();
    for (const auto &s : sessions) {
        if (s.folderId == 0) {
            SessionNode n;
            n.sessionData = s;
            n.depth = 0;
            m_nodes.push_back(std::move(n));
        }
    }

    for (const auto &folder : folders) {
        int count = 0;
        for (const auto &s : sessions)
            if (s.folderId == folder.id)
                ++count;

        SessionNode fn;
        fn.folder = true;
        fn.folderData = folder;
        fn.depth = 0;
        fn.childCount = count;
        m_nodes.push_back(fn);

        if (!m_expandedFolders.contains(folder.id))
            continue;
        for (const auto &s : sessions) {
            if (s.folderId != folder.id)
                continue;
            SessionNode sn;
            sn.sessionData = s;
            sn.depth = 1;
            m_nodes.push_back(std::move(sn));
        }
    }
}

void SessionStore::setLastError(const QString &error)
{
    if (m_lastError == error)
        return;
    m_lastError = error;
    emit lastErrorChanged();
}
