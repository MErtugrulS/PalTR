# PalTR Accounts

Launcher kayıt, e-posta doğrulama ve oturum API'sidir.

## Yerel çalıştırma

```powershell
dotnet run --project Server/PalTR.Accounts/PalTR.Accounts.csproj
```

Geliştirme ortamında SMTP ayarlanmazsa doğrulama bağlantısı yalnız API konsoluna yazılır. Hesap yine doğrulanmadan giriş yapamaz.

## Üretim ayarları

Gizli bilgiler repoya yazılmaz. Servisi başlatan ortamda aşağıdaki değişkenleri tanımlayın:

- `PALTR_ACCOUNTSERVICE__PUBLICBASEURL=https://accounts.ornekalanadi.com`
- `PALTR_ACCOUNTSERVICE__DATABASEPATH=D:/PalTR/Data/paltr-accounts.db`
- `PALTR_SMTP__HOST=smtp.ornekalanadi.com`
- `PALTR_SMTP__PORT=587`
- `PALTR_SMTP__USESSL=true`
- `PALTR_SMTP__USERNAME=...`
- `PALTR_SMTP__PASSWORD=...`
- `PALTR_SMTP__FROMADDRESS=noreply@ornekalanadi.com`
- `PALTR_SMTP__FROMNAME=PalTR`

Launcher tarafında API adresi:

- `PALTR_ACCOUNT_API_BASE_URL=https://accounts.ornekalanadi.com`

Uzak adreslerde HTTPS zorunludur. SQLite veritabanı ile SMTP parolası yedeklenmeli; SMTP parolası asla launcher paketine konmamalıdır.

## Uç noktalar

- `POST /api/auth/register`
- `GET /api/auth/verify-email?token=...`
- `POST /api/auth/resend-verification`
- `POST /api/auth/login`
- `POST /api/auth/refresh`
- `POST /api/auth/logout`
- `GET /api/auth/me`
- `GET /health`
