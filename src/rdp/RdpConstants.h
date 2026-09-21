#pragma once

#include <QtGlobal>

namespace Rdp {

inline constexpr quint8 TpktVersion = 0x03;

inline constexpr quint8 X224Data = 0xF0;
inline constexpr quint8 X224ConnectRequest = 0xE0;
inline constexpr quint8 X224ConnectConfirm = 0xD0;
inline constexpr quint8 X224DisconnectRequest = 0x80;

inline constexpr quint8 NegReq = 0x01;
inline constexpr quint8 NegRsp = 0x02;
inline constexpr quint8 NegFailure = 0x03;

inline constexpr quint32 ProtocolRdp = 0x00000000;
inline constexpr quint32 ProtocolSsl = 0x00000001;
inline constexpr quint32 ProtocolHybrid = 0x00000002;
inline constexpr quint32 ProtocolRdstls = 0x00000004;
inline constexpr quint32 ProtocolHybridEx = 0x00000008;

inline constexpr quint16 UdCsCore = 0xC001;
inline constexpr quint16 UdCsSecurity = 0xC002;
inline constexpr quint16 UdCsNet = 0xC003;
inline constexpr quint16 UdCsCluster = 0xC004;
inline constexpr quint16 UdScCore = 0x0C01;
inline constexpr quint16 UdScSecurity = 0x0C02;
inline constexpr quint16 UdScNet = 0x0C03;

inline constexpr quint32 ChannelOptionInitialized = 0x80000000u;
inline constexpr quint32 ChannelOptionEncryptRdp = 0x40000000u;
inline constexpr quint32 ChannelOptionCompressRdp = 0x00800000u;
inline constexpr quint32 ChannelOptionShowProtocol = 0x00200000u;

inline constexpr quint16 IoChannelId = 1003;

inline constexpr quint16 PdutypeDemandActive = 0x1;
inline constexpr quint16 PdutypeConfirmActive = 0x3;
inline constexpr quint16 PdutypeDeactivateAll = 0x6;
inline constexpr quint16 PdutypeData = 0x7;
inline constexpr quint16 PdutypeServerRedirect = 0xA;

inline constexpr quint16 Pdutype2Synchronize = 0x1F;
inline constexpr quint16 Pdutype2Control = 0x14;
inline constexpr quint16 Pdutype2Fontlist = 0x27;
inline constexpr quint16 Pdutype2Fontmap = 0x28;
inline constexpr quint16 Pdutype2Input = 0x1C;
inline constexpr quint16 Pdutype2Pointer = 0x1B;
inline constexpr quint16 Pdutype2Update = 0x02;
inline constexpr quint16 Pdutype2SaveSessionInfo = 0x21;
inline constexpr quint16 Pdutype2BitmapcachePersistentList = 0x2B;
inline constexpr quint16 Pdutype2SetErrorInfo = 0x2F;

inline constexpr quint16 UpdateTypeOrders = 0x0000;
inline constexpr quint16 UpdateTypeBitmap = 0x0001;
inline constexpr quint16 UpdateTypePalette = 0x0002;
inline constexpr quint16 UpdateTypeSynchronize = 0x0003;

inline constexpr quint16 InputEventSync = 0x0000;
inline constexpr quint16 InputEventUnused = 0x0001;
inline constexpr quint16 InputEventScanCode = 0x0004;
inline constexpr quint16 InputEventUnicode = 0x0005;
inline constexpr quint16 InputEventMouse = 0x8001;
inline constexpr quint16 InputEventMouseX = 0x8002;

inline constexpr quint16 PtrFlagsMove = 0x0800;
inline constexpr quint16 PtrFlagsDown = 0x8000;
inline constexpr quint16 PtrFlagsButton1 = 0x1000;
inline constexpr quint16 PtrFlagsButton2 = 0x2000;
inline constexpr quint16 PtrFlagsButton3 = 0x4000;
inline constexpr quint16 PtrFlagsWheel = 0x0200;
inline constexpr quint16 PtrFlagsWheelNegative = 0x0100;

inline constexpr quint16 KbdFlagsDown = 0x0000;
inline constexpr quint16 KbdFlagsUp = 0x8000;
inline constexpr quint16 KbdFlagsExtended = 0x0100;

inline constexpr quint32 FastPathOutput = 0x1;
inline constexpr quint32 FastPathFragment = 0x2;

enum class State {
    Idle,
    Connecting,
    Negotiating,
    TlsHandshake,
    McsConnect,
    Channels,
    SecureSettings,
    Licensing,
    Capabilities,
    Active,
    Closing,
    Failed
};

} // namespace Rdp
