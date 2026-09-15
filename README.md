# morixterm

اپلیکیشن دسکتاپی مبتنی بر Flutter/Dart برای مدیریت اتصال‌های SSH/RDP، ترمینال تعاملی و مرور فایل‌های ریموت.

سایت دانلود: [`website/`](website/) — دکمه‌های ویندوز و لینوکس همیشه آخرین release گیت‌هاب را می‌گیرند. پس از publish با workflow `Deploy website`: [mortenaho.github.io/morixtrem](https://mortenaho.github.io/morixtrem/)

![morixterm screenshot](assets/morixterm-screenshot.png)

## وضعیت فعلی

نسخه‌ی `2.0.0` شامل پوسته‌ی دسکتاپ، فهرست جلسه‌ها، SSH ترمینال تعاملی، انتقال فایل (آپلود/دانلود)، و اتصال RDP از طریق FreeRDP است. متادیتای جلسه به‌صورت محلی ذخیره می‌شود؛ رمزها داخل vault رمزنگاری‌شده نگه داشته می‌شوند (نه plaintext در SharedPreferences).

## امنیت

تنظیمات قفل از نوار ابزار → **Security** در دسترس است.

### تأیید Host Key (SSH)

- اثر انگشت کلید میزبان در `~/.local/share/morixterm/known_hosts.json` ذخیره می‌شود (TOFU).
- اولین اتصال به یک سرور: دیالوگ Trust با نمایش fingerprint.
- اگر کلید عوض شده باشد: هشدار MITM با گزینه‌های Reject یا Replace.
- برای `scp` سیستمی: `StrictHostKeyChecking=yes` و فایل known_hosts ساخته‌شده با `ssh-keyscan`.

### Vault رمز جلسات

- رمزهای ذخیره‌شده دیگر به‌صورت plaintext در SharedPreferences نوشته نمی‌شوند.
- رمزنگاری AES-GCM در فایل `~/.local/share/morixterm/credentials.vault`.
- اگر App Lock روشن باشد: master key با PBKDF2 از رمز قفل wrap می‌شود.
- اگر App Lock خاموش باشد: کلید با permission `0600` روی دیسک نگه داشته می‌شود.

### قفل برنامه

- تأیید رمز با **PBKDF2-SHA256** (هش‌های قدیمی SHA-256 هنگام استفاده ارتقا می‌یابند).
- **Auto-lock** بعد از بی‌فعالیتی (پیش‌فرض ۱۰ دقیقه؛ قابل تنظیم در Security، یا Off).
- با قفل شدن برنامه، vault هم lock می‌شود و تا Unlock دوباره باز نمی‌شود.

### سخت‌گیری‌های دیگر

- RDP: `/cert:tofu` به‌جای پذیرش کورکورانه گواهی.
- آرگومان‌های FreeRDP (شامل رمز) در فایل موقت با `chmod 600` نوشته می‌شوند، نه روی argv پروسس.
- لاگ‌ها: redaction پسورد/`/p:` و permission `600` روی فایل‌های لاگ در `~/.local/share/morixterm/`.

## اجرا

روی سیستمی که Flutter Desktop نصب و فعال است:

```bash
flutter pub get
flutter run -d linux
# یا
flutter run -d windows
```

## معماری

- لایه‌ی Flutter مسئول UI، مدیریت جلسه‌ها، ترمینال SSH و صفحه‌ی فایل است.
- SSH از `dartssh2` (SFTP/SCP) استفاده می‌کند؛ در صورت نیاز به `scp` سیستمی fallback می‌شود.
- RDP از FreeRDP (`xfreerdp` و مشابه) با درایو اشتراکی محلی برای مرور فایل استفاده می‌کند.
