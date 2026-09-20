#include "TerminalItem.h"

#include <QClipboard>
#include <QFontMetricsF>
#include <QGuiApplication>
#include <QKeyEvent>
#include <QMouseEvent>
#include <QPainter>
#include <QProcessEnvironment>
#include <QRegularExpression>
#include <QFileInfo>
#include <QTimer>
#include <QWheelEvent>

#include <algorithm>
#include <array>
#include <cmath>

namespace {
struct ThemeColors {
    QString name;
    QColor background;
    QColor foreground;
    QColor cursor;
    QColor selection;
    std::array<QColor, 16> palette;
};

ThemeColors themeColors(const QString &requested)
{
    const QString key = requested.trimmed().toLower();
    ThemeColors theme;
    if (key == QStringLiteral("dracula")) {
        theme = {QStringLiteral("Dracula"), QColor("#282a36"), QColor("#f8f8f2"), QColor("#f8f8f2"), QColor("#44475a"), {
            QColor("#282a36"), QColor("#ff5555"), QColor("#50fa7b"), QColor("#f1fa8c"),
            QColor("#bd93f9"), QColor("#ff79c6"), QColor("#8be9fd"), QColor("#f8f8f2"),
            QColor("#6272a4"), QColor("#ff6e6e"), QColor("#69ff94"), QColor("#ffffa5"),
            QColor("#d6acff"), QColor("#ff92df"), QColor("#a4ffff"), QColor("#ffffff")}};
    } else if (key == QStringLiteral("nord")) {
        theme = {QStringLiteral("Nord"), QColor("#2e3440"), QColor("#d8dee9"), QColor("#88c0d0"), QColor("#434c5e"), {
            QColor("#3b4252"), QColor("#bf616a"), QColor("#a3be8c"), QColor("#ebcb8b"),
            QColor("#81a1c1"), QColor("#b48ead"), QColor("#88c0d0"), QColor("#e5e9f0"),
            QColor("#4c566a"), QColor("#d08770"), QColor("#8fbcbb"), QColor("#eacb8a"),
            QColor("#5e81ac"), QColor("#b48ead"), QColor("#8fbcbb"), QColor("#eceff4")}};
    } else if (key == QStringLiteral("solarized dark")) {
        theme = {QStringLiteral("Solarized Dark"), QColor("#002b36"), QColor("#839496"), QColor("#93a1a1"), QColor("#073642"), {
            QColor("#073642"), QColor("#dc322f"), QColor("#859900"), QColor("#b58900"),
            QColor("#268bd2"), QColor("#d33682"), QColor("#2aa198"), QColor("#eee8d5"),
            QColor("#002b36"), QColor("#cb4b16"), QColor("#586e75"), QColor("#657b83"),
            QColor("#839496"), QColor("#6c71c4"), QColor("#93a1a1"), QColor("#fdf6e3")}};
    } else if (key == QStringLiteral("monokai")) {
        theme = {QStringLiteral("Monokai"), QColor("#272822"), QColor("#f8f8f2"), QColor("#f8f8f0"), QColor("#49483e"), {
            QColor("#272822"), QColor("#f92672"), QColor("#a6e22e"), QColor("#e6db74"),
            QColor("#66d9ef"), QColor("#ae81ff"), QColor("#a1efe4"), QColor("#f8f8f2"),
            QColor("#75715e"), QColor("#f92672"), QColor("#a6e22e"), QColor("#e6db74"),
            QColor("#66d9ef"), QColor("#ae81ff"), QColor("#a1efe4"), QColor("#f9f8f5")}};
    } else if (key == QStringLiteral("light")) {
        theme = {QStringLiteral("Light"), QColor("#f6f8fa"), QColor("#24292f"), QColor("#0969da"), QColor("#d0d7de"), {
            QColor("#f6f8fa"), QColor("#cf222e"), QColor("#116329"), QColor("#4d2d00"),
            QColor("#0969da"), QColor("#8250df"), QColor("#1b7c83"), QColor("#24292f"),
            QColor("#57606a"), QColor("#a40e26"), QColor("#1a7f37"), QColor("#633c01"),
            QColor("#218bff"), QColor("#a475f9"), QColor("#3192aa"), QColor("#6e7781")}};
    } else {
        theme = {QStringLiteral("MoriXterm"), QColor("#07110d"), QColor("#d5e4dc"), QColor("#63f5a6"), QColor("#164f3a"), {
            QColor("#1b2721"), QColor("#e06c75"), QColor("#62d196"), QColor("#e5c07b"),
            QColor("#61afef"), QColor("#c678dd"), QColor("#56b6c2"), QColor("#d5e4dc"),
            QColor("#50635a"), QColor("#ff7a85"), QColor("#7fffb2"), QColor("#ffd68a"),
            QColor("#84c7ff"), QColor("#e4a2ff"), QColor("#7ce8f2"), QColor("#ffffff")}};
    }
    return theme;
}
}

TerminalItem::TerminalItem(QQuickItem *parent)
    : QQuickPaintedItem(parent)
{
    setFlag(ItemHasContents, true);
    setOpaquePainting(true);
    setAcceptedMouseButtons(Qt::LeftButton | Qt::RightButton);
    setAcceptHoverEvents(true);
    setFocus(true);

    m_font.setFamily(QStringLiteral("JetBrainsMono Nerd Font"));
    m_font.setStyleHint(QFont::Monospace);
    m_font.setFixedPitch(true);
    m_font.setKerning(false);
    m_font.setPointSizeF(11.5);
    initializeTheme(QStringLiteral("MoriXterm"));

    m_repaintTimer = new QTimer(this);
    m_repaintTimer->setSingleShot(true);
    // Zero-delay single-shot coalesces a burst of PTY output into one frame without
    // adding an artificial 8ms input latency to every echoed keystroke.
    m_repaintTimer->setInterval(0);
    m_repaintTimer->setTimerType(Qt::PreciseTimer);
    connect(m_repaintTimer, &QTimer::timeout, this, &TerminalItem::flushRepaint);

    connect(&m_pty, &PtyProcess::readyRead, this, [this](const QByteArray &data) {
        inspectProcessDiagnostics(data);
        const int oldCursorRow = m_row;
        processBytes(data);
        markDirtyRow(oldCursorRow);
        markDirtyRow(m_row);
        scheduleRepaint();

        // SSH presents the remote shell only after authentication/MOTD output.
        // Wait for a quiet, non-authentication response before changing PS1 so
        // the command can never be mistaken for a password or host-key answer.
        if (m_promptPending && !m_promptApplied) {
            const QByteArray lower = data.toLower();
            const bool isInteractivePrompt = !lower.contains("password")
                && !lower.contains("passphrase")
                && !lower.contains("yes/no")
                && !lower.contains("fingerprint")
                && !lower.contains("continue connecting");
            if (isInteractivePrompt) {
                const int generation = ++m_promptActivityGeneration;
                QTimer::singleShot(900, this, [this, generation] {
                    if (m_promptPending && !m_promptApplied
                        && generation == m_promptActivityGeneration) {
                        applyPromptTheme();
                        m_promptPending = false;
                    }
                });
            }
        }
    });
    connect(&m_pty, &PtyProcess::exited, this, [this](int code) {
        updateStatus(QStringLiteral("Process exited (%1)").arg(code));
        emit runningChanged();
    });
    connect(&m_pty, &PtyProcess::errorOccurred, this, [this](const QString &message) {
        updateStatus(message);
        emit errorOccurred(message);
    });

    recalcMetrics();
    resetScreen();
}

