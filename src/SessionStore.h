#pragma once

#include <QAbstractListModel>
#include <QSet>
#include <QSqlDatabase>
#include <QVariantList>

class CredentialStore;

struct SavedSession
{
    qint64 id = 0;
    QString name;
    QString kind;
    QString host;
    QString user;
    int port = 22;
    QString domain;
    int width = 1440;
    int height = 900;
    int scale = 125;
    bool fullscreen = false;
    bool ignoreCertificate = false;
    qint64 folderId = 0;
    QString securityProfile = QStringLiteral("modern");
    QString keyFile;
    bool credentialSaved = false;
    bool ftpTls = true;
    bool ftpPassive = true;
    bool overwriteExisting = true;
    int maxParallel = 4;
    QString lastUsedAt;
};

struct SessionFolder
{
    qint64 id = 0;
    QString name;
};

struct SessionNode
{
    bool folder = false;
    SessionFolder folderData;
    SavedSession sessionData;
    int depth = 0;
    int childCount = 0;
};

class SessionStore : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(QString databasePath READ databasePath CONSTANT)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)

public:
    enum Role {
        IsFolderRole = Qt::UserRole + 1,
        ItemIdRole,
        SessionIdRole,
        FolderIdRole,
        NameRole,
        KindRole,
        HostRole,
        UserRole,
        PortRole,
        DomainRole,
        WidthRole,
        HeightRole,
        ScaleRole,
        FullscreenRole,
        IgnoreCertificateRole,
        SecurityProfileRole,
        KeyFileRole,
        CredentialSavedRole,
        DepthRole,
        ExpandedRole,
        ChildCountRole,
        FtpTlsRole,
        FtpPassiveRole,
        OverwriteExistingRole,
        MaxParallelRole,
        LastUsedAtRole
    };
    Q_ENUM(Role)

    explicit SessionStore(CredentialStore *credentialStore, QObject *parent = nullptr);
    ~SessionStore() override;

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    QString databasePath() const { return m_databasePath; }
    QString lastError() const { return m_lastError; }

    Q_INVOKABLE qint64 saveSession(qint64 sessionId,
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
                                   bool ftpTls = true,
                                   bool ftpPassive = true,
                                   bool overwriteExisting = true,
                                   int maxParallel = 4,
                                   int scale = 125);
    Q_INVOKABLE bool removeSessionById(qint64 sessionId);
    Q_INVOKABLE bool createFolder(const QString &name);
    Q_INVOKABLE bool renameFolder(qint64 folderId, const QString &name);
    Q_INVOKABLE bool deleteFolder(qint64 folderId);
    Q_INVOKABLE bool moveSessionToFolder(qint64 sessionId, qint64 folderId);
    Q_INVOKABLE void toggleFolder(qint64 folderId);
    Q_INVOKABLE QVariantList folderOptions() const;
    Q_INVOKABLE QVariantList recentSessions(int limit = 6) const;
    Q_INVOKABLE QString passwordForSession(qint64 sessionId) const;
    Q_INVOKABLE void markUsed(qint64 sessionId);
    Q_INVOKABLE bool setIgnoreCertificate(qint64 sessionId, bool enabled);
    Q_INVOKABLE void reload();

signals:
    void lastErrorChanged();
    void foldersChanged();

private:
    bool openDatabase();
    bool ensureSchema();
    bool ensureColumn(const QString &table, const QString &column, const QString &definition);
    bool validHost(const QString &host) const;
    bool validUser(const QString &user) const;
    QString normalizedSecurityProfile(const QString &profile) const;
    void rebuildNodes(const QVector<SessionFolder> &folders, const QVector<SavedSession> &sessions);
    void setLastError(const QString &error);

    QVector<SessionNode> m_nodes;
    QVector<SessionFolder> m_folders;
    QVector<SavedSession> m_sessions;
    QSet<qint64> m_expandedFolders;
    QString m_databasePath;
    QString m_lastError;
    QString m_connectionName;
    QSqlDatabase m_db;
    CredentialStore *m_credentialStore = nullptr;
};
