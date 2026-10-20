#include <QFont>
#include <QFontDatabase>
#include <QApplication>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQmlError>
#include <QQuickStyle>
#include <QUrl>
#include <QFile>

#include "backend.h"
#include "cli.h"
#include "systemtheme.h"

#define OMATYPE_VERSION "0.1.0"

int main(int argc, char *argv[]) {
    // Answered before the application exists, so they need no display.
    if (const std::optional<int> exitCode =
            Cli::handleArguments(argc, argv, QStringLiteral(OMATYPE_VERSION)))
        return *exitCode;

    // Omarchy asks Qt for GTK 3 dialogs, which run inside this process, and a
    // long-standing GTK 3 file chooser assertion aborts the whole app. Omatype
    // opens no file dialogs, but keeps the same platform theme as Omawrite so
    // the two look alike.
    if (qgetenv("QT_QPA_PLATFORMTHEME") == "gtk3")
        qputenv("QT_QPA_PLATFORMTHEME", "xdgdesktopportal");

    QApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("omatype"));
    app.setApplicationVersion(QStringLiteral(OMATYPE_VERSION));
    app.setDesktopFileName(QStringLiteral("omatype"));
    app.setWindowIcon(QIcon::fromTheme(QStringLiteral("omatype")));

    QFontDatabase::addApplicationFont(QStringLiteral(":/fonts/IBMPlexMono-Regular.ttf"));
    QFontDatabase::addApplicationFont(QStringLiteral(":/fonts/IBMPlexMono-Italic.ttf"));
    QFontDatabase::addApplicationFont(QStringLiteral(":/fonts/IBMPlexMono-Bold.ttf"));
    QFontDatabase::addApplicationFont(QStringLiteral(":/fonts/IBMPlexMono-BoldItalic.ttf"));
    app.setOrganizationName(QStringLiteral("Omacom"));
    app.setOrganizationDomain(QStringLiteral("omacom.io"));

    QQuickStyle::setStyle(QStringLiteral("Material"));

    Backend backend(&app);
    SystemTheme systemTheme(&app);
    backend.setDarkMode(systemTheme.darkMode());
    QObject::connect(&systemTheme, &SystemTheme::darkModeChanged, &backend,
                     &Backend::setDarkMode);

    // Carry the text scale into the default font, so the chrome that inherits
    // it (dialog titles, buttons) grows along with the typing area.
    const QFont interfaceFont(QStringLiteral("IBM Plex Mono"));
    const qreal basePointSize = interfaceFont.pointSizeF() > 0
        ? interfaceFont.pointSizeF()
        : app.font().pointSizeF();
    const auto applyInterfaceFont = [&app, interfaceFont, basePointSize](qreal textScale) {
        QFont scaled = interfaceFont;
        scaled.setPointSizeF(basePointSize * textScale);
        app.setFont(scaled);
    };

    // The desktop sets the baseline; the backend folds the user's own text
    // size into it and reports the total.
    backend.setDesktopTextScale(systemTheme.textScale());
    applyInterfaceFont(backend.textScale());
    QObject::connect(&systemTheme, &SystemTheme::textScaleChanged, &backend,
                     &Backend::setDesktopTextScale);
    QObject::connect(&backend, &Backend::textScaleChanged, &app,
                     [&backend, applyInterfaceFont]() {
        applyInterfaceFont(backend.textScale());
    });

    QQmlApplicationEngine engine;
    QObject::connect(&engine, &QQmlApplicationEngine::warnings, &app,
                     [](const QList<QQmlError> &warnings) {
        for (const QQmlError &warning : warnings)
            qWarning().noquote() << warning.toString();
    });
    engine.rootContext()->setContextProperty(QStringLiteral("backend"), &backend);

    engine.load(QUrl(QStringLiteral("qrc:/Main.qml")));
    if (engine.rootObjects().isEmpty()) {
        qCritical() << "Could not load the Omatype interface; resource available:"
                    << QFile::exists(QStringLiteral(":/Main.qml"));
        return -1;
    }

    return app.exec();
}
