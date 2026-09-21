#include "RdpViewItem.h"
#include "RdpConstants.h"

#include <QKeyEvent>
#include <QMouseEvent>
#include <QPainter>
#include <QWheelEvent>

RdpViewItem::RdpViewItem(QQuickItem *parent)
    : QQuickPaintedItem(parent)
{
    setAcceptedMouseButtons(Qt::AllButtons);
    setAcceptHoverEvents(true);
    setFlag(ItemAcceptsInputMethod, true);
    setImplicitWidth(1280);
    setImplicitHeight(800);
}

void RdpViewItem::setClient(Rdp::Client *client)
{
    if (m_client == client)
        return;

    if (m_client) {
        disconnect(m_fbConn);
        disconnect(m_stateConn);
    }
    m_client = client;
    if (m_client) {
        m_fbConn = connect(m_client, &Rdp::Client::framebufferChanged, this, [this](const QRect &) {
            update();
        });
        m_stateConn = connect(m_client, &Rdp::Client::stateChanged, this, [this] {
            const bool now = m_client && m_client->state() == Rdp::State::Active;
            if (m_connected != now) {
                m_connected = now;
                emit connectedChanged();
            }
            update();
        });
    }
    emit clientChanged();
    update();
}

void RdpViewItem::paint(QPainter *painter)
{
    painter->fillRect(boundingRect(), QColor(0x18, 0x19, 0x1a));
    if (!m_client)
        return;
    const QImage fb = m_client->framebuffer();
    if (fb.isNull())
        return;
    painter->drawImage(boundingRect(), fb);
}

quint16 RdpViewItem::mouseFlagsForButtons(Qt::MouseButtons buttons) const
{
    quint16 flags = Rdp::PtrFlagsMove;
    if (buttons & Qt::LeftButton)
        flags |= Rdp::PtrFlagsButton1 | Rdp::PtrFlagsDown;
    if (buttons & Qt::RightButton)
        flags |= Rdp::PtrFlagsButton2 | Rdp::PtrFlagsDown;
    if (buttons & Qt::MiddleButton)
        flags |= Rdp::PtrFlagsButton3 | Rdp::PtrFlagsDown;
    return flags;
}

void RdpViewItem::sendMouse(quint16 flags, QPointF pos)
{
    if (!m_client || !m_connected)
        return;
    const QImage fb = m_client->framebuffer();
    if (fb.isNull() || width() <= 0 || height() <= 0)
        return;
    const int x = int(pos.x() * fb.width() / width());
    const int y = int(pos.y() * fb.height() / height());
    m_client->sendMouse(flags, x, y);
}

void RdpViewItem::mousePressEvent(QMouseEvent *event)
{
    forceActiveFocus();
    quint16 flags = Rdp::PtrFlagsDown;
    if (event->button() == Qt::LeftButton)
        flags |= Rdp::PtrFlagsButton1;
    else if (event->button() == Qt::RightButton)
        flags |= Rdp::PtrFlagsButton2;
    else if (event->button() == Qt::MiddleButton)
        flags |= Rdp::PtrFlagsButton3;
    sendMouse(flags, event->position());
    event->accept();
}

void RdpViewItem::mouseReleaseEvent(QMouseEvent *event)
{
    quint16 flags = 0;
    if (event->button() == Qt::LeftButton)
        flags |= Rdp::PtrFlagsButton1;
    else if (event->button() == Qt::RightButton)
        flags |= Rdp::PtrFlagsButton2;
    else if (event->button() == Qt::MiddleButton)
        flags |= Rdp::PtrFlagsButton3;
    sendMouse(flags, event->position());
    event->accept();
}

void RdpViewItem::mouseMoveEvent(QMouseEvent *event)
{
    sendMouse(mouseFlagsForButtons(event->buttons()), event->position());
    event->accept();
}

void RdpViewItem::hoverMoveEvent(QHoverEvent *event)
{
    sendMouse(Rdp::PtrFlagsMove, event->position());
    event->accept();
}

void RdpViewItem::wheelEvent(QWheelEvent *event)
{
    const int delta = event->angleDelta().y();
    if (delta == 0)
        return;
    quint16 flags = Rdp::PtrFlagsWheel;
    int ticks = qBound(1, qAbs(delta) / 120, 10);
    if (delta < 0)
        flags |= Rdp::PtrFlagsWheelNegative;
    flags |= quint16((ticks << 8) & 0xFF00);
    sendMouse(flags, event->position());
    event->accept();
}

