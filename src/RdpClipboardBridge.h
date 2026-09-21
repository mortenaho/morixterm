#pragma once

#include <QByteArray>
#include <QObject>
#include <QString>
#include <QTimer>

#if defined(Q_OS_LINUX) && !defined(Q_OS_ANDROID)
struct _XDisplay;
typedef struct _XDisplay Display;
typedef unsigned long Window;
typedef unsigned long Atom;
#endif

// Bridges FreeRDP's X11 CLIPBOARD (xfreerdp under XWayland) with the Wayland
// compositor clipboard exposed through Qt, so copy/paste works both ways on
// GNOME/KDE Wayland sessions without freerdp-sdl.
class RdpClipboardBridge : public QObject
{
    Q_OBJECT

public:
    explicit RdpClipboardBridge(QObject *parent = nullptr);
    ~RdpClipboardBridge() override;

    void start();
    void stop();
    bool isActive() const { return m_active; }

private:
    void onQtClipboardChanged();
    void pumpXEvents();
    void requestX11Clipboard();
    void publishToQt(const QString &text);
    void claimX11Clipboard(const QString &text);
    void handleSelectionRequest(void *event);
    void handleSelectionNotify(void *event);
    void closeDisplay();

#if defined(Q_OS_LINUX) && !defined(Q_OS_ANDROID)
    Display *m_display = nullptr;
    Window m_window = 0;
    Atom m_clipboard = 0;
    Atom m_primary = 0;
    Atom m_utf8 = 0;
    Atom m_targets = 0;
    Atom m_property = 0;
    Atom m_incr = 0;
    int m_xfixesEventBase = -1;
#endif

    QTimer m_pump;
    QByteArray m_x11Payload;
    QString m_lastText;
    bool m_active = false;
    bool m_ignoreQt = false;
    bool m_owningX11 = false;
    bool m_waitingNotify = false;
    int m_pollTicks = 0;
};