void TerminalItem::paint(QPainter *painter)
{
    const QRectF clip = painter->hasClipping() ? painter->clipBoundingRect() : boundingRect();
    painter->fillRect(clip.intersected(boundingRect()), m_background);
    painter->setRenderHint(QPainter::TextAntialiasing, true);

    QFont normalFont = m_font;
    normalFont.setBold(false);
    QFont boldFont = m_font;
    boldFont.setBold(true);

    const int visibleRows = m_rows;
    const int firstPaintRow = std::clamp(static_cast<int>(std::floor(clip.top() / m_cellHeight)), 0, std::max(0, visibleRows - 1));
    const int lastPaintRow = std::clamp(static_cast<int>(std::floor(std::max<qreal>(0.0, clip.bottom() - 0.01) / m_cellHeight)),
                                        firstPaintRow, std::max(firstPaintRow, visibleRows - 1));
    for (int r = firstPaintRow; r <= lastPaintRow && r < visibleRows; ++r) {
        const int globalRow = visibleGlobalRow(r);
        const QVector<Cell> *linePtr = lineAtGlobalRow(globalRow);
        if (!linePtr)
            continue;
        const auto &line = *linePtr;
        const int visibleCols = std::min(m_cols, static_cast<int>(line.size()));

        // Paint cell backgrounds/selection first. Text is drawn in style runs below,
        // which cuts the number of drawText()/setFont() calls dramatically.
        for (int c = 0; c < visibleCols; ++c) {
            const Cell &cell = line[c];
            const bool selected = (m_selectionStart.x() >= 0 && m_selectionEnd.x() >= 0) && isSelected(globalRow, c);
            if (cell.bg.alpha() > 0 || selected) {
                const QRectF rect(c * m_cellWidth, r * m_cellHeight,
                                  m_cellWidth + 0.5, m_cellHeight);
                if (cell.bg.alpha() > 0)
                    painter->fillRect(rect, cell.bg);
                if (selected)
                    painter->fillRect(rect, m_selectionColor);
            }
        }

        int textCols = visibleCols;
        while (textCols > 0) {
            const QChar tail = line[textCols - 1].ch;
            if (!tail.isNull() && tail != QLatin1Char(' '))
                break;
            --textCols;
        }

        int runStart = 0;
        while (runStart < textCols) {
            const QColor runColor = line[runStart].fg.isValid() ? line[runStart].fg : m_defaultForeground;
            const bool runBold = line[runStart].bold;
            int runEnd = runStart + 1;
            while (runEnd < textCols &&
                   line[runEnd].fg == runColor &&
                   line[runEnd].bold == runBold) {
                ++runEnd;
            }

            QString text;
            text.reserve(runEnd - runStart);
            bool hasGlyph = false;
            for (int c = runStart; c < runEnd; ++c) {
                const QChar ch = line[c].ch.isNull() ? QLatin1Char(' ') : line[c].ch;
                text.append(ch);
                if (ch != QLatin1Char(' '))
                    hasGlyph = true;
            }

            if (hasGlyph) {
                painter->setFont(runBold ? boldFont : normalFont);
                painter->setPen(runColor);
                painter->drawText(QPointF(runStart * m_cellWidth,
                                          r * m_cellHeight + m_ascent), text);
            }
            runStart = runEnd;
        }
    }

    if (m_cursorVisible && m_scrollOffset == 0 && hasActiveFocus() && m_row >= 0 && m_row < m_rows && m_col >= 0 && m_col < m_cols) {
        const QRectF cursorRect(m_col * m_cellWidth, m_row * m_cellHeight + m_cellHeight - 2,
                                m_cellWidth, 2);
        painter->fillRect(cursorRect, m_cursorColor);
    }

    // Small, unobtrusive scroll indicator. It only appears when history exists.
    // The thumb reaches the bottom when the terminal follows live output and moves
    // upward while the user browses scrollback.
    const int historyLines = static_cast<int>(m_scrollback.size());
    if (!m_altScreen && historyLines > 0 && height() > 24.0) {
        constexpr qreal trackWidth = 5.0;
        constexpr qreal margin = 3.0;
        const qreal trackHeight = std::max<qreal>(1.0, height() - margin * 2.0);
        const qreal totalLines = static_cast<qreal>(historyLines + m_rows);
        const qreal thumbHeight = std::clamp(trackHeight * (static_cast<qreal>(m_rows) / totalLines), 22.0, trackHeight);
        const qreal travel = std::max<qreal>(0.0, trackHeight - thumbHeight);
        const qreal position = historyLines > 0
            ? static_cast<qreal>(historyLines - m_scrollOffset) / static_cast<qreal>(historyLines)
            : 1.0;
        const qreal thumbY = margin + travel * std::clamp(position, 0.0, 1.0);

        painter->fillRect(QRectF(width() - trackWidth - 2.0, margin, trackWidth, trackHeight), QColor(255, 255, 255, 22));
        painter->fillRect(QRectF(width() - trackWidth - 2.0, thumbY, trackWidth, thumbHeight), QColor("#4e9f7d"));
    }
}

void TerminalItem::setFontFamily(const QString &family)
{
    if (family.isEmpty() || m_font.family() == family)
        return;
    m_font.setFamily(family);
    recalcMetrics();
    resizeScreen();
    emit fontFamilyChanged();
    update();
}

