#include "RdpClipboardBridge.h"

#include <QGuiApplication>
#include <QClipboard>
#include <QMimeData>
#include <QtGlobal>

#if defined(Q_OS_LINUX) && !defined(Q_OS_ANDROID)
#include <X11/Xatom.h>
#include <X11/Xlib.h>
#include <X11/extensions/Xfixes.h>
#include <cstring>
#endif

RdpClipboardBridge::RdpClipboardBridge(QObject *parent)
    : QObject(parent)
{
    m_pump.setInterval(50);
    connect(&m_pump, &QTimer::timeout, this, &RdpClipboardBridge::pumpXEvents);
}

RdpClipboardBridge::~RdpClipboardBridge()
{
    stop();
}

void RdpClipboardBridge::start()
{
#if !(defined(Q_OS_LINUX) && !defined(Q_OS_ANDROID))
    return;
#else
    if (m_active)
        return;
    // Only needed when MoriXterm itself is on Wayland while FreeRDP uses X11.
    if (qEnvironmentVariableIsEmpty("WAYLAND_DISPLAY"))
        return;

    XInitThreads();
    m_display = XOpenDisplay(nullptr);
    if (!m_display)
        return;

    const int screen = DefaultScreen(m_display);
    m_window = XCreateSimpleWindow(m_display, RootWindow(m_display, screen),
                                   0, 0, 1, 1, 0, 0, 0);
    m_clipboard = XInternAtom(m_display, "CLIPBOARD", False);
    m_primary = XInternAtom(m_display, "PRIMARY", False);
    m_utf8 = XInternAtom(m_display, "UTF8_STRING", False);
    m_targets = XInternAtom(m_display, "TARGETS", False);
    m_property = XInternAtom(m_display, "MORIXTERM_CLIPBOARD", False);
    m_incr = XInternAtom(m_display, "INCR", False);

    int errorBase = 0;
    if (XFixesQueryExtension(m_display, &m_xfixesEventBase, &errorBase)) {
        XFixesSelectSelectionInput(m_display, DefaultRootWindow(m_display), m_clipboard,
                                   XFixesSetSelectionOwnerNotifyMask
                                       | XFixesSelectionWindowDestroyNotifyMask
                                       | XFixesSelectionClientCloseNotifyMask);
    }

    if (QClipboard *clip = QGuiApplication::clipboard()) {
        connect(clip, &QClipboard::dataChanged, this, &RdpClipboardBridge::onQtClipboardChanged,
                Qt::UniqueConnection);
    }

    m_active = true;
    m_pump.start();
    requestX11Clipboard();
#endif
}

void RdpClipboardBridge::stop()
{
#if defined(Q_OS_LINUX) && !defined(Q_OS_ANDROID)
    m_pump.stop();
    if (QClipboard *clip = QGuiApplication::clipboard())
        disconnect(clip, &QClipboard::dataChanged, this, &RdpClipboardBridge::onQtClipboardChanged);
    closeDisplay();
#endif
    m_active = false;
    m_owningX11 = false;
    m_waitingNotify = false;
    m_x11Payload.clear();
    m_lastText.clear();
}

void RdpClipboardBridge::closeDisplay()
{
#if defined(Q_OS_LINUX) && !defined(Q_OS_ANDROID)
    if (!m_display)
        return;
    if (m_window)
        XDestroyWindow(m_display, m_window);
    XCloseDisplay(m_display);
    m_display = nullptr;
    m_window = 0;
#endif
}

void RdpClipboardBridge::onQtClipboardChanged()
{
#if defined(Q_OS_LINUX) && !defined(Q_OS_ANDROID)
    if (!m_active || m_ignoreQt || !m_display)
        return;
    QClipboard *clip = QGuiApplication::clipboard();
    if (!clip)
        return;
    const QString text = clip->text();
    if (text.isEmpty() || text == m_lastText)
        return;
    claimX11Clipboard(text);
#endif
}

void RdpClipboardBridge::publishToQt(const QString &text)
{
    if (text.isEmpty() || text == m_lastText)
        return;
    m_lastText = text;
    QClipboard *clip = QGuiApplication::clipboard();
    if (!clip)
        return;
    m_ignoreQt = true;
    clip->setText(text);
    m_ignoreQt = false;
}

