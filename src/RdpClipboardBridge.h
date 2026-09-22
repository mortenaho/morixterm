#pragma once

#include <QByteArray>
#include <QObject>
#include <QProcess>
#include <QString>
#include <QTimer>

#if defined(Q_OS_LINUX) && !defined(Q_OS_ANDROID)
struct _XDisplay;
typedef struct _XDisplay Display;
typedef unsigned long Window;
typedef unsigned long Atom;
#endif

// Mirrors xfreerdp's X11 CLIPBOARD into the Wayland clipboard and back.
// File offers (text/uri-list, gnome/mate copied-files) are kept intact.
// Data that originates in xfreerdp is not re-claimed on X11, so FreeRDP's
// FUSE file clipboard stays mounted until the user pastes it.
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
    friend class RdpSessionControllerTest;

    struct Payload {
        QByteArray text;
        QByteArray uriList;
        QByteArray gnome;
        QByteArray mate;

        bool isEmpty() const
        {
            return text.isEmpty() && uriList.isEmpty() && gnome.isEmpty() && mate.isEmpty();
        }
        bool operator==(const Payload &other) const
        {
            return text == other.text && uriList == other.uriList && gnome == other.gnome
                && mate == other.mate;
        }
    };

    void onQtClipboardChanged();
    void onWaylandWatch();
    void pumpXEvents();
    void beginRemoteFetch();
    void requestSelection(unsigned long target);
    void publishRemote(const Payload &payload);
    void claimLocal(const Payload &payload);
    void pushToWayland(const Payload &payload);
    void handleSelectionRequest(void *event);
    void handleSelectionNotify(void *event);
    Payload normalize(Payload payload) const;
    Payload payloadFromQt() const;
    Payload payloadFromWayland() const;
    QByteArray readWlPaste(const QStringList &args) const;
    void closeDisplay();
    void releaseIgnore();

#if defined(Q_OS_LINUX) && !defined(Q_OS_ANDROID)
    Display *m_display = nullptr;
    Window m_window = 0;
    Atom m_clipboard = 0;
    Atom m_utf8 = 0;
    Atom m_textPlain = 0;
    Atom m_textPlainUtf8 = 0;
    Atom m_uriList = 0;
    Atom m_gnome = 0;
    Atom m_mate = 0;
    Atom m_targets = 0;
    Atom m_property = 0;
    Atom m_incr = 0;
    int m_xfixesEventBase = -1;
    unsigned long m_xTime = 0;
#endif

    QTimer m_pump;
    QTimer m_ignoreTimer;
    QProcess m_watch;
    QString m_wlCopy;
    QString m_wlPaste;
    Payload m_offer;
    Payload m_lastRemote;
    Payload m_lastPushed;
    QByteArray m_targetsRaw;
    bool m_active = false;
    bool m_ignoreQt = false;
    bool m_owningX11 = false;
    bool m_waiting = false;
    bool m_fetchingTargets = false;
    bool m_wantGnome = false;
    bool m_wantMate = false;
    bool m_wantUri = false;
    bool m_wantText = false;
    int m_fetchStage = 0;
    int m_pollTicks = 0;
    int m_suppressWatch = 0;
};