void TerminalItem::setFontSize(qreal size)
{
    size = std::clamp(size, 7.0, 32.0);
    if (qFuzzyCompare(m_font.pointSizeF(), size))
        return;
    m_font.setPointSizeF(size);
    recalcMetrics();
    resizeScreen();
    emit fontSizeChanged();
    update();
}

void TerminalItem::setBackgroundColor(const QColor &color)
{
    if (m_background == color)
        return;
    m_background = color;
    emit backgroundColorChanged();
    update();
}

void TerminalItem::setThemeName(const QString &name)
{
    const ThemeColors theme = themeColors(name);
    if (m_themeName == theme.name && m_background == theme.background)
        return;

    const QVector<QColor> oldPalette = m_palette;
    const QColor oldForeground = m_defaultForeground;
    initializeTheme(theme.name);

    const auto remap = [&oldPalette, &theme, &oldForeground](const QColor &color) {
        if (color == oldForeground)
            return theme.foreground;
        for (int i = 0; i < oldPalette.size() && i < 16; ++i) {
            if (color == oldPalette.at(i))
                return theme.palette.at(static_cast<size_t>(i));
        }
        return color;
    };
    for (auto &line : m_screen) {
        for (auto &cell : line) {
            if (cell.fg.isValid()) cell.fg = remap(cell.fg);
            if (cell.bg.isValid()) cell.bg = remap(cell.bg);
        }
    }
    if (m_current.fg.isValid()) m_current.fg = remap(m_current.fg);
    if (m_current.bg.isValid()) m_current.bg = remap(m_current.bg);
    if (!m_promptShellName.isEmpty() && m_pty.isRunning())
        applyPromptTheme();
    emit themeNameChanged();
    emit backgroundColorChanged();
    update();
}

QStringList TerminalItem::availableThemes() const
{
    return {QStringLiteral("MoriXterm"), QStringLiteral("Dracula"), QStringLiteral("Nord"),
            QStringLiteral("Solarized Dark"), QStringLiteral("Monokai"), QStringLiteral("Light")};
}

void TerminalItem::initializeTheme(const QString &name)
{
    const ThemeColors theme = themeColors(name);
    m_themeName = theme.name;
    m_background = theme.background;
    m_defaultForeground = theme.foreground;
    m_cursorColor = theme.cursor;
    m_selectionColor = theme.selection;
    m_palette = QVector<QColor>(theme.palette.begin(), theme.palette.end());
    m_current.fg = m_defaultForeground;
}

QString TerminalItem::promptCommandForShell(const QString &shell) const
{
    const QColor userColor = m_palette.value(2, m_defaultForeground);
    const QColor hostColor = m_palette.value(6, m_defaultForeground);
    const QColor pathColor = m_palette.value(3, m_defaultForeground);
    const QColor symbolColor = m_palette.value(1, m_defaultForeground);
    const QColor separatorColor = m_palette.value(8, m_defaultForeground);

    const auto hex = [](const QColor &color) {
        return color.name(QColor::HexRgb);
    };
    const auto zshColor = [&hex](const QColor &color) {
        return QStringLiteral("%F{") + hex(color) + QStringLiteral("}");
    };

    const QString shellName = QFileInfo(shell).fileName().toLower();
    if (shellName == QStringLiteral("zsh")) {
        return QStringLiteral("PROMPT='")
            + zshColor(userColor) + QStringLiteral("%n")
            + zshColor(separatorColor) + QStringLiteral("@")
            + zshColor(hostColor) + QStringLiteral("%m")
            + zshColor(separatorColor) + QStringLiteral(":")
            + zshColor(pathColor) + QStringLiteral("%~")
            + zshColor(symbolColor) + QStringLiteral("%# ")
            + QStringLiteral("%f'\n");
    }

    const auto ansi = [](const QColor &color) {
        const QColor c = color.isValid() ? color : QColor("#dedede");
        return QStringLiteral("\\e[38;2;")
            + QString::number(c.red()) + QStringLiteral(";")
            + QString::number(c.green()) + QStringLiteral(";")
            + QString::number(c.blue()) + QStringLiteral("m");
    };

    // Bash and POSIX shells understand these prompt escapes. The \[...\]
    // wrappers keep the cursor position correct around non-printing ANSI codes.
    return QStringLiteral("export PS1='")
        + QStringLiteral("\\[") + ansi(userColor) + QStringLiteral("\\]\\u")
        + QStringLiteral("\\[") + ansi(separatorColor) + QStringLiteral("\\]@")
        + QStringLiteral("\\[") + ansi(hostColor) + QStringLiteral("\\]\\h")
        + QStringLiteral("\\[") + ansi(separatorColor) + QStringLiteral("\\]:")
        + QStringLiteral("\\[") + ansi(pathColor) + QStringLiteral("\\]\\w")
        + QStringLiteral("\\[") + ansi(symbolColor) + QStringLiteral("\\]\\$ ")
        + QStringLiteral("\\[\\e[0m\\]'\n");
}

void TerminalItem::applyPromptTheme()
{
    if (m_promptShellName.isEmpty() || !m_pty.isRunning())
        return;
    m_pty.writeData(promptCommandForShell(m_promptShellName).toUtf8());
    m_promptApplied = true;
}

void TerminalItem::startLocalShell()
{
#ifdef Q_OS_WIN
    QString shell = qEnvironmentVariable("COMSPEC");
    if (shell.isEmpty())
        shell = QStringLiteral("cmd.exe");
#else
    QString shell = qEnvironmentVariable("SHELL");
    if (shell.isEmpty())
        shell = QStringLiteral("/bin/bash");
#endif
    m_promptShellName = shell;
    m_promptPending = false;
    m_promptApplied = false;
    startCommand(shell, {});
    QTimer::singleShot(250, this, &TerminalItem::applyPromptTheme);
}

void TerminalItem::startCommand(const QString &program, const QStringList &arguments)
{
    startCommandWithPassword(program, arguments, {});
}

void TerminalItem::startCommandWithPassword(const QString &program, const QStringList &arguments, const QString &password)
{
    resetScreen();
    m_diagnosticBuffer.clear();
    m_diagnosticBytesSeen = 0;
    m_diagnosticsEnabled = true;
    m_hostKeyChangeSignaled = false;
    m_hostKeyFailureSignaled = false;
    m_promptApplied = false;
    m_promptActivityGeneration++;
    if (QFileInfo(program).fileName().toLower() == QStringLiteral("ssh")) {
        m_promptShellName = QStringLiteral("/bin/bash");
        m_promptPending = true;
    }
    updateStatus(QStringLiteral("Starting %1").arg(program));
    if (m_pty.start(program, arguments, password)) {
        m_pty.resize(m_rows, m_cols);
        updateStatus(QStringLiteral("Connected"));
        emit runningChanged();
    }
    forceActiveFocus();
}

