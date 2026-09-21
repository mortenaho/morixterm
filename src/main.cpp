#include "AppLockManager.h"
#include "CredentialStore.h"
#include "FileManagerController.h"
#include "FtpClientController.h"
#include "RdpSessionController.h"
#include "SecurityHardening.h"
#include "SessionStore.h"
#include "SshSecurity.h"
#include "TerminalItem.h"
#include "Version.h"

#include <QCoreApplication>
#include <QGuiApplication>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QSysInfo>
#include <QUrl>
#include <qqml.h>

int main(int argc, char *argv[])
{
    SecurityHardening::apply();

    QGuiApplication app(argc, argv);
    QCoreApplication::setApplicationName(QStringLiteral("MoriXterm"));
    QCoreApplication::setApplicationVersion(QString::fromLatin1(MORIXTERM_APP_VERSION));
    QCoreApplication::setOrganizationName(QStringLiteral("mortenaho"));
    QCoreApplication::setOrganizationDomain(QStringLiteral("github.com/mortenaho"));
    QGuiApplication::setDesktopFileName(QStringLiteral("morixtrem"));
    app.setWindowIcon(QIcon(QStringLiteral(":/assets/morixtrem-app.png")));

    QQuickStyle::setStyle(QStringLiteral("Basic"));
    qmlRegisterType<TerminalItem>("MoriXterm.Terminal", 1, 0, "TerminalView");
    qmlRegisterType<FileManagerController>("MoriXterm.FileManager", 1, 0, "FileManagerController");
    qmlRegisterType<FtpClientController>("MoriXterm.Ftp", 1, 0, "FtpClientController");
    qmlRegisterType<RdpSessionController>("MoriXterm.Rdp", 1, 0, "RdpSessionController");

    CredentialStore credentialStore;
    AppLockManager appLock;
    SessionStore sessionStore(&credentialStore);
    SshSecurityController sshSecurity;

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("appLock"), &appLock);
    engine.rootContext()->setContextProperty(QStringLiteral("credentialStore"), &credentialStore);
    engine.rootContext()->setContextProperty(QStringLiteral("sessionStore"), &sessionStore);
    engine.rootContext()->setContextProperty(QStringLiteral("sshSecurity"), &sshSecurity);
    engine.rootContext()->setContextProperty(QStringLiteral("appVersion"), QCoreApplication::applicationVersion());
    engine.rootContext()->setContextProperty(QStringLiteral("qtVersion"), QString::fromLatin1(qVersion()));
    engine.rootContext()->setContextProperty(QStringLiteral("platformName"), QSysInfo::prettyProductName());
    engine.rootContext()->setContextProperty(QStringLiteral("cpuArchitecture"), QSysInfo::currentCpuArchitecture());
    engine.rootContext()->setContextProperty(QStringLiteral("repositoryUrl"), QStringLiteral("https://github.com/mortenaho/morixterm"));

    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed,
                     &app, [] { QCoreApplication::exit(-1); }, Qt::QueuedConnection);
    engine.load(QUrl(QStringLiteral("qrc:/qml/Main.qml")));

    return app.exec();
}
