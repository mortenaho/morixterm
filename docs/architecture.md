# معماری MVP

## جریان اتصال

`SessionForm` → `RdpSessionService` → `Windows RDP plugin` → `RemoteDesktopSurface`

## جریان انتقال فایل

`TransferView` → `TransferQueue` → `FileTransferService` → `RDP virtual channel`

قراردادهای سرویس باید مستقل از UI باشند تا در مرحله‌ی بعد backend ویندوز بدون بازنویسی صفحات جایگزین شود. اعتبارسنجی آدرس، احراز هویت، مجوز فایل و خطاهای شبکه باید در backend نیز تکرار شوند.
