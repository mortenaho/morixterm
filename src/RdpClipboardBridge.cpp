#include "RdpClipboardBridge.h"

#include <QClipboard>
#include <QDir>
#include <QFileInfo>
#include <QGuiApplication>
#include <QMimeData>
#include <QStandardPaths>
#include <QUrl>
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
    m_ignoreTimer.setSingleShot(true);
    m_ignoreTimer.setInterval(400);
    connect(&m_ignoreTimer, &QTimer::timeout, this, &RdpClipboardBridge::releaseIgnore);
}

RdpClipboardBridge::~RdpClipboardBridge()
{
    stop();
}

void RdpClipboardBridge::releaseIgnore()
{
    m_ignoreQt = false;
}

void RdpClipboardBridge::start()
{
#if !(defined(Q_OS_LINUX) && !defined(Q_OS_ANDROID))
    return;
#else
    if (m_active)
        return;
    if (qEnvironmentVariableIsEmpty("WAYLAND_DISPLAY"))
        return;

    const auto findTool = [](const QString &name) {
        const QString onPath = QStandardPaths::findExecutable(name);
        if (!onPath.isEmpty())
            return onPath;
        const QStringList dirs {
            QDir(QStandardPaths::writableLocation(QStandardPaths::HomeLocation))
                .filePath(QStringLiteral(".local/bin")),
            QStringLiteral("/usr/bin")
        };
        for (const QString &dir : dirs) {
            const QFileInfo info(QDir(dir).filePath(name));
            if (info.isFile() && info.isExecutable())
                return info.absoluteFilePath();
        }
        return QString();
    };
    m_wlCopy = findTool(QStringLiteral("wl-copy"));
    m_wlPaste = findTool(QStringLiteral("wl-paste"));

    XInitThreads();
    m_display = XOpenDisplay(nullptr);
    if (!m_display)
        return;

    const int screen = DefaultScreen(m_display);
    m_window = XCreateSimpleWindow(m_display, RootWindow(m_display, screen), 0, 0, 1, 1, 0, 0, 0);
    m_clipboard = XInternAtom(m_display, "CLIPBOARD", False);
    m_utf8 = XInternAtom(m_display, "UTF8_STRING", False);
    m_textPlain = XInternAtom(m_display, "text/plain", False);
    m_textPlainUtf8 = XInternAtom(m_display, "text/plain;charset=utf-8", False);
    m_uriList = XInternAtom(m_display, "text/uri-list", False);
    m_gnome = XInternAtom(m_display, "x-special/gnome-copied-files", False);
    m_mate = XInternAtom(m_display, "x-special/mate-copied-files", False);
    m_targets = XInternAtom(m_display, "TARGETS", False);
    m_property = XInternAtom(m_display, "MORIXTERM_CLIPBOARD", False);
    m_incr = XInternAtom(m_display, "INCR", False);
    m_xTime = CurrentTime;

    int errorBase = 0;
    if (XFixesQueryExtension(m_display, &m_xfixesEventBase, &errorBase)) {
        // Deliver owner-change events to our window (same pattern as xf_cliprdr).
        XFixesSelectSelectionInput(m_display, DefaultRootWindow(m_display), m_clipboard,
                                   XFixesSetSelectionOwnerNotifyMask
                                       | XFixesSelectionWindowDestroyNotifyMask
                                       | XFixesSelectionClientCloseNotifyMask);
        XFixesSelectSelectionInput(m_display, m_window, m_clipboard,
                                   XFixesSetSelectionOwnerNotifyMask
                                       | XFixesSelectionWindowDestroyNotifyMask
                                       | XFixesSelectionClientCloseNotifyMask);
    }

    if (QClipboard *clip = QGuiApplication::clipboard()) {
        connect(clip, &QClipboard::dataChanged, this, &RdpClipboardBridge::onQtClipboardChanged,
                Qt::UniqueConnection);
    }

    if (!m_wlPaste.isEmpty()) {
        m_watch.setProgram(m_wlPaste);
        // Drain stdin. A command that ignores the clipboard pipe stalls wl-paste
        // on large file offers and the next paste call deadlocks.
        m_watch.setArguments({QStringLiteral("--watch"), QStringLiteral("sh"), QStringLiteral("-c"),
                              QStringLiteral("cat >/dev/null; printf '%s\\n' morixterm-clip")});
        connect(&m_watch, &QProcess::readyReadStandardOutput, this, &RdpClipboardBridge::onWaylandWatch);
        m_watch.start();
    }

    m_active = true;
    m_pump.start();
    // Own the X11 CLIPBOARD with whatever the desktop already copied. xfreerdp
    // only notices a FormatList update when the selection owner changes after
    // it connects; Mutter's partial XWayland sync is not enough for paste.
    QTimer::singleShot(150, this, [this] {
        if (!m_active)
            return;
        Payload initial = payloadFromWayland();
        if (initial.isEmpty())
            initial = payloadFromQt();
        if (!initial.isEmpty())
            claimLocal(initial);
    });
#endif
}

