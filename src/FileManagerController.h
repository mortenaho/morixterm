#pragma once

#include "FileEntryModel.h"

#include <QObject>
#include <QProcess>
#include <QTimer>
#include <QUrl>
#include <functional>

class FileManagerController : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QAbstractItemModel *entries READ entries CONSTANT)
    Q_PROPERTY(QString currentPath READ currentPath NOTIFY currentPathChanged)
    Q_PROPERTY(QString statusText READ statusText NOTIFY statusTextChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(bool remote READ remote NOTIFY sessionChanged)
    Q_PROPERTY(QString sessionLabel READ sessionLabel NOTIFY sessionChanged)
    Q_PROPERTY(bool hasClipboardEntry READ hasClipboardEntry NOTIFY clipboardChanged)
    Q_PROPERTY(bool clipboardCut READ clipboardCut NOTIFY clipboardChanged)
    Q_PROPERTY(QString operationName READ operationName NOTIFY operationChanged)
    Q_PROPERTY(QString operationDetail READ operationDetail NOTIFY operationChanged)
    Q_PROPERTY(int operationProgress READ operationProgress NOTIFY operationChanged)

public:
    explicit FileManagerController(QObject *parent = nullptr);

    QAbstractItemModel *entries() { return &m_entries; }
    QString currentPath() const { return m_currentPath; }
    QString statusText() const { return m_statusText; }
    bool busy() const { return m_busy; }
    bool remote() const { return m_remote; }
    QString sessionLabel() const { return m_sessionLabel; }
    bool hasClipboardEntry() const { return !m_clipboardPath.isEmpty(); }
    bool clipboardCut() const { return m_clipboardCut; }
    QString operationName() const { return m_operationName; }
    QString operationDetail() const { return m_operationDetail; }
    int operationProgress() const { return m_operationProgress; }

    Q_INVOKABLE void configureLocal();
    Q_INVOKABLE void configureSsh(const QString &host, const QString &user, int port,
                                  const QString &controlPath = QString(),
                                  const QString &securityProfile = QStringLiteral("modern"),
                                  const QString &keyFile = QString());
    Q_INVOKABLE void refresh();
    Q_INVOKABLE void goUp();
    Q_INVOKABLE void openEntry(int row);
    Q_INVOKABLE void goToPath(const QString &path);
    Q_INVOKABLE QString entryPath(int row) const;
    Q_INVOKABLE QString entryName(int row) const;
    Q_INVOKABLE bool entryIsDirectory(int row) const;

    Q_INVOKABLE void upload(const QUrl &localFileUrl);
    Q_INVOKABLE void downloadEntry(int row, const QUrl &localFolderUrl);
    Q_INVOKABLE void createFolder(const QString &name);
    Q_INVOKABLE void renameEntry(int row, const QString &newName);
    Q_INVOKABLE void chmodEntry(int row, const QString &mode);
    Q_INVOKABLE void chownEntry(int row, const QString &ownerAndGroup);
    Q_INVOKABLE void deleteEntry(int row);
    Q_INVOKABLE void copyEntry(int row);
    Q_INVOKABLE void cutEntry(int row);
    Q_INVOKABLE void pasteEntry();
    Q_INVOKABLE QString defaultArchiveName(int row) const;
    Q_INVOKABLE QString defaultExtractFolder(int row) const;
    Q_INVOKABLE void compressEntry(int row, const QString &archiveName);
    Q_INVOKABLE void extractZipEntry(int row, const QString &destinationFolder);

signals:
    void currentPathChanged();
    void statusTextChanged();
    void busyChanged();
    void sessionChanged();
    void clipboardChanged();
    void operationFinished(bool success, const QString &message);
    void operationChanged();

private:
    using Completion = std::function<void(int, QProcess::ExitStatus, const QByteArray &, const QByteArray &)>;

    void setBusy(bool busy);
    void setStatus(const QString &status);
    QString target() const;
    QString shellQuote(const QString &value) const;
    QString pathJoin(const QString &base, const QString &name) const;
    QString remoteCdTarget() const;
    QStringList sshBaseArgs() const;
    QStringList scpBaseArgs() const;
    void runProcess(const QString &program, const QStringList &arguments, Completion completion,
                    const QByteArray &stdinData = {}, const QString &workingDirectory = {});
    void refreshLocal();
    void refreshRemote();
    void runFileOperation(const QString &localProgram, const QStringList &localArgs,
                          const QString &remoteCommand, const QString &successMessage);
    void finishAndRefresh(bool success, const QString &message);
    void clearClipboardEntry();
    void beginOperation(const QString &name, int progress = -1, const QString &detail = QString());
    void setOperationProgress(int progress, const QString &detail = QString());
    void parseOperationProgress(const QByteArray &chunk);

    FileEntryModel m_entries;
    QProcess *m_process = nullptr;
    bool m_busy = false;
    bool m_remote = false;
    QString m_host;
    QString m_user;
    int m_port = 22;
    QString m_controlPath;
    QString m_securityProfile = QStringLiteral("modern");
    QString m_keyFile;
    QString m_currentPath;
    QString m_sessionLabel = QStringLiteral("Local machine");
    QString m_statusText = QStringLiteral("Ready");
    QString m_operationName;
    QString m_operationDetail;
    int m_operationProgress = -1;
    bool m_parseProgress = false;
    int m_progressTotal = 0;
    int m_progressDone = 0;
    QByteArray m_progressBuffer;
    QByteArray m_liveStdout;
    QTimer m_authRetryTimer;
    int m_authRetryRemaining = 0;

    QString m_clipboardPath;
    QString m_clipboardName;
    bool m_clipboardCut = false;
    bool m_clipboardRemote = false;
    QString m_clipboardSessionKey;
};