void TerminalItem::sendText(const QString &text)
{
    if (m_scrollOffset != 0)
        scrollToBottom();
    m_pty.writeData(text.toUtf8());
}

void TerminalItem::clearTerminal()
{
    resetScreen();
    update();
}

void TerminalItem::copySelection()
{
    const QString text = selectedText();
    if (!text.isEmpty())
        QGuiApplication::clipboard()->setText(text);
}

void TerminalItem::pasteClipboard()
{
    const QString text = QGuiApplication::clipboard()->text();
    if (!text.isEmpty())
        sendText(text);
}

void TerminalItem::selectAll()
{
    if (m_rows <= 0 || m_cols <= 0 || m_screen.isEmpty())
        return;

    const int first = visibleGlobalRow(0);
    const int last = visibleGlobalRow(m_rows - 1);
    m_selectionStart = QPoint(0, first);
    m_selectionEnd = QPoint(m_cols - 1, last);
    update();
}

void TerminalItem::clearSelection()
{
    m_selecting = false;
    m_selectionStart = QPoint(-1, -1);
    m_selectionEnd = QPoint(-1, -1);
    update();
}

void TerminalItem::scrollToBottom()
{
    if (m_scrollOffset == 0)
        return;
    m_scrollOffset = 0;
    clearSelection();
    markAllDirty();
    scheduleRepaint();
}

void TerminalItem::scrollPageUp()
{
    scrollViewport(std::max(1, m_rows - 2));
}

void TerminalItem::scrollPageDown()
{
    scrollViewport(-std::max(1, m_rows - 2));
}

void TerminalItem::keyPressEvent(QKeyEvent *event)
{
    if (event->modifiers() & Qt::ShiftModifier) {
        if (event->key() == Qt::Key_PageUp) {
            scrollPageUp();
            event->accept();
            return;
        }
        if (event->key() == Qt::Key_PageDown) {
            scrollPageDown();
            event->accept();
            return;
        }
        if (event->key() == Qt::Key_Home) {
            scrollViewport(maxScrollOffset());
            event->accept();
            return;
        }
        if (event->key() == Qt::Key_End) {
            scrollToBottom();
            event->accept();
            return;
        }
    }

    if ((event->modifiers() & Qt::ControlModifier) && (event->modifiers() & Qt::ShiftModifier)) {
        if (event->key() == Qt::Key_C) {
            copySelection();
            event->accept();
            return;
        }
        if (event->key() == Qt::Key_V) {
            pasteClipboard();
            event->accept();
            return;
        }
    }

    const QByteArray seq = keySequence(event);
    if (!seq.isEmpty()) {
        if (m_scrollOffset != 0)
            scrollToBottom();
        m_pty.writeData(seq);
        event->accept();
        return;
    }

    QQuickPaintedItem::keyPressEvent(event);
}

void TerminalItem::mousePressEvent(QMouseEvent *event)
{
    forceActiveFocus();
    if (event->button() == Qt::RightButton) {
        pasteClipboard();
        event->accept();
        return;
    }

    if (event->button() == Qt::LeftButton) {
        if (!m_altScreen && !m_scrollback.isEmpty() && event->position().x() >= width() - 14.0) {
            m_scrollbarDragging = true;
            updateScrollFromScrollbarPosition(event->position().y());
            event->accept();
            return;
        }
        m_selecting = true;
        m_selectionStart = cellFromPosition(event->position());
        m_selectionEnd = m_selectionStart;
        update();
        event->accept();
        return;
    }
    QQuickPaintedItem::mousePressEvent(event);
}

void TerminalItem::mouseMoveEvent(QMouseEvent *event)
{
    if (m_scrollbarDragging) {
        updateScrollFromScrollbarPosition(event->position().y());
        event->accept();
        return;
    }
    if (m_selecting) {
        m_selectionEnd = cellFromPosition(event->position());
        update();
        event->accept();
        return;
    }
    QQuickPaintedItem::mouseMoveEvent(event);
}

void TerminalItem::mouseReleaseEvent(QMouseEvent *event)
{
    if (event->button() == Qt::LeftButton && m_scrollbarDragging) {
        updateScrollFromScrollbarPosition(event->position().y());
        m_scrollbarDragging = false;
        event->accept();
        return;
    }
    if (event->button() == Qt::LeftButton && m_selecting) {
        m_selecting = false;
        m_selectionEnd = cellFromPosition(event->position());
        update();
        event->accept();
        return;
    }
    QQuickPaintedItem::mouseReleaseEvent(event);
}

void TerminalItem::wheelEvent(QWheelEvent *event)
{
    // Ctrl + wheel behaves like modern terminal emulators: zoom the terminal
    // font without sending wheel input to the remote shell. Trackpads and mice
    // are both supported, and setFontSize() keeps the range sane.
    if (event->modifiers().testFlag(Qt::ControlModifier)) {
        qreal delta = 0.0;
        if (!event->angleDelta().isNull())
            delta = static_cast<qreal>(event->angleDelta().y()) / 120.0;
        else if (!event->pixelDelta().isNull())
            delta = static_cast<qreal>(event->pixelDelta().y()) / 40.0;

        if (!qFuzzyIsNull(delta)) {
            const qreal step = delta > 0.0 ? 0.75 : -0.75;
            setFontSize(fontSize() + step);
            event->accept();
            return;
        }
    }

    // Most mice report 120 units per notch. Touchpads may only provide pixelDelta,
    // so convert either form to terminal rows and keep scrolling responsive.
    int lines = 0;
    if (!event->pixelDelta().isNull()) {
        const qreal pixels = static_cast<qreal>(event->pixelDelta().y());
        lines = static_cast<int>(std::round(pixels / std::max<qreal>(1.0, m_cellHeight)));
        if (lines == 0 && !qFuzzyIsNull(pixels))
            lines = pixels > 0 ? 1 : -1;
    } else if (!event->angleDelta().isNull()) {
        const int steps = event->angleDelta().y() / 120;
        lines = steps * 3;
        if (lines == 0)
            lines = event->angleDelta().y() > 0 ? 1 : -1;
    }

    if (lines != 0) {
        scrollViewport(lines);
        event->accept();
        return;
    }
    QQuickPaintedItem::wheelEvent(event);
}

