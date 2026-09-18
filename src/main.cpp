#include "connectionmanager.h"
#include "sessionmodel.h"

#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>

int main(int argc, char *argv[])
{
    QGuiApplication::setOrganizationName(QStringLiteral("MoriXterm"));
    QGuiApplication::setOrganizationDomain(QStringLiteral("morixterm.local"));
    QGuiApplication::setApplicationName(QStringLiteral("MoriXterm"));
    QGuiApplication::setApplicationVersion(QStringLiteral("0.2.0"));

    QGuiApplication app(argc, argv);
    QQuickStyle::setStyle(QStringLiteral("Fusion"));

    SessionModel sessionModel;
    ConnectionManager connectionManager;
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("sessionModel"), &sessionModel);
    engine.rootContext()->setContextProperty(QStringLiteral("connectionManager"), &connectionManager);

    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed,
                     &app, [] { QCoreApplication::exit(EXIT_FAILURE); }, Qt::QueuedConnection);
    engine.loadFromModule(QStringLiteral("MoriXterm"), QStringLiteral("Main"));
    return app.exec();
}