void RdpClipboardBridge::stop()
{
#if defined(Q_OS_LINUX) && !defined(Q_OS_ANDROID)
    m_pump.stop();
    m_ignoreTimer.stop();
    if (m_watch.state() != QProcess::NotRunning) {
        m_watch.kill();
        m_watch.waitForFinished(200);
    }
    if (QClipboard *clip = QGuiApplication::clipboard())
        disconnect(clip, &QClipboard::dataChanged, this, &RdpClipboardBridge::onQtClipboardChanged);
    closeDisplay();
#endif
    m_active = false;
    m_owningX11 = false;
    m_waiting = false;
    m_offer = {};
    m_lastRemote = {};
    m_lastPushed = {};
    m_suppressWatch = 0;
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

RdpClipboardBridge::Payload RdpClipboardBridge::normalize(Payload payload) const
{
    if (payload.gnome.isEmpty() && !payload.mate.isEmpty())
        payload.gnome = payload.mate;
    if (payload.uriList.isEmpty() && !payload.gnome.isEmpty()) {
        const int nl = payload.gnome.indexOf('\n');
        if (nl >= 0)
            payload.uriList = payload.gnome.mid(nl + 1);
    }
    if (payload.gnome.isEmpty() && !payload.uriList.isEmpty()) {
        payload.gnome = QByteArray("copy\n") + payload.uriList;
        if (!payload.gnome.endsWith('\n'))
            payload.gnome.append('\n');
    }
    if (payload.mate.isEmpty())
        payload.mate = payload.gnome;
    if (payload.text.isEmpty())
        payload.text = payload.uriList;
    return payload;
}

QByteArray RdpClipboardBridge::readWlPaste(const QStringList &args) const
{
    if (m_wlPaste.isEmpty())
        return {};
    QProcess paste;
    paste.start(m_wlPaste, args);
    if (!paste.waitForFinished(800) || paste.exitCode() != 0)
        return {};
    return paste.readAllStandardOutput();
}

RdpClipboardBridge::Payload RdpClipboardBridge::payloadFromWayland() const
{
    Payload payload;
    const QByteArray types = readWlPaste({QStringLiteral("--list-types")});
    const QList<QByteArray> lines = types.split('\n');
    const auto has = [&](const char *name) {
        for (const QByteArray &line : lines) {
            if (line.trimmed() == name)
                return true;
        }
        return false;
    };
    if (has("x-special/gnome-copied-files")) {
        payload.gnome = readWlPaste(
            {QStringLiteral("--no-newline"), QStringLiteral("--type"),
             QStringLiteral("x-special/gnome-copied-files")});
    }
    if (has("x-special/mate-copied-files")) {
        payload.mate = readWlPaste(
            {QStringLiteral("--no-newline"), QStringLiteral("--type"),
             QStringLiteral("x-special/mate-copied-files")});
    }
    if (has("text/uri-list")) {
        payload.uriList = readWlPaste(
            {QStringLiteral("--no-newline"), QStringLiteral("--type"), QStringLiteral("text/uri-list")});
    }
    if (payload.gnome.isEmpty() && payload.uriList.isEmpty()) {
        payload.text = readWlPaste({QStringLiteral("--no-newline"), QStringLiteral("--type"),
                                    QStringLiteral("text/plain;charset=utf-8")});
        if (payload.text.isEmpty()) {
            payload.text = readWlPaste({QStringLiteral("--no-newline"), QStringLiteral("--type"),
                                        QStringLiteral("text/plain")});
        }
        if (payload.text.isEmpty())
            payload.text = readWlPaste({QStringLiteral("--no-newline")});
    }
    return normalize(payload);
}

RdpClipboardBridge::Payload RdpClipboardBridge::payloadFromQt() const
{
    Payload payload;
    QClipboard *clip = QGuiApplication::clipboard();
    const QMimeData *mime = clip ? clip->mimeData() : nullptr;
    if (!mime)
        return payload;
    payload.gnome = mime->data(QStringLiteral("x-special/gnome-copied-files"));
    payload.mate = mime->data(QStringLiteral("x-special/mate-copied-files"));
    payload.uriList = mime->data(QStringLiteral("text/uri-list"));
    if (payload.uriList.isEmpty() && mime->hasUrls()) {
        for (const QUrl &url : mime->urls()) {
            payload.uriList += url.toEncoded();
            payload.uriList += '\n';
        }
    }
    if (payload.gnome.isEmpty() && payload.uriList.isEmpty())
        payload.text = mime->text().toUtf8();
    return normalize(payload);
}

void RdpClipboardBridge::onQtClipboardChanged()
{
    if (!m_active || m_ignoreQt)
        return;
    const Payload payload = payloadFromQt();
    if (payload.isEmpty() || payload == m_lastRemote)
        return;
    // Reclaim even when the bytes match: we may have lost X11 ownership to
    // Mutter's incomplete XWayland mirror while xfreerdp still needs us.
    if (payload == m_offer && m_owningX11)
        return;
    claimLocal(payload);
}

void RdpClipboardBridge::onWaylandWatch()
{
    m_watch.readAllStandardOutput();
    if (!m_active)
        return;
    if (m_suppressWatch > 0) {
        --m_suppressWatch;
        return;
    }
    // Wait until the watch child has released the clipboard offer. Reading it
    // from inside the callback deadlocks wl-paste against itself.
    QTimer::singleShot(80, this, [this] {
        if (!m_active || m_ignoreQt || m_suppressWatch > 0)
            return;
        const Payload payload = payloadFromWayland();
        if (payload.isEmpty() || payload == m_lastRemote)
            return;
        if (payload == m_offer && m_owningX11)
            return;
        claimLocal(payload);
    });
}

void RdpClipboardBridge::pushToWayland(const Payload &payload)
{
    if (m_wlCopy.isEmpty())
        return;
    QStringList args;
    QByteArray body = payload.text;
    if (!payload.gnome.isEmpty()) {
        args << QStringLiteral("--type") << QStringLiteral("x-special/gnome-copied-files");
        body = payload.gnome;
    } else if (!payload.uriList.isEmpty()) {
        args << QStringLiteral("--type") << QStringLiteral("text/uri-list");
        body = payload.uriList;
    }
    if (body.isEmpty())
        return;
    // Our own publish shows up on the watch. Do not claim the X11 selection
    // afterwards or FreeRDP drops the file it is still serving.
    ++m_suppressWatch;
    auto *copy = new QProcess(this);
    copy->start(m_wlCopy, args);
    copy->write(body);
    copy->closeWriteChannel();
    connect(copy, &QProcess::finished, copy, &QObject::deleteLater);
}

void RdpClipboardBridge::publishRemote(const Payload &payload)
{
    const Payload normalized = normalize(payload);
    if (normalized.isEmpty() || normalized == m_lastPushed || normalized == m_lastRemote)
        return;

    // GNOME's XWayland bridge often publishes only a path string after a local
    // file copy. Prefer the real Wayland file offer and keep owning X11.
    if (normalized.uriList.isEmpty() && normalized.gnome.isEmpty() && !normalized.text.isEmpty()) {
        const Payload wayland = payloadFromWayland();
        if (!wayland.uriList.isEmpty() || !wayland.gnome.isEmpty()) {
            claimLocal(wayland);
            return;
        }
    }

    m_lastRemote = normalized;
    m_lastPushed = normalized;

    if (QClipboard *clip = QGuiApplication::clipboard()) {
        auto *mime = new QMimeData;
        if (!normalized.text.isEmpty())
            mime->setText(QString::fromUtf8(normalized.text));
        if (!normalized.uriList.isEmpty()) {
            mime->setData(QStringLiteral("text/uri-list"), normalized.uriList);
            QList<QUrl> urls;
            const QList<QByteArray> lines = normalized.uriList.split('\n');
            for (const QByteArray &line : lines) {
                const QByteArray trimmed = line.trimmed();
                if (trimmed.isEmpty() || trimmed.startsWith('#'))
                    continue;
                const QUrl url = QUrl::fromEncoded(trimmed);
                if (url.isValid())
                    urls.append(url);
            }
            if (!urls.isEmpty())
                mime->setUrls(urls);
        }
        if (!normalized.gnome.isEmpty())
            mime->setData(QStringLiteral("x-special/gnome-copied-files"), normalized.gnome);
        if (!normalized.mate.isEmpty())
            mime->setData(QStringLiteral("x-special/mate-copied-files"), normalized.mate);
        m_ignoreQt = true;
        clip->setMimeData(mime);
        m_ignoreTimer.start();
    }
    pushToWayland(normalized);
}

void RdpClipboardBridge::claimLocal(const Payload &payload)
{
#if defined(Q_OS_LINUX) && !defined(Q_OS_ANDROID)
    if (!m_display)
        return;
    m_offer = normalize(payload);
    if (m_offer.isEmpty())
        return;
    m_lastPushed = m_offer;
    // This offer came from the local desktop, not from xfreerdp.
    m_lastRemote = {};
    // CurrentTime is required here. The stored XFixes timestamp belongs to the
    // previous owner, and the server rejects SetSelectionOwner with that time.
    XSetSelectionOwner(m_display, m_clipboard, m_window, CurrentTime);
    XSync(m_display, False);
    m_owningX11 = XGetSelectionOwner(m_display, m_clipboard) == m_window;
    if (m_owningX11)
        XFlush(m_display);
#else
    Q_UNUSED(payload)
#endif
}

void RdpClipboardBridge::requestSelection(unsigned long target)
{
#if defined(Q_OS_LINUX) && !defined(Q_OS_ANDROID)
    if (!m_display || m_owningX11)
        return;
    m_waiting = true;
    XConvertSelection(m_display, m_clipboard, target, m_property, m_window, m_xTime ? m_xTime : CurrentTime);
    XFlush(m_display);
#else
    Q_UNUSED(target)
#endif
}

void RdpClipboardBridge::beginRemoteFetch()
{
#if defined(Q_OS_LINUX) && !defined(Q_OS_ANDROID)
    if (!m_display || m_owningX11 || m_waiting)
        return;
    m_fetchingTargets = true;
    m_fetchStage = 0;
    m_wantGnome = m_wantMate = m_wantUri = m_wantText = false;
    m_targetsRaw.clear();
    requestSelection(m_targets);
#endif
}

void RdpClipboardBridge::handleSelectionNotify(void *eventPtr)
{
#if defined(Q_OS_LINUX) && !defined(Q_OS_ANDROID)
    auto *event = static_cast<XSelectionEvent *>(eventPtr);
    m_waiting = false;
    if (m_owningX11 || event->property == None) {
        m_fetchingTargets = false;
        return;
    }

    Atom type = None;
    int format = 0;
    unsigned long nItems = 0;
    unsigned long bytesAfter = 0;
    unsigned char *data = nullptr;
    if (XGetWindowProperty(m_display, m_window, m_property, 0, 1024 * 1024, True, AnyPropertyType,
                           &type, &format, &nItems, &bytesAfter, &data)
            != Success
        || !data) {
        m_fetchingTargets = false;
        return;
    }

    if (type == m_incr) {
        XFree(data);
        m_fetchingTargets = false;
        return;
    }

    if (m_fetchingTargets && event->target == m_targets && format == 32) {
        const auto *atoms = reinterpret_cast<const unsigned long *>(data);
        for (unsigned long i = 0; i < nItems; ++i) {
            if (atoms[i] == m_gnome)
                m_wantGnome = true;
            else if (atoms[i] == m_mate)
                m_wantMate = true;
            else if (atoms[i] == m_uriList)
                m_wantUri = true;
            else if (atoms[i] == m_utf8 || atoms[i] == XA_STRING || atoms[i] == m_textPlain
                     || atoms[i] == m_textPlainUtf8)
                m_wantText = true;
        }
        XFree(data);
        m_fetchingTargets = false;
        m_fetchStage = 1;
        if (m_wantGnome)
            requestSelection(m_gnome);
        else if (m_wantUri)
            requestSelection(m_uriList);
        else if (m_wantMate)
            requestSelection(m_mate);
        else if (m_wantText)
            requestSelection(m_utf8);
        return;
    }

    QByteArray bytes;
    if (format == 8)
        bytes = QByteArray(reinterpret_cast<const char *>(data), int(nItems));
    XFree(data);

    Payload payload = m_lastRemote;
    if (event->target == m_gnome)
        payload.gnome = bytes;
    else if (event->target == m_mate)
        payload.mate = bytes;
    else if (event->target == m_uriList)
        payload.uriList = bytes;
    else if (event->target == m_utf8 || event->target == XA_STRING || event->target == m_textPlain
             || event->target == m_textPlainUtf8)
        payload.text = bytes;

    if (m_fetchStage == 1 && m_wantGnome && event->target == m_gnome && m_wantUri) {
        m_lastRemote = payload;
        m_fetchStage = 2;
        requestSelection(m_uriList);
        return;
    }
    if ((m_wantGnome || m_wantUri || m_wantMate) && payload.text.isEmpty() && m_wantText
        && event->target != m_utf8 && event->target != XA_STRING) {
        m_lastRemote = payload;
        m_wantText = false;
        requestSelection(m_utf8);
        return;
    }

    m_fetchStage = 0;
    publishRemote(payload);
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
    reply.property = req->property == None ? m_property : req->property;
    reply.time = req->time;

    const auto writeBytes = [&](Atom type, const QByteArray &bytes) {
        XChangeProperty(m_display, req->requestor, reply.property, type, 8, PropModeReplace,
                        reinterpret_cast<const unsigned char *>(bytes.constData()), bytes.size());
    };

    if (req->target == m_targets) {
        unsigned long targets[8];
        int count = 0;
        targets[count++] = m_targets;
        if (!m_offer.text.isEmpty()) {
            targets[count++] = m_utf8;
            targets[count++] = XA_STRING;
            targets[count++] = m_textPlain;
            targets[count++] = m_textPlainUtf8;
        }
        if (!m_offer.uriList.isEmpty())
            targets[count++] = m_uriList;
        if (!m_offer.gnome.isEmpty())
            targets[count++] = m_gnome;
        if (!m_offer.mate.isEmpty())
            targets[count++] = m_mate;
        XChangeProperty(m_display, req->requestor, reply.property, XA_ATOM, 32, PropModeReplace,
                        reinterpret_cast<const unsigned char *>(targets), count);
    } else if ((req->target == m_utf8 || req->target == XA_STRING || req->target == m_textPlain
                || req->target == m_textPlainUtf8)
               && !m_offer.text.isEmpty()) {
        writeBytes(req->target == XA_STRING ? XA_STRING : m_utf8, m_offer.text);
    } else if (req->target == m_uriList && !m_offer.uriList.isEmpty()) {
        writeBytes(m_uriList, m_offer.uriList);
    } else if (req->target == m_gnome && !m_offer.gnome.isEmpty()) {
        writeBytes(m_gnome, m_offer.gnome);
    } else if (req->target == m_mate && !m_offer.mate.isEmpty()) {
        writeBytes(m_mate, m_offer.mate);
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
                m_xTime = notify->selection_timestamp;
                // Ignore Mutter's echo of a local Wayland copy when we are about
                // to (or already did) claim the full mime set ourselves.
                if (m_suppressWatch == 0)
                    beginRemoteFetch();
            }
        }
    }

    if (m_waiting) {
        if (++m_pollTicks >= 40) {
            m_pollTicks = 0;
            m_waiting = false;
            m_fetchingTargets = false;
        }
    } else if (!m_owningX11 && !m_waiting) {
        // Keep local→remote alive if GNOME steals the X11 selection again.
        if (++m_pollTicks >= 20) {
            m_pollTicks = 0;
            const Payload local = payloadFromWayland();
            if (!local.isEmpty() && local != m_lastRemote
                && (local != m_offer || !m_owningX11)) {
                claimLocal(local);
            } else if (m_xfixesEventBase < 0) {
                beginRemoteFetch();
            }
        }
    } else {
        m_pollTicks = 0;
    }
#endif
}
