#pragma once

#include "PtyProcess.h"

#include <QColor>
#include <QFont>
#include <QPoint>
#include <QQuickPaintedItem>
#include <QStringConverter>
#include <QVector>

class QPainter;
class QKeyEvent;
class QMouseEvent;
class QWheelEvent;
class QTimer;

class TerminalItem : public QQuickPaintedItem
{
    Q_OBJECT
    Q_PROPERTY(QString fontFamily READ fontFamily WRITE setFontFamily NOTIFY fontFamilyChanged)
    Q_PROPERTY(qreal fontSize READ fontSize WRITE setFontSize NOTIFY fontSizeChanged)
    Q_PROPERTY(QColor backgroundColor READ backgroundColor WRITE setBackgroundColor NOTIFY backgroundColorChanged)
    Q_PROPERTY(QString themeName READ themeName WRITE setThemeName NOTIFY themeNameChanged)
    Q_PROPERTY(bool running READ running NOTIFY runningChanged)
    Q_PROPERTY(QString statusText READ statusText NOTIFY statusTextChanged)

public:
    explicit TerminalItem(QQuickItem *parent = nullptr);

    void paint(QPainter *painter) override;

    QString fontFamily() const { return m_font.family(); }
    void setFontFamily(const QString &family);

    qreal fontSize() const { return m_font.pointSizeF(); }
    void setFontSize(qreal size);

    QColor backgroundColor() const { return m_background; }
    void setBackgroundColor(const QColor &color);

    QString themeName() const { return m_themeName; }
    void setThemeName(const QString &name);

    bool running() const { return m_pty.isRunning(); }
    QString statusText() const { return m_statusText; }

    Q_INVOKABLE void startLocalShell();
    Q_INVOKABLE void startCommand(const QString &program, const QStringList &arguments = {});
    Q_INVOKABLE void startCommandWithPassword(const QString &program, const QStringList &arguments, const QString &password);
    Q_INVOKABLE void sendText(const QString &text);
    Q_INVOKABLE void clearTerminal();
    Q_INVOKABLE void copySelection();
    Q_INVOKABLE void pasteClipboard();
    Q_INVOKABLE void selectAll();
    Q_INVOKABLE void clearSelection();
    Q_INVOKABLE QStringList availableThemes() const;
    Q_INVOKABLE void scrollToBottom();
    Q_INVOKABLE void scrollPageUp();
    Q_INVOKABLE void scrollPageDown();

signals:
    void fontFamilyChanged();
    void fontSizeChanged();
    void backgroundColorChanged();
    void themeNameChanged();
    void runningChanged();
    void statusTextChanged();
    void titleChanged(const QString &title);
    void errorOccurred(const QString &message);
    void sshHostKeyChanged(const QString &fingerprint);
    void sshHostKeyVerificationFailed(const QString &message);

protected:
    void keyPressEvent(QKeyEvent *event) override;
    void mousePressEvent(QMouseEvent *event) override;
    void mouseMoveEvent(QMouseEvent *event) override;
    void mouseReleaseEvent(QMouseEvent *event) override;
    void wheelEvent(QWheelEvent *event) override;
    void geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) override;

private:
    struct Cell {
        QChar ch = QLatin1Char(' ');
        QColor fg;
        QColor bg = Qt::transparent;
        bool bold = false;
    };

    enum class ParseState { Normal, Escape, Csi, Osc, OscEscape };

    void recalcMetrics();
    void resizeScreen();
    void resetScreen();
    void processBytes(const QByteArray &data);
    void processText(const QString &text);
    void processCsi(char finalByte, const QByteArray &params);
    void applySgr(const QList<int> &params);
    void putChar(QChar ch);
    void lineFeed();
    void scrollUp(int lines = 1);
    void ensureCursorVisible();
    void eraseInDisplay(int mode);
    void eraseInLine(int mode);
    QColor indexedColor(int index) const;
    void initializeTheme(const QString &name);
    QString promptCommandForShell(const QString &shell) const;
    void applyPromptTheme();
    QPoint cellFromPosition(const QPointF &pos) const;
    QString selectedText() const;
    bool isSelected(int row, int col) const;
    QByteArray keySequence(QKeyEvent *event) const;
    void updateStatus(const QString &status);
    void inspectProcessDiagnostics(const QByteArray &data);
    void scheduleRepaint();
    void flushRepaint();
    void markDirtyRow(int row);
    void markAllDirty();
    void scrollViewport(int lines);
    int maxScrollOffset() const;
    int visibleGlobalRow(int viewportRow) const;
    const QVector<Cell> *lineAtGlobalRow(int globalRow) const;
    void trimScrollback();
    void updateScrollFromScrollbarPosition(qreal y);

    PtyProcess m_pty;
    QFont m_font;
    QColor m_background = QColor("#1e1f20");
    QColor m_defaultForeground = QColor("#dedede");
    QColor m_cursorColor = QColor("#38d996");
    QColor m_selectionColor = QColor("#164f3a");
    QVector<QColor> m_palette;
    QString m_themeName = QStringLiteral("MoriXterm");
    QString m_promptShellName;
    bool m_promptPending = false;
    bool m_promptApplied = false;
    int m_promptActivityGeneration = 0;
    QVector<QVector<Cell>> m_scrollback;
    QVector<QVector<Cell>> m_screen;
    QVector<QVector<Cell>> m_savedScreen;
    int m_rows = 24;
    int m_cols = 80;
    int m_row = 0;
    int m_col = 0;
    int m_savedRow = 0;
    int m_savedCol = 0;
    qreal m_cellWidth = 9.0;
    qreal m_cellHeight = 18.0;
    qreal m_ascent = 14.0;
    Cell m_current;
    ParseState m_state = ParseState::Normal;
    QByteArray m_csi;
    QByteArray m_osc;
    QStringDecoder m_utf8Decoder { QStringConverter::Utf8 };
    bool m_cursorVisible = true;
    bool m_altScreen = false;
    bool m_selecting = false;
    QPoint m_selectionStart {-1, -1};
    QPoint m_selectionEnd {-1, -1};
    QString m_statusText = QStringLiteral("Ready");
    QByteArray m_diagnosticBuffer;
    qsizetype m_diagnosticBytesSeen = 0;
    bool m_diagnosticsEnabled = true;
    bool m_hostKeyChangeSignaled = false;
    bool m_hostKeyFailureSignaled = false;
    QTimer *m_repaintTimer = nullptr;
    int m_dirtyFirstRow = -1;
    int m_dirtyLastRow = -1;
    bool m_fullRepaintPending = true;
    int m_scrollOffset = 0;
    int m_maxScrollbackLines = 10000;
    bool m_scrollbarDragging = false;
};
