#include "backend.h"

#include <QColor>
#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFontDatabase>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QRegularExpression>
#include <QSaveFile>
#include <QSettings>
#include <QStandardPaths>
#include <QTextStream>
#include <QDateTime>

#include <algorithm>
#include <iterator>
#include <utility>

namespace {

// The user's own text size, multiplied onto the desktop's text scale.
// Browser-sized steps, with a wider range for small and large displays.
constexpr qreal textZoomSteps[] = {0.5, 0.67, 0.75, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0};
constexpr int textZoomStepCount = int(std::size(textZoomSteps));
constexpr int historyLimit = 2000;

const QString textZoomSetting = QStringLiteral("text/zoom");
const QString testFontSetting = QStringLiteral("test/font");

// Noto ships a separate family per script, which buries every other font in
// the picker. Offer only the core Latin families; the rest still serve as
// fallbacks for whatever scripts a test contains.
const QStringList keptNotoFamilies = {QStringLiteral("Noto Sans"),
                                      QStringLiteral("Noto Sans Mono"),
                                      QStringLiteral("Noto Serif")};

// Fontconfig's generic aliases just point at another listed family.
const QStringList genericFontAliases = {QStringLiteral("Monospace"), QStringLiteral("Mono"),
                                        QStringLiteral("Sans Serif"), QStringLiteral("Sans"),
                                        QStringLiteral("Serif"), QStringLiteral("System-ui")};

// Symbol fonts often claim Latin coverage because they map their glyphs onto
// ASCII, so they can only be told apart by name. D050000L is URW's Dingbats.
const QRegularExpression symbolFontName(
    QStringLiteral("symbol|dingbat|emoji|icon|awesome|^D050000L$"),
    QRegularExpression::CaseInsensitiveOption);

// A shade of `from` carried part of the way towards `to`.
QColor blend(const QColor &from, const QColor &to, qreal amount) {
    return QColor::fromRgbF(from.redF() + (to.redF() - from.redF()) * amount,
                            from.greenF() + (to.greenF() - from.greenF()) * amount,
                            from.blueF() + (to.blueF() - from.blueF()) * amount);
}

QString configKeyFor(const QVariantMap &result) {
    return QStringLiteral("%1:%2:p%3:n%4")
        .arg(result.value(QStringLiteral("mode")).toString())
        .arg(result.value(QStringLiteral("amount")).toInt())
        .arg(result.value(QStringLiteral("punctuation")).toBool() ? 1 : 0)
        .arg(result.value(QStringLiteral("numbers")).toBool() ? 1 : 0);
}

}

Backend::Backend(QObject *parent) : QObject(parent) {
    // A settings file truncated by a crash reads back as an empty value, and
    // both that and a NaN would clamp to the smallest size rather than fall
    // back to the default.
    bool zoomOk = false;
    const qreal storedZoom = QSettings().value(textZoomSetting, 1.0).toDouble(&zoomOk);
    m_textZoom = zoomOk && storedZoom > 0 ? qBound(textZoomSteps[0], storedZoom,
                                                   textZoomSteps[textZoomStepCount - 1])
                                          : 1.0;

    const QString savedFont = QSettings().value(testFontSetting).toString();
    m_testFont = !savedFont.isEmpty() && QFontDatabase::hasFamily(savedFont)
        ? savedFont
        : defaultTestFont();

    m_statusTimer.setSingleShot(true);
    m_statusTimer.setInterval(2500);
    connect(&m_statusTimer, &QTimer::timeout, this, [this]() { setStatus(QString()); });

    loadOmarchyTheme();
    watchOmarchyTheme();
    // Switching themes touches several watched paths in a row, and the theme
    // folder can be briefly missing, so reload once the burst has settled.
    m_themeReloadTimer.setSingleShot(true);
    m_themeReloadTimer.setInterval(100);
    connect(&m_themeReloadTimer, &QTimer::timeout, this, [this]() {
        loadOmarchyTheme();
        watchOmarchyTheme();
    });
    connect(&m_themeWatcher, &QFileSystemWatcher::fileChanged, &m_themeReloadTimer,
            qOverload<>(&QTimer::start));
    connect(&m_themeWatcher, &QFileSystemWatcher::directoryChanged, &m_themeReloadTimer,
            qOverload<>(&QTimer::start));
}

void Backend::setDarkMode(bool darkMode) {
    m_systemDarkMode = darkMode;
    loadOmarchyTheme();
}

void Backend::setDesktopTextScale(qreal textScale) {
    if (qFuzzyCompare(m_desktopTextScale, textScale))
        return;

    m_desktopTextScale = textScale;
    emit textScaleChanged();
}

