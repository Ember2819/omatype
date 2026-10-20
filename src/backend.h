#pragma once

#include <QObject>
#include <QFileSystemWatcher>
#include <QFont>
#include <QString>
#include <QStringList>
#include <QTimer>
#include <QVariant>
#include <QVariantList>
#include <QVariantMap>

class Backend : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool darkMode READ darkMode WRITE setDarkMode NOTIFY darkModeChanged)
    Q_PROPERTY(qreal textScale READ textScale NOTIFY textScaleChanged)
    Q_PROPERTY(QString status READ status NOTIFY statusChanged)
    Q_PROPERTY(QString themeBackground READ themeBackground NOTIFY themeColorsChanged)
    Q_PROPERTY(QString themeForeground READ themeForeground NOTIFY themeColorsChanged)
    Q_PROPERTY(QString themeAccent READ themeAccent NOTIFY themeColorsChanged)
    Q_PROPERTY(QString themeSelection READ themeSelection NOTIFY themeColorsChanged)
    Q_PROPERTY(QString themeSelectionForeground READ themeSelectionForeground NOTIFY themeColorsChanged)
    Q_PROPERTY(QString themeMuted READ themeMuted NOTIFY themeColorsChanged)
    Q_PROPERTY(QString themeError READ themeError NOTIFY themeColorsChanged)
    Q_PROPERTY(QString themePanel READ themePanel NOTIFY themeColorsChanged)
    Q_PROPERTY(QString testFont READ testFont WRITE setTestFont NOTIFY testFontChanged)
    Q_PROPERTY(QStringList availableFonts READ availableFonts CONSTANT)

public:
    explicit Backend(QObject *parent = nullptr);

    bool darkMode() const { return m_darkMode; }
    void setDarkMode(bool darkMode);
    // What the desktop asks for, times what the user asked for on top of it.
    qreal textScale() const { return m_desktopTextScale * m_textZoom; }
    void setDesktopTextScale(qreal textScale);
    QString status() const { return m_status; }
    QString themeBackground() const { return m_themeBackground; }
    QString themeForeground() const { return m_themeForeground; }
    QString themeAccent() const { return m_themeAccent; }
    QString themeSelection() const { return m_themeSelection; }
    QString themeSelectionForeground() const { return m_themeSelectionForeground; }
    QString themeMuted() const { return m_themeMuted; }
    QString themeError() const { return m_themeError; }
    QString themePanel() const { return m_themePanel; }
    QString testFont() const { return m_testFont; }
    void setTestFont(const QString &family);
    QStringList availableFonts() const;

    static QString defaultTestFont();
    static QStringList selectableFontFamilies(const QStringList &families);
    static QString tomlValue(const QString &text);

    Q_INVOKABLE void increaseTextSize();
    Q_INVOKABLE void decreaseTextSize();
    Q_INVOKABLE void resetTextSize();
    Q_INVOKABLE void newWindow();
    Q_INVOKABLE QVariant setting(const QString &key, const QVariant &fallback) const;
    Q_INVOKABLE void setSetting(const QString &key, const QVariant &value);
    // Stores a finished test and says whether it beat the best before it.
    Q_INVOKABLE QVariantMap recordResult(const QVariantMap &result);
    Q_INVOKABLE double personalBest(const QString &configKey) const;
    Q_INVOKABLE QVariantList recentResults(int limit) const;
    Q_INVOKABLE QVariantMap historySummary() const;
    Q_INVOKABLE void clearHistory();
    Q_INVOKABLE QVariantMap windowGeometry() const;
    Q_INVOKABLE void saveWindowGeometry(int x, int y, int width, int height, bool maximized);

signals:
    void darkModeChanged();
    void textScaleChanged();
    void statusChanged();
    void themeColorsChanged();
    void testFontChanged();

private:
    void setStatus(const QString &status);
    qreal steppedTextZoom(int direction) const;
    void setTextZoom(qreal zoom);
    QVariantList loadHistory() const;
    bool saveHistory(const QVariantList &history) const;
    QString historyPath() const;
    void loadOmarchyTheme();
    void watchOmarchyTheme();

    bool m_darkMode = true;
    // The desktop's light/dark setting, used when the Omarchy theme names none.
    bool m_systemDarkMode = true;
    qreal m_desktopTextScale = 1.0;
    qreal m_textZoom = 1.0;
    QString m_status;
    QTimer m_statusTimer;

    QString m_themeBackground;
    QString m_themeForeground;
    QString m_themeAccent;
    QString m_themeSelection;
    QString m_themeSelectionForeground;
    QString m_themeMuted;
    QString m_themeError;
    QString m_themePanel;
    QString m_testFont;
    QFileSystemWatcher m_themeWatcher;
    QTimer m_themeReloadTimer;
};
