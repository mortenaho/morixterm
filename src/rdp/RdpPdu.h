#pragma once

#include "RdpBuffer.h"

#include <QString>

namespace Rdp {

QByteArray buildX224ConnectionRequest(const QString &cookieUser, quint32 requestedProtocols);
bool parseX224ConnectionConfirm(const QByteArray &tpktPayload, quint32 *selectedProtocol, quint32 *failureCode, QString *error);

QByteArray buildMcsConnectInitial(int width, int height, quint32 serverSelectedProtocol, const QString &clientName);
QByteArray buildMcsErectDomain();
QByteArray buildMcsAttachUserRequest();
QByteArray buildMcsChannelJoinRequest(quint16 userId, quint16 channelId);

QByteArray buildClientInfoPdu(quint16 userId,
                              quint16 mcsChannelId,
                              const QString &domain,
                              const QString &user,
                              const QString &password,
                              int width,
                              int height);

QByteArray buildConfirmActive(quint16 userId, quint16 mcsChannelId, quint16 shareId, int width, int height);
QByteArray buildSynchronize(quint16 userId, quint16 mcsChannelId, quint16 shareId);
QByteArray buildControl(quint16 userId, quint16 mcsChannelId, quint16 shareId, quint16 action);
QByteArray buildFontList(quint16 userId, quint16 mcsChannelId, quint16 shareId);
QByteArray buildInputEvent(quint16 userId, quint16 mcsChannelId, const QByteArray &events);
QByteArray buildMouseEvent(quint16 flags, quint16 x, quint16 y);
QByteArray buildScanCodeEvent(quint16 flags, quint16 code);

QByteArray wrapSendDataRequest(quint16 userId, quint16 channelId, const QByteArray &data);

} // namespace Rdp