void Backend::setStatus(const QString &status) {
    if (m_status == status)
        return;

    m_status = status;
    emit statusChanged();
    if (!m_status.isEmpty())
        m_statusTimer.start();
}

void Backend::increaseTextSize() {
    setTextZoom(steppedTextZoom(1));
}

void Backend::decreaseTextSize() {
    setTextZoom(steppedTextZoom(-1));
}

void Backend::resetTextSize() {
    setTextZoom(1.0);
}

// The neighbouring rung, starting from whichever rung the current zoom sits
// closest to; the ends of the ladder hold.
qreal Backend::steppedTextZoom(int direction) const {
    int closest = 0;
    for (int step = 1; step < textZoomStepCount; ++step) {
        if (qAbs(textZoomSteps[step] - m_textZoom) < qAbs(textZoomSteps[closest] - m_textZoom))
            closest = step;
    }

    return textZoomSteps[qBound(0, closest + direction, textZoomStepCount - 1)];
}

void Backend::setTextZoom(qreal zoom) {
    // Report the size even when the ladder has run out, so a keypress that
    // changes nothing still says why.
    setStatus(QStringLiteral("Text size %1%").arg(qRound(zoom * 100)));
    if (qFuzzyCompare(m_textZoom, zoom))
        return;

    m_textZoom = zoom;
    QSettings().setValue(textZoomSetting, zoom);
    emit textScaleChanged();
}

void Backend::newWindow() {
    // A typing test has no document to hand over, so a new window is just
    // another copy of the app.
    QProcess::startDetached(QCoreApplication::applicationFilePath(), {});
}

QVariant Backend::setting(const QString &key, const QVariant &fallback) const {
    return QSettings().value(QStringLiteral("test/") + key, fallback);
}

void Backend::setSetting(const QString &key, const QVariant &value) {
    QSettings().setValue(QStringLiteral("test/") + key, value);
}

QString Backend::defaultTestFont() {
    return QStringLiteral("IBM Plex Mono");
}

void Backend::setTestFont(const QString &family) {
    if (family.isEmpty() || family == m_testFont)
        return;

    m_testFont = family;
    QSettings().setValue(testFontSetting, family);
    emit testFontChanged();
}

QStringList Backend::availableFonts() const {
    // Leave out icon, emoji, and other symbol fonts, along with anything that
    // cannot set the Latin text the test is written in.
    QStringList families;
    for (const QString &family : QFontDatabase::families(QFontDatabase::Latin)) {
        if (QFontDatabase::isPrivateFamily(family)
                || QFontDatabase::writingSystems(family).contains(QFontDatabase::Symbol))
            continue;
        families.append(family);
    }
    return selectableFontFamilies(families);
}

QStringList Backend::selectableFontFamilies(const QStringList &families) {
    QStringList selectable;
    static const QRegularExpression foundrySuffix(QStringLiteral("\\s*\\[[^\\]]*\\]$"));
    for (QString family : families) {
        // The same family from two foundries is listed as "Name [Foundry]".
        family.remove(foundrySuffix);
        if (family.startsWith(QStringLiteral("Noto ")) && !keptNotoFamilies.contains(family))
            continue;
        if (genericFontAliases.contains(family, Qt::CaseInsensitive)
                || family.contains(symbolFontName))
            continue;
        if (family == defaultTestFont() || selectable.contains(family, Qt::CaseInsensitive))
            continue;
        selectable.append(family);
    }
    std::sort(selectable.begin(), selectable.end(), [](const QString &a, const QString &b) {
        return a.compare(b, Qt::CaseInsensitive) < 0;
    });
    selectable.prepend(defaultTestFont());
    return selectable;
}

QString Backend::historyPath() const {
    const QString directory = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    QDir().mkpath(directory);
    return QDir(directory).filePath(QStringLiteral("history.json"));
}

QVariantList Backend::loadHistory() const {
    QFile file(historyPath());
    if (!file.open(QIODevice::ReadOnly))
        return {};

    // A history cut short by a crash is not worth stopping for: start over.
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll());
    return document.isArray() ? document.array().toVariantList() : QVariantList();
}

bool Backend::saveHistory(const QVariantList &history) const {
    QSaveFile file(historyPath());
    if (!file.open(QIODevice::WriteOnly))
        return false;

    file.write(QJsonDocument(QJsonArray::fromVariantList(history)).toJson(QJsonDocument::Compact));
    return file.commit();
}

