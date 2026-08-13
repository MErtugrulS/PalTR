using System.ComponentModel.DataAnnotations;
using System.Net;
using System.Net.Mail;
using System.Text.RegularExpressions;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.Extensions.Options;
using PalTR.Accounts;

WebApplicationBuilder builder = WebApplication.CreateBuilder(args);
builder.Configuration.AddEnvironmentVariables("PALTR_");
builder.Services.Configure<AccountOptions>(builder.Configuration.GetSection("AccountService"));
builder.Services.Configure<SmtpOptions>(builder.Configuration.GetSection("Smtp"));
builder.Services.AddSingleton<AccountStore>();
builder.Services.AddSingleton<IVerificationEmailSender, VerificationEmailSender>();
builder.Services.AddRateLimiter(options => options.AddFixedWindowLimiter("auth", limiter =>
{
    limiter.PermitLimit = 20;
    limiter.Window = TimeSpan.FromMinutes(1);
    limiter.QueueLimit = 0;
    limiter.AutoReplenishment = true;
}));

WebApplication app = builder.Build();
await app.Services.GetRequiredService<AccountStore>().InitializeAsync();
app.UseRateLimiter();
app.Use(async (context, next) =>
{
    context.Response.Headers.XContentTypeOptions = "nosniff";
    context.Response.Headers.CacheControl = "no-store";
    await next();
});

RouteGroupBuilder auth = app.MapGroup("/api/auth").RequireRateLimiting("auth");

auth.MapPost("/register", async (RegisterRequest request, AccountStore store,
    IVerificationEmailSender emailSender, IOptions<AccountOptions> optionAccessor) =>
{
    string username = request.Username.Trim();
    string email = request.Email.Trim();
    string? validation = ValidateRegistration(username, email, request.Password);
    if (validation is not null) return Results.Problem(validation, statusCode: 400);

    AccountRecord? account = await store.CreateAccountAsync(username, email, Security.HashPassword(request.Password));
    if (account is null) return Results.Problem("Kullanıcı adı veya e-posta zaten kullanımda.", statusCode: 409);

    AccountOptions options = optionAccessor.Value;
    string token = Security.NewToken();
    await store.SaveVerificationAsync(account.Id, Security.HashToken(token),
        DateTimeOffset.UtcNow.AddHours(options.VerificationTokenHours));
    string url = $"{options.PublicBaseUrl.TrimEnd('/')}/api/auth/verify-email?token={WebUtility.UrlEncode(token)}";
    try { await emailSender.SendAsync(account.Email, account.Username, url); }
    catch (Exception)
    {
        return Results.Problem("Hesap oluşturuldu ancak doğrulama e-postası gönderilemedi. Yöneticiyle iletişime geç.", statusCode: 503);
    }
    return Results.Ok(new MessageResponse("Hesap oluşturuldu. E-postandaki doğrulama bağlantısını aç."));
});

auth.MapGet("/verify-email", async (string token, AccountStore store) =>
{
    bool verified = token.Length == 64 && await store.VerifyEmailAsync(Security.HashToken(token));
    const string success = "<html><body style='font-family:sans-serif;background:#071923;color:#f4e5bd;padding:48px'><h1>E-posta doğrulandı</h1><p>PalTR Launcher'a dönüp giriş yapabilirsin.</p></body></html>";
    const string failure = "<html><body style='font-family:sans-serif;background:#071923;color:#ff9b83;padding:48px'><h1>Bağlantı geçersiz</h1><p>Doğrulama bağlantısının süresi dolmuş veya bağlantı daha önce kullanılmış.</p></body></html>";
    return Results.Content(verified ? success : failure, "text/html", statusCode: verified ? 200 : 400);
});

auth.MapPost("/login", async (LoginRequest request, AccountStore store, IOptions<AccountOptions> optionAccessor) =>
{
    AccountRecord? account = await store.FindAccountAsync(request.Identifier);
    if (account is null || !Security.VerifyPassword(request.Password, account.PasswordHash))
        return Results.Problem("Kullanıcı adı/e-posta veya parola hatalı.", statusCode: 401);
    if (!account.EmailVerified)
        return Results.Problem("Giriş yapmadan önce e-posta adresini doğrula.", statusCode: 403);
    return Results.Ok(await IssueSessionAsync(account, store, optionAccessor.Value));
});