void TerminalItem::geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry)
{
    QQuickPaintedItem::geometryChange(newGeometry, oldGeometry);
    if (newGeometry.size() != oldGeometry.size())
        resizeScreen();
}

void TerminalItem::inspectProcessDiagnostics(const QByteArray &data)
{
    // Host-key errors only happen during SSH startup. Do not keep scanning the
    // terminal's entire output forever: doing so made every echoed keystroke pay
    // for repeated QByteArray copies/lower-casing once a shell was interactive.
    if (!m_diagnosticsEnabled || m_hostKeyFailureSignaled || data.isEmpty())
        return;

    m_diagnosticBytesSeen += data.size();
    m_diagnosticBuffer.append(data);
    constexpr qsizetype MaxDiagnosticBytes = 2048;
    if (m_diagnosticBuffer.size() > MaxDiagnosticBytes)
        m_diagnosticBuffer = m_diagnosticBuffer.right(MaxDiagnosticBytes);

    const QByteArray lower = m_diagnosticBuffer.toLower();
    const bool changed = lower.contains("remote host identification has changed") ||
                         (lower.contains("host key for") && lower.contains("has changed")) ||
                         (lower.contains("offending ") && lower.contains(" key in "));

    if (changed && !m_hostKeyChangeSignaled) {
        QString fingerprint;
        const QString text = QString::fromLocal8Bit(m_diagnosticBuffer);
        static const QRegularExpression fingerprintRx(QStringLiteral(R"((SHA256:[A-Za-z0-9+/=]+))"));
        const QRegularExpressionMatch match = fingerprintRx.match(text);
        if (match.hasMatch())
            fingerprint = match.captured(1);
        m_hostKeyChangeSignaled = true;
        m_hostKeyFailureSignaled = true;
        m_diagnosticsEnabled = false;
        emit sshHostKeyChanged(fingerprint);
        return;
    }

    if (lower.contains("host key verification failed")) {
        m_hostKeyFailureSignaled = true;
        m_diagnosticsEnabled = false;
        emit sshHostKeyVerificationFailed(QStringLiteral("SSH host key verification failed."));
        return;
    }

    // By this point an SSH host key would already have been checked. Stop the
    // diagnostic scanner once normal interactive output is clearly flowing.
    constexpr qsizetype StartupDiagnosticBudget = 8 * 1024;
    if (m_diagnosticBytesSeen >= StartupDiagnosticBudget) {
        m_diagnosticsEnabled = false;
        m_diagnosticBuffer.clear();
    }
}

void TerminalItem::scheduleRepaint()
{
    if (!m_repaintTimer)
        return;
    if (!m_repaintTimer->isActive())
        m_repaintTimer->start();
}

void TerminalItem::flushRepaint()
{
    if (m_scrollOffset > 0 || m_fullRepaintPending || m_dirtyFirstRow < 0 || m_dirtyLastRow < 0) {
        update();
    } else {
        const qreal top = std::max<qreal>(0.0, m_dirtyFirstRow * m_cellHeight);
        const qreal bottom = std::min<qreal>(height(), (m_dirtyLastRow + 1) * m_cellHeight);
        // QQuickPaintedItem::update() takes QRect in Qt 6. Convert the
        // floating-point terminal row bounds to an aligned integer repaint rect.
        update(QRectF(0, top, width(),
                      std::max<qreal>(m_cellHeight, bottom - top)).toAlignedRect());
    }
    m_dirtyFirstRow = -1;
    m_dirtyLastRow = -1;
    m_fullRepaintPending = false;
}

void TerminalItem::markDirtyRow(int row)
{
    if (row < 0 || row >= m_rows)
        return;
    if (m_dirtyFirstRow < 0 || row < m_dirtyFirstRow)
        m_dirtyFirstRow = row;
    if (m_dirtyLastRow < 0 || row > m_dirtyLastRow)
        m_dirtyLastRow = row;
}

void TerminalItem::markAllDirty()
{
    m_fullRepaintPending = true;
    m_dirtyFirstRow = 0;
    m_dirtyLastRow = std::max(0, m_rows - 1);
}

void TerminalItem::recalcMetrics()
{
    QFontMetricsF metrics(m_font);
    m_cellWidth = std::max<qreal>(1.0, metrics.horizontalAdvance(QLatin1Char('M')));
    m_cellHeight = std::max<qreal>(1.0, std::ceil(metrics.height() + 2.0));
    m_ascent = metrics.ascent() + 1.0;
}

void TerminalItem::resizeScreen()
{
    const int newCols = std::max(2, static_cast<int>(width() / m_cellWidth));
    const int newRows = std::max(2, static_cast<int>(height() / m_cellHeight));
    if (newCols == m_cols && newRows == m_rows)
        return;

    QVector<QVector<Cell>> resized(newRows, QVector<Cell>(newCols));
    const int copyRows = std::min(newRows, static_cast<int>(m_screen.size()));
    for (int r = 0; r < copyRows; ++r) {
        const int copyCols = std::min(newCols, static_cast<int>(m_screen[r].size()));
        for (int c = 0; c < copyCols; ++c)
            resized[r][c] = m_screen[r][c];
    }

    m_rows = newRows;
    m_cols = newCols;
    m_screen = std::move(resized);
    for (auto &line : m_scrollback)
        line.resize(m_cols);
    m_scrollOffset = std::clamp(m_scrollOffset, 0, maxScrollOffset());
    m_row = std::clamp(m_row, 0, m_rows - 1);
    m_col = std::clamp(m_col, 0, m_cols - 1);
    m_pty.resize(m_rows, m_cols);
    markAllDirty();
    update();
}

void TerminalItem::resetScreen()
{
    m_scrollback.clear();
    m_scrollOffset = 0;
    m_screen = QVector<QVector<Cell>>(m_rows, QVector<Cell>(m_cols));
    m_row = 0;
    m_col = 0;
    m_current = Cell{};
    m_current.fg = m_defaultForeground;
    m_state = ParseState::Normal;
    m_csi.clear();
    m_osc.clear();
    m_selectionStart = {-1, -1};
    m_selectionEnd = {-1, -1};
    markAllDirty();
}