QVariantMap Backend::recordResult(const QVariantMap &result) {
    QVariantList history = loadHistory();
    const QString key = configKeyFor(result);
    const double wpm = result.value(QStringLiteral("wpm")).toDouble();

    double previousBest = 0;
    for (const QVariant &entry : std::as_const(history)) {
        const QVariantMap map = entry.toMap();
        if (configKeyFor(map) == key)
            previousBest = qMax(previousBest, map.value(QStringLiteral("wpm")).toDouble());
    }

    // The graph is for the results screen; keeping every second of every test
    // would only grow the file.
    QVariantMap stored = result;
    stored.remove(QStringLiteral("samples"));
    stored.insert(QStringLiteral("timestamp"), QDateTime::currentSecsSinceEpoch());
    history.append(stored);
    while (history.size() > historyLimit)
        history.removeFirst();

    if (!saveHistory(history))
        setStatus(QStringLiteral("Could not save the result"));

    return {{QStringLiteral("previousBest"), previousBest},
            {QStringLiteral("personalBest"), previousBest > 0 && wpm > previousBest},
            {QStringLiteral("best"), qMax(previousBest, wpm)}};
}

double Backend::personalBest(const QString &configKey) const {
    double best = 0;
    for (const QVariant &entry : loadHistory()) {
        const QVariantMap map = entry.toMap();
        if (configKeyFor(map) == configKey)
            best = qMax(best, map.value(QStringLiteral("wpm")).toDouble());
    }
    return best;
}

QVariantList Backend::recentResults(int limit) const {
    const QVariantList history = loadHistory();
    QVariantList recent;
    for (int index = history.size() - 1; index >= 0 && recent.size() < limit; --index) {
        QVariantMap map = history.at(index).toMap();
        map.insert(QStringLiteral("date"),
                   QDateTime::fromSecsSinceEpoch(map.value(QStringLiteral("timestamp")).toLongLong())
                       .toString(QStringLiteral("yyyy-MM-dd HH:mm")));
        recent.append(map);
    }
    return recent;
}

QVariantMap Backend::historySummary() const {
    const QVariantList history = loadHistory();
    double total = 0;
    double best = 0;
    for (const QVariant &entry : history) {
        const double wpm = entry.toMap().value(QStringLiteral("wpm")).toDouble();
        total += wpm;
        best = qMax(best, wpm);
    }
    return {{QStringLiteral("count"), history.size()},
            {QStringLiteral("average"), history.isEmpty() ? 0.0 : total / history.size()},
            {QStringLiteral("best"), best}};
}

void Backend::clearHistory() {
    QFile::remove(historyPath());
    setStatus(QStringLiteral("History cleared"));
}

QVariantMap Backend::windowGeometry() const {
    QSettings settings;
    return {{QStringLiteral("x"), settings.value(QStringLiteral("window/x"), -1)},
            {QStringLiteral("y"), settings.value(QStringLiteral("window/y"), -1)},
            {QStringLiteral("width"), settings.value(QStringLiteral("window/width"), 1280)},
            {QStringLiteral("height"), settings.value(QStringLiteral("window/height"), 820)},
            {QStringLiteral("maximized"), settings.value(QStringLiteral("window/maximized"), false)}};
}

void Backend::saveWindowGeometry(int x, int y, int width, int height, bool maximized) {
    QSettings settings;
    if (!maximized) {
        settings.setValue(QStringLiteral("window/x"), x);
        settings.setValue(QStringLiteral("window/y"), y);
        settings.setValue(QStringLiteral("window/width"), width);
        settings.setValue(QStringLiteral("window/height"), height);
    }
    settings.setValue(QStringLiteral("window/maximized"), maximized);
}

// A quoted TOML value ends at its closing quote; whatever trails it is an inline comment.
QString Backend::tomlValue(const QString &text) {
    const QString value = text.trimmed();
    if (value.isEmpty())
        return value;

    const QChar quote = value.front();
    if (quote != QLatin1Char('"') && quote != QLatin1Char('\''))
        return value;

    const int close = value.indexOf(quote, 1);
    return close < 0 ? value : value.mid(1, close - 1);
}