auth.MapPost("/resend-verification", async (ResendVerificationRequest request, AccountStore store,
    IVerificationEmailSender emailSender, IOptions<AccountOptions> optionAccessor) =>
{
    AccountRecord? account = await store.FindAccountAsync(request.Identifier);
    if (account is not null && !account.EmailVerified)
    {
        AccountOptions options = optionAccessor.Value;
        string token = Security.NewToken();
        await store.SaveVerificationAsync(account.Id, Security.HashToken(token),
            DateTimeOffset.UtcNow.AddHours(options.VerificationTokenHours));
        string url = $"{options.PublicBaseUrl.TrimEnd('/')}/api/auth/verify-email?token={WebUtility.UrlEncode(token)}";
        try { await emailSender.SendAsync(account.Email, account.Username, url); }
        catch (Exception)
        {
            return Results.Problem("Doğrulama e-postası gönderilemedi. Daha sonra tekrar dene.", statusCode: 503);
        }
    }
    return Results.Ok(new MessageResponse("Hesap mevcut ve doğrulanmamışsa yeni bağlantı gönderildi."));
});

auth.MapPost("/refresh", async (RefreshRequest request, AccountStore store, IOptions<AccountOptions> optionAccessor) =>
{
    SessionRecord? oldSession = await store.FindSessionByRefreshAsync(Security.HashToken(request.RefreshToken));
    if (oldSession is null) return Results.Problem("Oturum süresi dolmuş. Yeniden giriş yap.", statusCode: 401);
    await store.RevokeSessionAsync(oldSession.RefreshTokenHash);
    AccountRecord account = new(oldSession.AccountId, oldSession.Username, oldSession.Email, string.Empty, true);
    return Results.Ok(await IssueSessionAsync(account, store, optionAccessor.Value));
});

auth.MapPost("/logout", async (RefreshRequest request, AccountStore store) =>
{
    await store.RevokeSessionAsync(Security.HashToken(request.RefreshToken));
    return Results.NoContent();
});

auth.MapGet("/me", async (HttpRequest request, AccountStore store) =>
{
    string? token = ReadBearer(request);
    SessionRecord? session = token is null ? null : await store.FindSessionByAccessAsync(Security.HashToken(token));
    return session is null
        ? Results.Problem("Geçerli oturum bulunamadı.", statusCode: 401)
        : Results.Ok(new AccountResponse(session.Username, session.Email));
});

app.MapGet("/health", () => Results.Ok(new { status = "ok" }));
app.Run();

static async Task<SessionResponse> IssueSessionAsync(AccountRecord account, AccountStore store, AccountOptions options)
{
    string accessToken = Security.NewToken();
    string refreshToken = Security.NewToken();
    DateTimeOffset accessExpiry = DateTimeOffset.UtcNow.AddMinutes(options.AccessTokenMinutes);
    DateTimeOffset refreshExpiry = DateTimeOffset.UtcNow.AddDays(options.RefreshTokenDays);
    await store.CreateSessionAsync(account.Id, Security.HashToken(accessToken), accessExpiry,
        Security.HashToken(refreshToken), refreshExpiry);
    return new(account.Username, account.Email, accessToken, accessExpiry, refreshToken, refreshExpiry);
}

static string? ValidateRegistration(string username, string email, string password)
{
    if (!Regex.IsMatch(username, "^[A-Za-z0-9_]{3,24}$"))
        return "Kullanıcı adı 3-24 karakter olmalı; yalnız harf, rakam ve alt çizgi içerebilir.";
    try { _ = new MailAddress(email); }
    catch (FormatException) { return "Geçerli bir e-posta adresi gir."; }
    if (password.Length < 10 || password.Length > 128 || !password.Any(char.IsUpper) ||
        !password.Any(char.IsLower) || !password.Any(char.IsDigit))
        return "Parola 10-128 karakter olmalı ve büyük harf, küçük harf ile rakam içermeli.";
    return null;
}

static string? ReadBearer(HttpRequest request)
{
    string value = request.Headers.Authorization.ToString();
    return value.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase) ? value[7..].Trim() : null;
}

public sealed record RegisterRequest([Required] string Username, [Required] string Email, [Required] string Password);
public sealed record LoginRequest([Required] string Identifier, [Required] string Password);
public sealed record ResendVerificationRequest([Required] string Identifier);
public sealed record RefreshRequest([Required] string RefreshToken);
public sealed record MessageResponse(string Message);
public sealed record AccountResponse(string Username, string Email);
public sealed record SessionResponse(string Username, string Email, string AccessToken, DateTimeOffset AccessExpiresAt,
    string RefreshToken, DateTimeOffset RefreshExpiresAt);

public partial class Program;