void TerminalItem::processBytes(const QByteArray &data)
{
    qsizetype i = 0;
    while (i < data.size()) {
        const char raw = data.at(i);
        const unsigned char ch = static_cast<unsigned char>(raw);

        switch (m_state) {
        case ParseState::Normal:
            if (ch == 0x1b) {
                m_state = ParseState::Escape;
                ++i;
            } else if (ch == '\r') {
                m_col = 0;
                ++i;
            } else if (ch == '\n') {
                lineFeed();
                ++i;
            } else if (ch == '\b') {
                m_col = std::max(0, m_col - 1);
                ++i;
            } else if (ch == '\t') {
                m_col = std::min(m_cols - 1, ((m_col / 8) + 1) * 8);
                ++i;
            } else if (ch >= 0x20 && ch != 0x7f) {
                // Decode printable bytes in one batch. The old implementation
                // called QStringDecoder once per byte, which was especially
                // noticeable while typing into a remote interactive shell.
                const qsizetype begin = i;
                while (i < data.size()) {
                    const unsigned char next = static_cast<unsigned char>(data.at(i));
                    if (next == 0x1b || next == '\r' || next == '\n' ||
                        next == '\b' || next == '\t' || next < 0x20 || next == 0x7f)
                        break;
                    ++i;
                }
                const QByteArray chunk(data.constData() + begin, i - begin);
                const QString text = m_utf8Decoder(chunk);
                if (!text.isEmpty())
                    processText(text);
            } else {
                ++i;
            }
            break;

        case ParseState::Escape:
            if (ch == '[') {
                m_csi.clear();
                m_state = ParseState::Csi;
            } else if (ch == ']') {
                m_osc.clear();
                m_state = ParseState::Osc;
            } else if (ch == '7') {
                m_savedRow = m_row;
                m_savedCol = m_col;
                m_state = ParseState::Normal;
            } else if (ch == '8') {
                m_row = m_savedRow;
                m_col = m_savedCol;
                ensureCursorVisible();
                m_state = ParseState::Normal;
            } else if (ch == 'c') {
                resetScreen();
                m_state = ParseState::Normal;
            } else {
                m_state = ParseState::Normal;
            }
            ++i;
            break;

        case ParseState::Csi:
            if (ch >= 0x40 && ch <= 0x7e) {
                processCsi(static_cast<char>(ch), m_csi);
                m_csi.clear();
                m_state = ParseState::Normal;
            } else {
                if (m_csi.size() < 4096)
                    m_csi.append(raw);
                else {
                    m_csi.clear();
                    m_state = ParseState::Normal;
                }
            }
            ++i;
            break;

        case ParseState::Osc:
            if (ch == 0x07) {
                const QList<QByteArray> parts = m_osc.split(';');
                if (parts.size() >= 2 && (parts[0] == "0" || parts[0] == "2")) {
                    QString title = QString::fromUtf8(m_osc.mid(m_osc.indexOf(';') + 1)).left(256);
                    title.remove(QRegularExpression(QStringLiteral("[\\x00-\\x1F\\x7F]")));
                    emit titleChanged(title);
                }
                m_osc.clear();
                m_state = ParseState::Normal;
            } else if (ch == 0x1b) {
                m_state = ParseState::OscEscape;
            } else {
                if (m_osc.size() < 4096)
                    m_osc.append(raw);
                else {
                    m_osc.clear();
                    m_state = ParseState::Normal;
                }
            }
            ++i;
            break;

        case ParseState::OscEscape:
            if (ch == '\\') {
                const QList<QByteArray> parts = m_osc.split(';');
                if (parts.size() >= 2 && (parts[0] == "0" || parts[0] == "2")) {
                    QString title = QString::fromUtf8(m_osc.mid(m_osc.indexOf(';') + 1)).left(256);
                    title.remove(QRegularExpression(QStringLiteral("[\\x00-\\x1F\\x7F]")));
                    emit titleChanged(title);
                }
                m_osc.clear();
                m_state = ParseState::Normal;
            } else {
                m_state = ParseState::Osc;
            }
            ++i;
            break;
        }
    }
}

void TerminalItem::processText(const QString &text)
{
    for (QChar ch : text) {
        if (ch == QChar::ReplacementCharacter)
            continue;
        putChar(ch);
    }
}

void TerminalItem::processCsi(char finalByte, const QByteArray &rawParams)
{
    QByteArray params = rawParams;
    const bool isPrivate = params.startsWith('?');
    if (isPrivate)
        params.remove(0, 1);

    QList<int> values;
    if (params.isEmpty()) {
        values << 0;
    } else {
        for (const QByteArray &part : params.split(';'))
            values << (part.isEmpty() ? 0 : part.toInt());
    }

    const auto p = [&values](int index, int defaultValue) {
        if (index >= values.size() || values[index] == 0)
            return defaultValue;
        return values[index];
    };

    switch (finalByte) {
    case 'A': m_row = std::max(0, m_row - p(0, 1)); break;
    case 'B': m_row = std::min(m_rows - 1, m_row + p(0, 1)); break;
    case 'C': m_col = std::min(m_cols - 1, m_col + p(0, 1)); break;
    case 'D': m_col = std::max(0, m_col - p(0, 1)); break;
    case 'E': m_row = std::min(m_rows - 1, m_row + p(0, 1)); m_col = 0; break;
    case 'F': m_row = std::max(0, m_row - p(0, 1)); m_col = 0; break;
    case 'G': m_col = std::clamp(p(0, 1) - 1, 0, m_cols - 1); break;
    case 'H':
    case 'f':
        m_row = std::clamp(p(0, 1) - 1, 0, m_rows - 1);
        m_col = std::clamp(p(1, 1) - 1, 0, m_cols - 1);
        break;
    case 'J': eraseInDisplay(values.value(0, 0)); break;
    case 'K': eraseInLine(values.value(0, 0)); break;
    case 'm': applySgr(values); break;
    case 's': m_savedRow = m_row; m_savedCol = m_col; break;
    case 'u': m_row = m_savedRow; m_col = m_savedCol; ensureCursorVisible(); break;
    case 'd': m_row = std::clamp(p(0, 1) - 1, 0, m_rows - 1); break;
    case 'h':
    case 'l':
        if (isPrivate) {
            const bool enable = finalByte == 'h';
            for (int value : values) {
                if (value == 25)
                    m_cursorVisible = enable;
                if (value == 1049) {
                    if (enable && !m_altScreen) {
                        m_savedScreen = m_screen;
                        m_savedRow = m_row;
                        m_savedCol = m_col;
                        m_altScreen = true;
                        m_scrollOffset = 0;
                        m_screen = QVector<QVector<Cell>>(m_rows, QVector<Cell>(m_cols));
                        m_row = m_col = 0;
                        markAllDirty();
                    } else if (!enable && m_altScreen) {
                        if (!m_savedScreen.isEmpty())
                            m_screen = m_savedScreen;
                        m_row = m_savedRow;
                        m_col = m_savedCol;
                        m_altScreen = false;
                        m_scrollOffset = 0;
                        markAllDirty();
                    }
                }
            }
        }
        break;
    default:
        break;
    }
}