void RdpClipboardBridge::claimX11Clipboard(const QString &text)
{
#if defined(Q_OS_LINUX) && !defined(Q_OS_ANDROID)
    if (!m_display)
        return;
    m_x11Payload = text.toUtf8();
    m_lastText = text;
    XSetSelectionOwner(m_display, m_clipboard, m_window, CurrentTime);
    if (XGetSelectionOwner(m_display, m_clipboard) == m_window) {
        m_owningX11 = true;
        XFlush(m_display);
    } else {
        m_owningX11 = false;
    }
#endif
}

void RdpClipboardBridge::requestX11Clipboard()
{
#if defined(Q_OS_LINUX) && !defined(Q_OS_ANDROID)
    if (!m_display || m_owningX11)
        return;
    m_waitingNotify = true;
    XConvertSelection(m_display, m_clipboard, m_utf8, m_property, m_window, CurrentTime);
    XFlush(m_display);
#endif
}

void RdpClipboardBridge::handleSelectionNotify(void *eventPtr)
{
#if defined(Q_OS_LINUX) && !defined(Q_OS_ANDROID)
    auto *event = static_cast<XSelectionEvent *>(eventPtr);
    m_waitingNotify = false;
    if (event->property == None || m_owningX11)
        return;

    Atom type = None;
    int format = 0;
    unsigned long nItems = 0;
    unsigned long bytesAfter = 0;
    unsigned char *data = nullptr;
    if (XGetWindowProperty(m_display, m_window, m_property, 0, 1024 * 1024, True, AnyPropertyType,
                           &type, &format, &nItems, &bytesAfter, &data)
            != Success
        || !data) {
        return;
    }

    QString text;
    if (type == m_incr) {
        // Large transfers via INCR are uncommon for text paste; skip for now.
    } else if (type == m_utf8 || type == XA_STRING) {
        text = QString::fromUtf8(reinterpret_cast<const char *>(data), int(nItems));
    }
    XFree(data);
    if (!text.isEmpty())
        publishToQt(text);
#else
    Q_UNUSED(eventPtr)
#endif
}

void RdpClipboardBridge::handleSelectionRequest(void *eventPtr)
{
#if defined(Q_OS_LINUX) && !defined(Q_OS_ANDROID)
    auto *req = static_cast<XSelectionRequestEvent *>(eventPtr);
    XSelectionEvent reply {};
    reply.type = SelectionNotify;
    reply.display = req->display;
    reply.requestor = req->requestor;
    reply.selection = req->selection;
    reply.target = req->target;
    reply.property = req->property;
    reply.time = req->time;

    if (req->target == m_targets) {
        const Atom targets[] = { m_targets, m_utf8, XA_STRING };
        XChangeProperty(m_display, req->requestor, req->property, XA_ATOM, 32, PropModeReplace,
                        reinterpret_cast<const unsigned char *>(targets), 3);
    } else if ((req->target == m_utf8 || req->target == XA_STRING) && !m_x11Payload.isEmpty()) {
        XChangeProperty(m_display, req->requestor, req->property, req->target, 8, PropModeReplace,
                        reinterpret_cast<const unsigned char *>(m_x11Payload.constData()),
                        m_x11Payload.size());
    } else {
        reply.property = None;
    }

    XSendEvent(m_display, req->requestor, False, 0, reinterpret_cast<XEvent *>(&reply));
    XFlush(m_display);
#else
    Q_UNUSED(eventPtr)
#endif
}

void RdpClipboardBridge::pumpXEvents()
{
#if defined(Q_OS_LINUX) && !defined(Q_OS_ANDROID)
    if (!m_display)
        return;

    while (XPending(m_display)) {
        XEvent event;
        XNextEvent(m_display, &event);

        if (event.type == SelectionRequest) {
            handleSelectionRequest(&event.xselectionrequest);
        } else if (event.type == SelectionNotify) {
            handleSelectionNotify(&event.xselection);
        } else if (event.type == SelectionClear) {
            if (event.xselectionclear.selection == m_clipboard)
                m_owningX11 = false;
        } else if (m_xfixesEventBase >= 0
                   && event.type == m_xfixesEventBase + XFixesSelectionNotify) {
            auto *notify = reinterpret_cast<XFixesSelectionNotifyEvent *>(&event);
            if (notify->selection == m_clipboard && notify->owner != m_window) {
                m_owningX11 = false;
                requestX11Clipboard();
            }
        }
    }

    // Periodic retry if XFixes is unavailable or a convert timed out.
    if (++m_pollTicks >= 10) {
        m_pollTicks = 0;
        if (!m_owningX11 && !m_waitingNotify)
            requestX11Clipboard();
    }
#endif
}
