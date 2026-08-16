using System.IO;
using System.IO.Compression;
using System.Net;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text.Json;
using PalTRLauncher.Models;

namespace PalTRLauncher.Services;

public sealed class GitHubPalTRInstallationService : IInstallationService, IDisposable
{
    public static readonly Uri DefaultManifestUri = new(
        "https://github.com/MErtugrulS/PalTR/releases/latest/download/paltr-update.json");

    private const long MaximumManifestBytes = 64 * 1024;
    private const long MaximumPackageBytes = 512L * 1024 * 1024;
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true
    };

    private readonly PalworldInstallLocator installLocator;
    private readonly LocalPalTRInstallationService embeddedInstaller;
    private readonly HttpClient httpClient;
    private readonly bool ownsHttpClient;
    private readonly Uri manifestUri;
    private readonly string cacheRoot;

    public GitHubPalTRInstallationService(
        PalworldInstallLocator installLocator,
        LocalPalTRInstallationService embeddedInstaller,
        HttpClient? httpClient = null,
        Uri? manifestUri = null,
        string? cacheRoot = null)
    {
        this.installLocator = installLocator;
        this.embeddedInstaller = embeddedInstaller;
        this.httpClient = httpClient ?? CreateHttpClient();
        ownsHttpClient = httpClient is null;
        this.manifestUri = manifestUri ?? DefaultManifestUri;
        this.cacheRoot = cacheRoot ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "PalTRLauncher",
            "Updates");
    }

    public async Task<InstallationSnapshot> InspectAsync(CancellationToken cancellationToken = default)
    {
        try
        {
            PalTRUpdateManifest manifest = await GetManifestAsync(cancellationToken);
            LocalPalTRInstallationService? cachedInstaller = TryGetCachedInstaller(manifest);
            if (cachedInstaller is not null)
            {
                return await cachedInstaller.InspectAsync(cancellationToken);
            }

            InstallationSnapshot embeddedState = await embeddedInstaller.InspectAsync(cancellationToken);
            string? gameRoot = embeddedState.GameRoot ?? installLocator.FindGameRoot();
            if (gameRoot is null)
            {
                return embeddedState;
            }

            string? installedVersion = TryReadInstalledVersion(gameRoot);
            return new InstallationSnapshot(
                InstallationState.InstallRequired,
                installedVersion is null ? "PalTR kurulacak" : "PalTR güncellemesi hazır",
                $"GitHub sürümü {manifest.Version} indirilmeye hazır.",
                gameRoot,
                manifest.Version);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch
        {
            // Ağ yokken launcher ve gömülü kurtarma paketi kullanılabilir kalır.
            return await embeddedInstaller.InspectAsync(cancellationToken);
        }
    }

    public async Task<InstallationActionResult> InstallOrRepairAsync(CancellationToken cancellationToken = default)
    {
        try
        {
            PalTRUpdateManifest manifest = await GetManifestAsync(cancellationToken);
            LocalPalTRInstallationService installer =
                TryGetCachedInstaller(manifest) ?? await DownloadPackageAsync(manifest, cancellationToken);
            return await installer.InstallOrRepairAsync(cancellationToken);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (Exception exception)
        {
            InstallationSnapshot embeddedState = await embeddedInstaller.InspectAsync(cancellationToken);
            if (embeddedState.CanInstall || embeddedState.CanRetry)
            {
                InstallationActionResult fallback = await embeddedInstaller.InstallOrRepairAsync(cancellationToken);
                if (fallback.Success)
                {
                    return fallback;
                }
            }
            return new InstallationActionResult(false, new InstallationSnapshot(
                InstallationState.Failed,
                "Güncelleme indirilemedi",
                $"GitHub paketi alınamadı. {exception.Message}",
                embeddedState.GameRoot,
                embeddedState.PackageVersion));
        }
    }

    private async Task<PalTRUpdateManifest> GetManifestAsync(CancellationToken cancellationToken)
    {
        EnsureAllowedGitHubUri(manifestUri);
        using HttpResponseMessage response = await httpClient.GetAsync(
            manifestUri,
            HttpCompletionOption.ResponseHeadersRead,
            cancellationToken);
        EnsureAllowedGitHubUri(response.RequestMessage?.RequestUri
            ?? throw new InvalidDataException("Manifest yanıt adresi bulunamadı."));
        response.EnsureSuccessStatusCode();

        if (response.Content.Headers.ContentLength is > MaximumManifestBytes)
        {
            throw new InvalidDataException("Güncelleme manifesti izin verilen boyutu aşıyor.");
        }

        await using Stream source = await response.Content.ReadAsStreamAsync(cancellationToken);
        using MemoryStream buffer = new();
        await CopyWithLimitAsync(source, buffer, MaximumManifestBytes, cancellationToken);
        buffer.Position = 0;
        PalTRUpdateManifest? manifest = await JsonSerializer.DeserializeAsync<PalTRUpdateManifest>(
            buffer,
            JsonOptions,
            cancellationToken);

        ValidateManifest(manifest);
        return manifest!;
    }

    private async Task<LocalPalTRInstallationService> DownloadPackageAsync(
        PalTRUpdateManifest manifest,
        CancellationToken cancellationToken)
    {
        Uri packageUri = new(manifest.PackageUrl, UriKind.Absolute);
        EnsureAllowedGitHubUri(packageUri);
        Directory.CreateDirectory(cacheRoot);

        string archivePath = Path.Combine(cacheRoot, $"PalTRUI-{SafeVersion(manifest.Version)}.zip.part");
        try
        {
            using HttpResponseMessage response = await httpClient.GetAsync(
                packageUri,
                HttpCompletionOption.ResponseHeadersRead,
                cancellationToken);
            EnsureAllowedGitHubUri(response.RequestMessage?.RequestUri
                ?? throw new InvalidDataException("Paket yanıt adresi bulunamadı."));
            response.EnsureSuccessStatusCode();

            long expectedSize = manifest.Size;
            if (response.Content.Headers.ContentLength is long contentLength && contentLength != expectedSize)
            {
                throw new InvalidDataException("İndirilen paketin boyutu manifest ile eşleşmiyor.");
            }

            await using Stream source = await response.Content.ReadAsStreamAsync(cancellationToken);
            await using (FileStream destination = new(
                archivePath,
                FileMode.Create,
                FileAccess.Write,
                FileShare.None,
                64 * 1024,
                FileOptions.Asynchronous | FileOptions.SequentialScan))
            {
                await CopyWithLimitAsync(source, destination, expectedSize, cancellationToken, requireExactSize: true);
            }

            string actualHash = await ComputeSha256Async(archivePath, cancellationToken);
            if (!actualHash.Equals(manifest.Sha256, StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidDataException("İndirilen paketin SHA-256 doğrulaması başarısız.");
            }

            string packageRoot = GetPackageRoot(manifest.Version);
            string stagingRoot = packageRoot + ".staging-" + Guid.NewGuid().ToString("N");
            ExtractSafely(archivePath, stagingRoot);
            ValidateExtractedPayload(stagingRoot, manifest.Version);

            if (Directory.Exists(packageRoot))
            {
                Directory.Delete(packageRoot, true);
            }
            Directory.Move(stagingRoot, packageRoot);
            return CreateCachedInstaller(packageRoot);
        }
        finally
        {
            if (File.Exists(archivePath))
            {
                File.Delete(archivePath);
            }
        }
    }

    private LocalPalTRInstallationService? TryGetCachedInstaller(PalTRUpdateManifest manifest)
    {
        string packageRoot = GetPackageRoot(manifest.Version);
        try
        {
            ValidateExtractedPayload(packageRoot, manifest.Version);
            return CreateCachedInstaller(packageRoot);
        }
        catch
        {
            return null;
        }
    }

    private LocalPalTRInstallationService CreateCachedInstaller(string packageRoot)
        => new(installLocator, packageRoot, embeddedInstaller.DependencyRoot);

    private string GetPackageRoot(string version)
        => Path.Combine(cacheRoot, "Packages", SafeVersion(version));

    private static void ValidateManifest(PalTRUpdateManifest? manifest)
    {
        if (manifest is null || manifest.SchemaVersion != 1)
        {
            throw new InvalidDataException("Desteklenmeyen güncelleme manifesti.");
        }
        if (!manifest.Channel.Equals("stable", StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidDataException("Güncelleme kanalı desteklenmiyor.");
        }
        if (string.IsNullOrWhiteSpace(manifest.Version) || manifest.Version.Length > 80)
        {
            throw new InvalidDataException("Güncelleme sürümü geçersiz.");
        }
        if (manifest.Size <= 0 || manifest.Size > MaximumPackageBytes)
        {
            throw new InvalidDataException("Güncelleme paketi boyutu geçersiz.");
        }
        if (manifest.Sha256.Length != 64 || !manifest.Sha256.All(Uri.IsHexDigit))
        {
            throw new InvalidDataException("Güncelleme paketi SHA-256 değeri geçersiz.");
        }
        EnsureAllowedGitHubUri(new Uri(manifest.PackageUrl, UriKind.Absolute));
    }

    private static void EnsureAllowedGitHubUri(Uri uri)
    {
        if (uri.Scheme != Uri.UriSchemeHttps ||
            !(uri.Host.Equals("github.com", StringComparison.OrdinalIgnoreCase) ||
              uri.Host.EndsWith(".github.com", StringComparison.OrdinalIgnoreCase) ||
              uri.Host.EndsWith(".githubusercontent.com", StringComparison.OrdinalIgnoreCase)))
        {
            throw new InvalidDataException("Güncelleme adresi izin verilen GitHub HTTPS alanında değil.");
        }
    }

    private static void ExtractSafely(string archivePath, string destinationRoot)
    {
        Directory.CreateDirectory(destinationRoot);
        string canonicalRoot = Path.GetFullPath(destinationRoot) + Path.DirectorySeparatorChar;
        long extractedBytes = 0;
        using ZipArchive archive = ZipFile.OpenRead(archivePath);
        foreach (ZipArchiveEntry entry in archive.Entries)
        {
            extractedBytes += entry.Length;
            if (extractedBytes > MaximumPackageBytes)
            {
                throw new InvalidDataException("Açılan güncelleme paketi izin verilen boyutu aşıyor.");
            }

            string destination = Path.GetFullPath(Path.Combine(destinationRoot, entry.FullName));
            if (!destination.StartsWith(canonicalRoot, StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidDataException("Güncelleme paketinde geçersiz dosya yolu bulundu.");
            }

            if (string.IsNullOrEmpty(entry.Name))
            {
                Directory.CreateDirectory(destination);
                continue;
            }

            Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
            entry.ExtractToFile(destination, true);
        }
    }

    private static void ValidateExtractedPayload(string packageRoot, string expectedVersion)
    {
        string payload = Path.Combine(packageRoot, "Payload", "PalTRUI");
        string infoPath = Path.Combine(payload, "Info.json");
        if (!File.Exists(infoPath) ||
            !File.Exists(Path.Combine(payload, "LogicMods", "PalTRUI.pak")) ||
            !Directory.Exists(Path.Combine(payload, "Scripts")))
        {
            throw new InvalidDataException("Güncelleme paketinin PalTRUI dizin yapısı geçersiz.");
        }

        using JsonDocument info = JsonDocument.Parse(File.ReadAllText(infoPath));
        string? version = info.RootElement.TryGetProperty("Version", out JsonElement value)
            ? value.GetString()
            : null;
        if (!string.Equals(version, expectedVersion, StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidDataException("Paket sürümü manifest ile eşleşmiyor.");
        }
    }

    private static string? TryReadInstalledVersion(string gameRoot)
    {
        string infoPath = Path.Combine(
            gameRoot,
            "Mods",
            "NativeMods",
            "UE4SS",
            "Mods",
            "PalTRUI",
            "Info.json");
        try
        {
            using JsonDocument info = JsonDocument.Parse(File.ReadAllText(infoPath));
            return info.RootElement.TryGetProperty("Version", out JsonElement value)
                ? value.GetString()
                : null;
        }
        catch
        {
            return null;
        }
    }

    private static async Task CopyWithLimitAsync(
        Stream source,
        Stream destination,
        long limit,
        CancellationToken cancellationToken,
        bool requireExactSize = false)
    {
        byte[] buffer = new byte[64 * 1024];
        long total = 0;
        int read;
        while ((read = await source.ReadAsync(buffer.AsMemory(0, buffer.Length), cancellationToken)) > 0)
        {
            total += read;
            if (total > limit)
            {
                throw new InvalidDataException("İndirilen içerik izin verilen boyutu aşıyor.");
            }
            await destination.WriteAsync(buffer.AsMemory(0, read), cancellationToken);
        }
        if (requireExactSize && total != limit)
        {
            throw new InvalidDataException("İndirilen paket eksik veya beklenenden farklı boyutta.");
        }
    }

    private static async Task<string> ComputeSha256Async(string path, CancellationToken cancellationToken)
    {
        await using FileStream stream = File.OpenRead(path);
        using SHA256 sha256 = SHA256.Create();
        byte[] buffer = new byte[64 * 1024];
        int read;
        while ((read = await stream.ReadAsync(buffer.AsMemory(0, buffer.Length), cancellationToken)) > 0)
        {
            sha256.TransformBlock(buffer, 0, read, null, 0);
        }
        sha256.TransformFinalBlock(Array.Empty<byte>(), 0, 0);
        byte[] hash = sha256.Hash ?? throw new CryptographicException("SHA-256 üretilemedi.");
        return Convert.ToHexString(hash);
    }

    private static string SafeVersion(string version)
    {
        char[] invalid = Path.GetInvalidFileNameChars();
        string safe = new(version.Select(character => invalid.Contains(character) ? '_' : character).ToArray());
        return safe.Length == 0 ? "unknown" : safe;
    }

    private static HttpClient CreateHttpClient()
    {
        HttpClient client = new()
        {
            Timeout = TimeSpan.FromSeconds(30)
        };
        client.DefaultRequestHeaders.UserAgent.ParseAdd("PalTRLauncher/0.1");
        return client;
    }

    public void Dispose()
    {
        if (ownsHttpClient)
        {
            httpClient.Dispose();
        }
    }
}
