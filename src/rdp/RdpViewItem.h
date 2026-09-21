#pragma once

#include "RdpClient.h"

#include <QQuickPaintedItem>
#include <QImage>

class RdpViewItem : public QQuickPaintedItem
{
    Q_OBJECT
    Q_PROPERTY(Rdp::Client *client READ client WRITE setClient NOTIFY clientChanged)
    Q_PROPERTY(bool connected READ connected NOTIFY connectedChanged)

public:
    explicit RdpViewItem(QQuickItem *parent = nullptr);

    Rdp::Client *client() const { return m_client; }
    void setClient(Rdp::Client *client);
    bool connected() const { return m_connected; }

    void paint(QPainter *painter) override;

signals:
    void clientChanged();
    void connectedChanged();

protected:
    void keyPressEvent(QKeyEvent *event) override;
    void keyReleaseEvent(QKeyEvent *event) override;
    void mousePressEvent(QMouseEvent *event) override;
    void mouseReleaseEvent(QMouseEvent *event) override;
    void mouseMoveEvent(QMouseEvent *event) override;
    void wheelEvent(QWheelEvent *event) override;
    void hoverMoveEvent(QHoverEvent *event) override;

private:
    quint16 mouseFlagsForButtons(Qt::MouseButtons buttons) const;
    quint16 qtKeyToRdpScanCode(int key, bool *extended) const;
    void sendMouse(quint16 flags, QPointF pos);

    Rdp::Client *m_client = nullptr;
    bool m_connected = false;
    QMetaObject::Connection m_fbConn;
    QMetaObject::Connection m_stateConn;
};