quint16 RdpViewItem::qtKeyToRdpScanCode(int key, bool *extended) const
{
    if (extended)
        *extended = false;
    switch (key) {
    case Qt::Key_Escape: return 0x01;
    case Qt::Key_1: return 0x02;
    case Qt::Key_2: return 0x03;
    case Qt::Key_3: return 0x04;
    case Qt::Key_4: return 0x05;
    case Qt::Key_5: return 0x06;
    case Qt::Key_6: return 0x07;
    case Qt::Key_7: return 0x08;
    case Qt::Key_8: return 0x09;
    case Qt::Key_9: return 0x0A;
    case Qt::Key_0: return 0x0B;
    case Qt::Key_Backspace: return 0x0E;
    case Qt::Key_Tab: return 0x0F;
    case Qt::Key_Return:
    case Qt::Key_Enter: return 0x1C;
    case Qt::Key_Control: return 0x1D;
    case Qt::Key_Shift: return 0x2A;
    case Qt::Key_Alt: return 0x38;
    case Qt::Key_Space: return 0x39;
    case Qt::Key_CapsLock: return 0x3A;
    case Qt::Key_F1: return 0x3B;
    case Qt::Key_F2: return 0x3C;
    case Qt::Key_F3: return 0x3D;
    case Qt::Key_F4: return 0x3E;
    case Qt::Key_F5: return 0x3F;
    case Qt::Key_F6: return 0x40;
    case Qt::Key_F7: return 0x41;
    case Qt::Key_F8: return 0x42;
    case Qt::Key_F9: return 0x43;
    case Qt::Key_F10: return 0x44;
    case Qt::Key_F11: return 0x57;
    case Qt::Key_F12: return 0x58;
    case Qt::Key_Delete:
        if (extended) *extended = true;
        return 0x53;
    case Qt::Key_Left:
        if (extended) *extended = true;
        return 0x4B;
    case Qt::Key_Up:
        if (extended) *extended = true;
        return 0x48;
    case Qt::Key_Right:
        if (extended) *extended = true;
        return 0x4D;
    case Qt::Key_Down:
        if (extended) *extended = true;
        return 0x50;
    case Qt::Key_A: return 0x1E;
    case Qt::Key_B: return 0x30;
    case Qt::Key_C: return 0x2E;
    case Qt::Key_D: return 0x20;
    case Qt::Key_E: return 0x12;
    case Qt::Key_F: return 0x21;
    case Qt::Key_G: return 0x22;
    case Qt::Key_H: return 0x23;
    case Qt::Key_I: return 0x17;
    case Qt::Key_J: return 0x24;
    case Qt::Key_K: return 0x25;
    case Qt::Key_L: return 0x26;
    case Qt::Key_M: return 0x32;
    case Qt::Key_N: return 0x31;
    case Qt::Key_O: return 0x18;
    case Qt::Key_P: return 0x19;
    case Qt::Key_Q: return 0x10;
    case Qt::Key_R: return 0x13;
    case Qt::Key_S: return 0x1F;
    case Qt::Key_T: return 0x14;
    case Qt::Key_U: return 0x16;
    case Qt::Key_V: return 0x2F;
    case Qt::Key_W: return 0x11;
    case Qt::Key_X: return 0x2D;
    case Qt::Key_Y: return 0x15;
    case Qt::Key_Z: return 0x2C;
    default: return 0;
    }
}

void RdpViewItem::keyPressEvent(QKeyEvent *event)
{
    if (!m_client || !m_connected) {
        QQuickPaintedItem::keyPressEvent(event);
        return;
    }
    bool extended = false;
    const quint16 code = qtKeyToRdpScanCode(event->key(), &extended);
    if (code) {
        quint16 flags = Rdp::KbdFlagsDown;
        if (extended)
            flags |= Rdp::KbdFlagsExtended;
        m_client->sendKey(flags, code);
        event->accept();
        return;
    }
    QQuickPaintedItem::keyPressEvent(event);
}

void RdpViewItem::keyReleaseEvent(QKeyEvent *event)
{
    if (!m_client || !m_connected) {
        QQuickPaintedItem::keyReleaseEvent(event);
        return;
    }
    bool extended = false;
    const quint16 code = qtKeyToRdpScanCode(event->key(), &extended);
    if (code) {
        quint16 flags = Rdp::KbdFlagsUp;
        if (extended)
            flags |= Rdp::KbdFlagsExtended;
        m_client->sendKey(flags, code);
        event->accept();
        return;
    }
    QQuickPaintedItem::keyReleaseEvent(event);
}