void TerminalItem::applySgr(const QList<int> &params)
{
    QList<int> p = params;
    if (p.isEmpty())
        p << 0;

    for (int i = 0; i < p.size(); ++i) {
        const int code = p[i];
        if (code == 0) {
            m_current = Cell{};
            m_current.fg = m_defaultForeground;
        } else if (code == 1) {
            m_current.bold = true;
        } else if (code == 22) {
            m_current.bold = false;
        } else if (code >= 30 && code <= 37) {
            m_current.fg = indexedColor(code - 30);
        } else if (code >= 90 && code <= 97) {
            m_current.fg = indexedColor(code - 90 + 8);
        } else if (code == 39) {
            m_current.fg = m_defaultForeground;
        } else if (code >= 40 && code <= 47) {
            m_current.bg = indexedColor(code - 40);
        } else if (code >= 100 && code <= 107) {
            m_current.bg = indexedColor(code - 100 + 8);
        } else if (code == 49) {
            m_current.bg = Qt::transparent;
        } else if ((code == 38 || code == 48) && i + 1 < p.size()) {
            QColor color;
            if (p[i + 1] == 5 && i + 2 < p.size()) {
                color = indexedColor(p[i + 2]);
                i += 2;
            } else if (p[i + 1] == 2 && i + 4 < p.size()) {
                color = QColor(std::clamp(p[i + 2], 0, 255),
                               std::clamp(p[i + 3], 0, 255),
                               std::clamp(p[i + 4], 0, 255));
                i += 4;
            }
            if (color.isValid()) {
                if (code == 38) m_current.fg = color;
                else m_current.bg = color;
            }
        }
    }
}

void TerminalItem::putChar(QChar ch)
{
    if (m_col >= m_cols) {
        m_col = 0;
        lineFeed();
    }
    ensureCursorVisible();
    if (m_row >= 0 && m_row < m_screen.size() && m_col >= 0 && m_col < m_screen[m_row].size()) {
        Cell cell = m_current;
        cell.ch = ch;
        m_screen[m_row][m_col] = cell;
        markDirtyRow(m_row);
    }
    ++m_col;
}

void TerminalItem::lineFeed()
{
    markDirtyRow(m_row);
    ++m_row;
    if (m_row >= m_rows) {
        scrollUp();
        m_row = m_rows - 1;
    }
    markDirtyRow(m_row);
}

void TerminalItem::scrollUp(int lines)
{
    lines = std::clamp(lines, 1, m_rows);
    markAllDirty();
    for (int i = 0; i < lines; ++i) {
        if (!m_screen.isEmpty()) {
            if (!m_altScreen) {
                m_scrollback.push_back(m_screen.first());
                if (m_scrollOffset > 0)
                    ++m_scrollOffset;
                trimScrollback();
            }
            m_screen.removeFirst();
        }
        m_screen.push_back(QVector<Cell>(m_cols));
    }
    m_scrollOffset = std::clamp(m_scrollOffset, 0, maxScrollOffset());
}

void TerminalItem::ensureCursorVisible()
{
    m_row = std::clamp(m_row, 0, m_rows - 1);
    m_col = std::clamp(m_col, 0, m_cols);
}

void TerminalItem::eraseInDisplay(int mode)
{
    if (mode == 3) {
        m_scrollback.clear();
        m_scrollOffset = 0;
        m_screen = QVector<QVector<Cell>>(m_rows, QVector<Cell>(m_cols));
        m_selectionStart = {-1, -1};
        m_selectionEnd = {-1, -1};
        markAllDirty();
        return;
    }
    if (mode == 2) {
        m_screen = QVector<QVector<Cell>>(m_rows, QVector<Cell>(m_cols));
        markAllDirty();
        return;
    }
    if (mode == 0) {
        eraseInLine(0);
        for (int r = m_row + 1; r < m_rows; ++r)
            m_screen[r] = QVector<Cell>(m_cols);
        markAllDirty();
    } else if (mode == 1) {
        eraseInLine(1);
        for (int r = 0; r < m_row; ++r)
            m_screen[r] = QVector<Cell>(m_cols);
        markAllDirty();
    }
}

void TerminalItem::eraseInLine(int mode)
{
    if (m_row < 0 || m_row >= m_screen.size())
        return;
    markDirtyRow(m_row);
    if (mode == 2) {
        m_screen[m_row] = QVector<Cell>(m_cols);
    } else if (mode == 0) {
        for (int c = m_col; c < m_cols; ++c)
            m_screen[m_row][c] = Cell{};
    } else if (mode == 1) {
        for (int c = 0; c <= m_col && c < m_cols; ++c)
            m_screen[m_row][c] = Cell{};
    }
}

QColor TerminalItem::indexedColor(int index) const
{
    index = std::clamp(index, 0, 255);
    if (index < 16 && index < m_palette.size()) return m_palette.at(index);
    if (index >= 232) {
        const int gray = 8 + (index - 232) * 10;
        return QColor(gray, gray, gray);
    }
    const int n = index - 16;
    const int r = n / 36;
    const int g = (n / 6) % 6;
    const int b = n % 6;
    const auto component = [](int value) { return value == 0 ? 0 : 55 + value * 40; };
    return QColor(component(r), component(g), component(b));
}

QPoint TerminalItem::cellFromPosition(const QPointF &pos) const
{
    const int viewportRow = std::clamp(static_cast<int>(pos.y() / m_cellHeight), 0, m_rows - 1);
    return QPoint(std::clamp(static_cast<int>(pos.x() / m_cellWidth), 0, m_cols - 1),
                  visibleGlobalRow(viewportRow));
}

QString TerminalItem::selectedText() const
{
    if (m_selectionStart.x() < 0 || m_selectionEnd.x() < 0)
        return {};

    QPoint a = m_selectionStart;
    QPoint b = m_selectionEnd;
    auto linear = [this](const QPoint &p) { return p.y() * m_cols + p.x(); };
    if (linear(a) > linear(b))
        std::swap(a, b);

    QString result;
    for (int r = a.y(); r <= b.y(); ++r) {
        const QVector<Cell> *row = lineAtGlobalRow(r);
        if (!row)
            continue;
        const int startCol = (r == a.y()) ? a.x() : 0;
        const int endCol = (r == b.y()) ? b.x() : m_cols - 1;
        QString line;
        for (int c = startCol; c <= endCol && c < row->size(); ++c)
            line += row->at(c).ch;
        while (line.endsWith(QLatin1Char(' ')))
            line.chop(1);
        result += line;
        if (r != b.y())
            result += QLatin1Char('\n');
    }
    return result;
}

