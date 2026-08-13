using System.Net.Http;
using System.Net.Http.Json;
using System.Text.Json;
using PalTRLauncher.Models;

namespace PalTRLauncher.Services;

public sealed class HttpAccountService : IAccountService
{
    private static readonly JsonSerializerOptions JsonOptions = new() { PropertyNameCaseInsensitive = true };
    private readonly HttpClient client;

    public HttpAccountService(string? baseUrl = null, HttpMessageHandler? handler = null)
    {
        string configured = baseUrl ?? Environment.GetEnvironmentVariable("PALTR_ACCOUNT_API_BASE_URL")
            ?? "http://localhost:5086";
        Uri uri = new(configured.TrimEnd('/') + "/", UriKind.Absolute);
        if (uri.Scheme != Uri.UriSchemeHttps && !uri.IsLoopback)
            throw new InvalidOperationException("PalTR hesap API adresi HTTPS kullanmalıdır.");
        client = handler is null ? new HttpClient() : new HttpClient(handler);
        client.BaseAddress = uri;
        client.Timeout = TimeSpan.FromSeconds(15);
    }

    public Task<AccountOperationResult> RegisterAsync(string username, string email, string password)
        => SendAsync(HttpMethod.Post, "api/auth/register", new { username, email, password }, false);

    public Task<AccountOperationResult> LoginAsync(string identifier, string password)
        => SendAsync(HttpMethod.Post, "api/auth/login", new { identifier, password }, true);

    public Task<AccountOperationResult> RefreshAsync(string refreshToken)
        => SendAsync(HttpMethod.Post, "api/auth/refresh", new { refreshToken }, true);

    public async Task LogoutAsync(string refreshToken)
    {
        try { _ = await client.PostAsJsonAsync("api/auth/logout", new { refreshToken }); }
        catch (HttpRequestException) { }
        catch (TaskCanceledException) { }
    }

    private async Task<AccountOperationResult> SendAsync(HttpMethod method, string path, object body, bool expectSession)
    {
        try
        {
            using HttpRequestMessage request = new(method, path) { Content = JsonContent.Create(body) };
            using HttpResponseMessage response = await client.SendAsync(request);
            string json = await response.Content.ReadAsStringAsync();
            if (!response.IsSuccessStatusCode)
                return AccountOperationResult.Failed(ReadMessage(json, "Hesap servisi isteği reddetti."));
            if (!expectSession)
                return AccountOperationResult.Completed(ReadMessage(json, "Hesap oluşturuldu. E-postanı doğrula."));
            AccountSession? session = JsonSerializer.Deserialize<AccountSession>(json, JsonOptions);
            return session is null || string.IsNullOrWhiteSpace(session.RefreshToken)
                ? AccountOperationResult.Failed("Hesap servisi geçersiz oturum yanıtı döndürdü.")
                : AccountOperationResult.Completed("Oturum açıldı.", session);
        }
        catch (HttpRequestException)
        {
            return AccountOperationResult.Failed("Hesap servisine ulaşılamıyor. Bağlantını kontrol et.");
        }
        catch (TaskCanceledException)
        {
            return AccountOperationResult.Failed("Hesap servisi zaman aşımına uğradı.");
        }
        catch (JsonException)
        {
            return AccountOperationResult.Failed("Hesap servisi geçersiz yanıt döndürdü.");
        }
    }

    private static string ReadMessage(string json, string fallback)
    {
        try
        {
            using JsonDocument document = JsonDocument.Parse(json);
            JsonElement root = document.RootElement;
            if (root.TryGetProperty("detail", out JsonElement detail) && !string.IsNullOrWhiteSpace(detail.GetString()))
                return detail.GetString()!;
            if (root.TryGetProperty("message", out JsonElement message) && !string.IsNullOrWhiteSpace(message.GetString()))
                return message.GetString()!;
        }
        catch (JsonException) { }
        return fallback;
    }
}