void Backend::loadOmarchyTheme() {
    const QString colorsPath = QDir::homePath()
        + QStringLiteral("/.local/state/omarchy/current/theme/colors.toml");
    QString themeMode;
    QString background;
    QString foreground;
    QString accent;
    QString selection;
    QString selectionBackground;
    QString selectionForeground;
    QString brightForeground;
    QString lighterBackground;
    QString red;
    QFile file(colorsPath);
    if (file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        QTextStream in(&file);
        while (!in.atEnd()) {
            const QString line = in.readLine().trimmed();
            if (line.isEmpty() || line.startsWith(QLatin1Char('#')))
                continue;

            const int equals = line.indexOf(QLatin1Char('='));
            if (equals < 0)
                continue;

            const QString key = line.left(equals).trimmed();
            const QString value = tomlValue(line.mid(equals + 1));

            if (key == QStringLiteral("mode"))
                themeMode = value;
            else if (key == QStringLiteral("background"))
                background = value;
            else if (key == QStringLiteral("foreground"))
                foreground = value;
            else if (key == QStringLiteral("accent"))
                accent = value;
            else if (key == QStringLiteral("selection"))
                selection = value;
            else if (key == QStringLiteral("selection_background"))
                selectionBackground = value;
            else if (key == QStringLiteral("selection_foreground"))
                selectionForeground = value;
            else if (key == QStringLiteral("bright_foreground"))
                brightForeground = value;
            else if (key == QStringLiteral("lighter_background"))
                lighterBackground = value;
            else if (key == QStringLiteral("color1"))
                red = value;
        }
    }

    const bool wasDark = m_darkMode;
    const QStringList previousColors{m_themeBackground, m_themeForeground, m_themeAccent,
                                     m_themeSelection, m_themeSelectionForeground,
                                     m_themeMuted, m_themeError, m_themePanel};

    bool themeIsDark = m_systemDarkMode;
    if (themeMode == QStringLiteral("dark")) {
        themeIsDark = true;
    } else if (themeMode == QStringLiteral("light")) {
        themeIsDark = false;
    } else {
        const QColor parsedBackground(background);
        if (parsedBackground.isValid()) {
            const double luminance = 0.299 * parsedBackground.redF()
                + 0.587 * parsedBackground.greenF() + 0.114 * parsedBackground.blueF();
            themeIsDark = luminance < 0.5;
        }
    }
    m_darkMode = themeIsDark;

    // The defaults follow the mode the theme resolved to, so a colour we cannot
    // read costs that one colour rather than the contrast of the whole window.
    m_themeBackground = m_darkMode ? QStringLiteral("#101010") : QStringLiteral("#ffffff");
    m_themeForeground = m_darkMode ? QStringLiteral("#eeeeee") : QStringLiteral("#222324");
    m_themeAccent = m_darkMode ? QStringLiteral("#5584aa") : QStringLiteral("#2077b2");
    m_themeSelection = m_darkMode ? QStringLiteral("#186a9a") : QStringLiteral("#2077b2");
    m_themeError = m_darkMode ? QStringLiteral("#ca4754") : QStringLiteral("#c0392b");

    // An unparseable colour reaches QML as black, so keep the default instead.
    // Later calls win, so each fallback is applied before what it falls back from.
    const auto applyColor = [](QString &target, const QString &value) {
        if (QColor(value).isValid())
            target = value;
    };
    applyColor(m_themeBackground, background);
    applyColor(m_themeForeground, foreground);
    applyColor(m_themeAccent, accent);
    applyColor(m_themeSelection, selectionBackground);
    applyColor(m_themeSelection, selection);
    applyColor(m_themeError, red);
    m_themeSelectionForeground = m_themeForeground;
    applyColor(m_themeSelectionForeground, brightForeground);
    applyColor(m_themeSelectionForeground, selectionForeground);

    // The letters still to type sit between the page and the text, in whatever
    // theme is loaded, so they stay readable without competing with what has
    // been typed.
    const QColor page(m_themeBackground);
    const QColor text(m_themeForeground);
    m_themeMuted = blend(page, text, 0.42).name();

    // Omarchy themes name a lighter background for panels, so use the shade
    // the theme chose. Not every theme sets the key, and a few set it to the
    // page background, which would leave a panel with no edge at all: mix a
    // shade of the page towards the text for those.
    const QColor lighter(lighterBackground);
    m_themePanel = (lighter.isValid() && lighter != page
                        ? lighter
                        : blend(page, text, 0.06)).name();

    if (m_darkMode != wasDark)
        emit darkModeChanged();
    const QStringList colors{m_themeBackground, m_themeForeground, m_themeAccent,
                             m_themeSelection, m_themeSelectionForeground,
                             m_themeMuted, m_themeError, m_themePanel};
    if (colors != previousColors)
        emit themeColorsChanged();
}

void Backend::watchOmarchyTheme() {
    const QStringList watched = m_themeWatcher.files() + m_themeWatcher.directories();
    if (!watched.isEmpty())
        m_themeWatcher.removePaths(watched);

    const QString currentDir = QDir::homePath()
        + QStringLiteral("/.local/state/omarchy/current");
    const QString themeDir = currentDir + QStringLiteral("/theme");
    const QString colorsPath = themeDir + QStringLiteral("/colors.toml");

    if (QDir(currentDir).exists())
        m_themeWatcher.addPath(currentDir);
    if (QDir(themeDir).exists())
        m_themeWatcher.addPath(themeDir);
    if (QFile::exists(colorsPath))
        m_themeWatcher.addPath(colorsPath);
}
