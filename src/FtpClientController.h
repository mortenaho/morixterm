#pragma once

#include "FileEntryModel.h"

#include <QObject>
#include <QProcess>
#include <QVariantList>
#include <QUrl>

class FtpClientController : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QAbstractItemModel *entries READ entries CONSTANT)
    Q_PROPERTY(QString currentPath READ currentPath NOTIFY currentPathChanged)
    Q_PROPERTY(QString statusText READ statusText NOTIFY statusTextChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(QString protocol READ protocol NOTIFY sessionChanged)
    Q_PROPERTY(QString sessionLabel READ sessionLabel NOTIFY sessionChanged)
    Q_PROPERTY(QVariantList transfers READ transfers NOTIFY transfersChanged)
    Q_PROPERTY(int activeTransferCount READ activeTransferCount NOTIFY transfersChanged)
    Q_PROPERTY(int overallProgress READ overallProgress NOTIFY transfersChanged)
    Q_PROPERTY(int maxParallel READ maxParallel WRITE setMaxParallel NOTIFY maxParallelChanged)
    Q_PROPERTY(bool overwriteExisting READ overwriteExisting WRITE setOverwriteExisting NOTIFY overwriteExistingChanged)
    Q_PROPERTY(bool tlsVerificationBypassed READ tlsVerificationBypassed NOTIFY tlsSecurityChanged)

public:
    explicit FtpClientController(QObject *parent = nullptr);
    ~FtpClientController() override;

    QAbstractItemModel *entries() { return &m_entries; }
    QString currentPath() const { return m_currentPath; }
    QString statusText() const { return m_statusText; }
    bool busy() const { return m_busy; }
    QString protocol() const { return m_protocol; }
    QString sessionLabel() const { return m_sessionLabel; }
    QVariantList transfers() const;
    int activeTransferCount() const;
    int overallProgress() const;
    int maxParallel() const { return m_maxParallel; }
    bool overwriteExisting() const { return m_overwriteExisting; }
    bool tlsVerificationBypassed() const { return m_ignoreTlsCertificate; }

    Q_INVOKABLE void configure(const QString &protocol,
                               const QString &host,
                               const QString &user,
                               int port,
                               const QString &password,
                               const QString &keyFile,
                               bool ftpTls,
                               bool passive,
                               int maxParallel,
                               bool overwriteExisting,
                               bool ignoreTlsCertificate = false);
    Q_INVOKABLE void refresh();
    Q_INVOKABLE void goUp();
    Q_INVOKABLE void goToPath(const QString &path);
    Q_INVOKABLE void openEntry(int row);
    Q_INVOKABLE QString entryPath(int row) const;
    Q_INVOKABLE QString entryName(int row) const;
    Q_INVOKABLE bool entryIsDirectory(int row) const;

    Q_INVOKABLE void createFolder(const QString &name);
    Q_INVOKABLE void renameEntry(int row, const QString &newName);
    Q_INVOKABLE void deleteEntry(int row);
    Q_INVOKABLE void chmodEntry(int row, const QString &mode);

    Q_INVOKABLE void uploadPaths(const QVariantList &localPaths, bool overwrite);
    Q_INVOKABLE void downloadRows(const QVariantList &rows, const QUrl &localFolder, bool overwrite);
    Q_INVOKABLE void cancelTransfer(int jobId);
    Q_INVOKABLE void cancelAllTransfers();
    Q_INVOKABLE void clearFinishedTransfers();
    Q_INVOKABLE void trustTlsForCurrentSession();

    void setMaxParallel(int value);
    void setOverwriteExisting(bool value);

signals:
    void currentPathChanged();
    void statusTextChanged();
    void busyChanged();
    void sessionChanged();
    void transfersChanged();
    void maxParallelChanged();
    void overwriteExistingChanged();
    void tlsSecurityChanged();
    void tlsCertificateError(const QString &message);
    void operationFinished(bool success, const QString &message);

private:
    struct TransferJob {
        int id = 0;
        QString direction;
        QString label;
        QString localPath;
        QString remotePath;
        QString state = QStringLiteral("Queued");
        QString detail;
        int progress = 0;
        bool overwrite = true;
        QProcess *process = nullptr;
        QByteArray progressBuffer;
    };

    QString curlProgram() const;
    QString remoteUrl(const QString &path, bool directory = false) const;
    QByteArray secretConfig() const;
    static QByteArray escapeCurlConfig(const QString &value);
    QString joinRemote(const QString &base, const QString &name) const;
    QString normalizeRemotePath(const QString &path) const;
    void setStatus(const QString &status);
    void setBusy(bool busy);
    void runListCommand(bool ftpMlsd);
    void parseListing(const QByteArray &output, bool mlsd);
    QVector<FileEntry> parseMlsd(const QByteArray &output) const;
    QVector<FileEntry> parseLongListing(const QByteArray &output) const;
    void runRemoteCommand(const QStringList &quoteCommands, const QString &successMessage);
    QStringList commonCurlArgs() const;
    void writeSecretConfig(QProcess *process) const;
    bool isTlsCertificateError(int exitCode, const QByteArray &stderrData) const;
    QString friendlyTlsError(const QByteArray &stderrData) const;

    void enqueueFileUpload(const QString &localFile, const QString &remoteFile, bool overwrite);
    void enqueueDirectoryUpload(const QString &localDirectory, const QString &remoteDirectory, bool overwrite);
    void enqueueFileDownload(const QString &remoteFile, const QString &localFile, bool overwrite);
    void startQueuedTransfers();
    void startTransfer(TransferJob *job);
    void finishTransfer(TransferJob *job, bool success, const QString &message);
    void parseCurlProgress(TransferJob *job, const QByteArray &chunk);
    TransferJob *findJob(int id) const;
    void pruneJobs();

    FileEntryModel m_entries;
    QProcess *m_commandProcess = nullptr;
    bool m_busy = false;
    QString m_protocol = QStringLiteral("ftp");
    QString m_host;
    QString m_user;
    int m_port = 21;
    QString m_password;
    QString m_keyFile;
    bool m_ftpTls = true;
    bool m_ignoreTlsCertificate = false;
    bool m_tlsPromptIssued = false;
    bool m_passive = true;
    int m_maxParallel = 4;
    bool m_overwriteExisting = true;
    QString m_currentPath = QStringLiteral("/");
    QString m_statusText = QStringLiteral("Ready");
    QString m_sessionLabel;
    QList<TransferJob *> m_jobs;
    int m_nextJobId = 1;
};