bool TerminalItem::isSelected(int row, int col) const
{
    if (m_selectionStart.x() < 0 || m_selectionEnd.x() < 0)
        return false;
    int a = m_selectionStart.y() * m_cols + m_selectionStart.x();
    int b = m_selectionEnd.y() * m_cols + m_selectionEnd.x();
    if (a > b) std::swap(a, b);
    const int p = row * m_cols + col;
    return p >= a && p <= b;
}

void TerminalItem::scrollViewport(int lines)
{
    if (m_altScreen || lines == 0 || m_scrollback.isEmpty())
        return;

    const int next = std::clamp(m_scrollOffset + lines, 0, maxScrollOffset());
    if (next == m_scrollOffset)
        return;

    m_scrollOffset = next;
    m_selecting = false;
    m_selectionStart = {-1, -1};
    m_selectionEnd = {-1, -1};
    markAllDirty();
    scheduleRepaint();
}

int TerminalItem::maxScrollOffset() const
{
    return m_altScreen ? 0 : static_cast<int>(m_scrollback.size());
}

int TerminalItem::visibleGlobalRow(int viewportRow) const
{
    const int historyLines = static_cast<int>(m_scrollback.size());
    const int start = std::max(0, historyLines - m_scrollOffset);
    return start + std::clamp(viewportRow, 0, std::max(0, m_rows - 1));
}

const QVector<TerminalItem::Cell> *TerminalItem::lineAtGlobalRow(int globalRow) const
{
    if (globalRow < 0)
        return nullptr;
    const int historyLines = static_cast<int>(m_scrollback.size());
    if (globalRow < historyLines)
        return &m_scrollback[globalRow];
    const int screenRow = globalRow - historyLines;
    if (screenRow < 0 || screenRow >= m_screen.size())
        return nullptr;
    return &m_screen[screenRow];
}

void TerminalItem::trimScrollback()
{
    if (m_maxScrollbackLines <= 0) {
        m_scrollback.clear();
        m_scrollOffset = 0;
        return;
    }
    const int overflow = static_cast<int>(m_scrollback.size()) - m_maxScrollbackLines;
    if (overflow <= 0)
        return;

    m_scrollback.remove(0, overflow);
    if (m_selectionStart.y() >= 0) {
        m_selectionStart.setY(std::max(-1, m_selectionStart.y() - overflow));
        m_selectionEnd.setY(std::max(-1, m_selectionEnd.y() - overflow));
    }
}

void TerminalItem::updateScrollFromScrollbarPosition(qreal y)
{
    const int historyLines = maxScrollOffset();
    if (historyLines <= 0 || height() <= 0.0)
        return;

    constexpr qreal margin = 3.0;
    const qreal trackHeight = std::max<qreal>(1.0, height() - margin * 2.0);
    const qreal totalLines = static_cast<qreal>(historyLines + m_rows);
    const qreal thumbHeight = std::clamp(trackHeight * (static_cast<qreal>(m_rows) / totalLines), 22.0, trackHeight);
    const qreal travel = std::max<qreal>(1.0, trackHeight - thumbHeight);
    const qreal thumbCenter = std::clamp(y - margin - thumbHeight / 2.0, 0.0, travel);
    const qreal bottomFraction = thumbCenter / travel;
    const int nextOffset = std::clamp(
        static_cast<int>(std::lround((1.0 - bottomFraction) * historyLines)),
        0,
        historyLines);

    if (nextOffset == m_scrollOffset)
        return;
    m_scrollOffset = nextOffset;
    m_selecting = false;
    m_selectionStart = {-1, -1};
    m_selectionEnd = {-1, -1};
    markAllDirty();
    scheduleRepaint();
}

QByteArray TerminalItem::keySequence(QKeyEvent *event) const
{
    const Qt::KeyboardModifiers mods = event->modifiers();
    const bool ctrl = mods & Qt::ControlModifier;
    const bool alt = mods & Qt::AltModifier;

    if (ctrl && event->key() >= Qt::Key_A && event->key() <= Qt::Key_Z) {
        const char control = static_cast<char>(event->key() - Qt::Key_A + 1);
        return QByteArray(1, control);
    }

    switch (event->key()) {
    case Qt::Key_Return:
    case Qt::Key_Enter: return "\r";
    case Qt::Key_Backspace: return QByteArray(1, 0x7f);
    case Qt::Key_Tab: return "\t";
    case Qt::Key_Escape: return "\x1b";
    case Qt::Key_Up: return "\x1b[A";
    case Qt::Key_Down: return "\x1b[B";
    case Qt::Key_Right: return "\x1b[C";
    case Qt::Key_Left: return "\x1b[D";
    case Qt::Key_Home: return "\x1b[H";
    case Qt::Key_End: return "\x1b[F";
    case Qt::Key_Insert: return "\x1b[2~";
    case Qt::Key_Delete: return "\x1b[3~";
    case Qt::Key_PageUp: return "\x1b[5~";
    case Qt::Key_PageDown: return "\x1b[6~";
    case Qt::Key_F1: return "\x1bOP";
    case Qt::Key_F2: return "\x1bOQ";
    case Qt::Key_F3: return "\x1bOR";
    case Qt::Key_F4: return "\x1bOS";
    case Qt::Key_F5: return "\x1b[15~";
    case Qt::Key_F6: return "\x1b[17~";
    case Qt::Key_F7: return "\x1b[18~";
    case Qt::Key_F8: return "\x1b[19~";
    case Qt::Key_F9: return "\x1b[20~";
    case Qt::Key_F10: return "\x1b[21~";
    case Qt::Key_F11: return "\x1b[23~";
    case Qt::Key_F12: return "\x1b[24~";
    default: break;
    }

    const QString text = event->text();
    if (!text.isEmpty()) {
        QByteArray bytes = text.toUtf8();
        if (alt)
            bytes.prepend('\x1b');
        return bytes;
    }
    return {};
}

void TerminalItem::updateStatus(const QString &status)
{
    if (m_statusText == status)
        return;
    m_statusText = status;
    emit statusTextChanged();
}
