using System.Diagnostics;
using System.IO;
using System.Security.Cryptography;
using System.Text.Json;
using PalTRLauncher.Models;

namespace PalTRLauncher.Services;

public sealed class LocalPalTRInstallationService : IInstallationService
{
    private readonly PalworldInstallLocator installLocator;
    private readonly string payloadRoot;

    public LocalPalTRInstallationService(
        PalworldInstallLocator installLocator,
        string? applicationRoot = null)
    {
        this.installLocator = installLocator;
        payloadRoot = Path.Combine(applicationRoot ?? AppContext.BaseDirectory, "Payload", "PalTRUI");
    }

    public async Task<InstallationSnapshot> InspectAsync(CancellationToken cancellationToken = default)
    {
        try
        {
            return await InspectCoreAsync(cancellationToken);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (Exception exception)
        {
            return new InstallationSnapshot(
                InstallationState.Failed,
                "Kurulum denetlenemedi",
                exception.Message);
        }
    }

    private async Task<InstallationSnapshot> InspectCoreAsync(CancellationToken cancellationToken)
    {
        await Task.Yield();
        cancellationToken.ThrowIfCancellationRequested();

        string? gameRoot = installLocator.FindGameRoot();
        if (gameRoot is null)
        {
            return Blocked("Palworld bulunamadı", "Steam Palworld kurulumu bulunamadı. Oyunu Steam üzerinden kurup yeniden dene.");
        }

        if (!TryReadPayloadVersion(out string packageVersion, out string payloadError))
        {
            return Blocked("PalTR paketi eksik", payloadError, gameRoot);
        }

        string dependencyError = GetDependencyError(gameRoot);
        if (dependencyError.Length > 0)
        {
            return Blocked("Gerekli bileşen eksik", dependencyError, gameRoot, packageVersion);
        }

        IReadOnlyList<FileMapping> mappings = BuildMappings(gameRoot);
        foreach (FileMapping mapping in mappings)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (!File.Exists(mapping.Destination) || !FilesMatch(mapping.Source, mapping.Destination))
            {
                return new InstallationSnapshot(
                    InstallationState.InstallRequired,
                    "PalTR güncellemesi hazır",
                    $"PalTR {packageVersion} kurulacak veya onarılacak. Giriş, güncelleme tamamlanınca açılacak.",
                    gameRoot,
                    packageVersion);
            }
        }

        if (!IsPalTRUIEnabled(gameRoot))
        {
            return new InstallationSnapshot(
                InstallationState.InstallRequired,
                "PalTR etkinleştirilecek",
                $"PalTR {packageVersion} dosyaları hazır; UE4SS mod kaydı etkinleştirilecek.",
                gameRoot,
                packageVersion);
        }

        return new InstallationSnapshot(
            InstallationState.Ready,
            "PalTR güncel",
            $"PalTR {packageVersion} dosyaları doğrulandı.",
            gameRoot,
            packageVersion);
    }

    public async Task<InstallationActionResult> InstallOrRepairAsync(CancellationToken cancellationToken = default)
    {
        InstallationSnapshot inspection = await InspectAsync(cancellationToken);
        if (inspection.IsReady)
        {
            return new InstallationActionResult(true, inspection);
        }

        if (!inspection.CanInstall || inspection.GameRoot is null)
        {
            return new InstallationActionResult(false, inspection);
        }

        if (IsPalworldRunning())
        {
            return new InstallationActionResult(false, Blocked(
                "Palworld açık",
                "Güvenli güncelleme için Palworld'ü kapatıp yeniden dene.",
                inspection.GameRoot,
                inspection.PackageVersion));
        }

        string backupRoot = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "PalTRLauncher",
            "Backups",
            DateTime.UtcNow.ToString("yyyyMMdd-HHmmss"));
        List<(string Destination, string? Backup)> changedFiles = new();

        try
        {
            foreach (FileMapping mapping in BuildMappings(inspection.GameRoot))
            {
                cancellationToken.ThrowIfCancellationRequested();
                if (File.Exists(mapping.Destination) && FilesMatch(mapping.Source, mapping.Destination))
                {
                    continue;
                }

                string? destinationDirectory = Path.GetDirectoryName(mapping.Destination);
                if (destinationDirectory is null)
                {
                    throw new InvalidOperationException("Kurulum hedef dizini çözülemedi.");
                }

                Directory.CreateDirectory(destinationDirectory);
                string? backup = null;
                if (File.Exists(mapping.Destination))
                {
                    backup = Path.Combine(backupRoot, mapping.RelativeDestination);
                    Directory.CreateDirectory(Path.GetDirectoryName(backup)!);
                    File.Copy(mapping.Destination, backup, true);
                }

                string temporary = mapping.Destination + ".paltr-new";
                File.Copy(mapping.Source, temporary, true);
                if (!FilesMatch(mapping.Source, temporary))
                {
                    File.Delete(temporary);
                    throw new IOException($"Dosya doğrulaması başarısız: {mapping.RelativeDestination}");
                }

                File.Move(temporary, mapping.Destination, true);
                changedFiles.Add((mapping.Destination, backup));
            }


            EnsurePalTRUIEnabled(inspection.GameRoot, backupRoot, changedFiles);

            InstallationSnapshot finalState = await InspectAsync(cancellationToken);
            return new InstallationActionResult(finalState.IsReady, finalState);
        }
        catch (Exception exception)
        {
            RollBack(changedFiles);
            return new InstallationActionResult(false, new InstallationSnapshot(
                InstallationState.Failed,
                "Güncelleme tamamlanamadı",
                $"Değişiklikler geri alındı. {exception.Message}",
                inspection.GameRoot,
                inspection.PackageVersion));
        }
    }

    private bool TryReadPayloadVersion(out string version, out string error)
    {
        string infoPath = Path.Combine(payloadRoot, "Info.json");
        string pakPath = Path.Combine(payloadRoot, "LogicMods", "PalTRUI.pak");
        string scriptsPath = Path.Combine(payloadRoot, "Scripts");
        if (!File.Exists(infoPath) || !File.Exists(pakPath) || !Directory.Exists(scriptsPath))
        {
            version = string.Empty;
            error = "Launcher dağıtımında PalTRUI payload'ı eksik. Launcher paketini yeniden indir.";
            return false;
        }

        using JsonDocument info = JsonDocument.Parse(File.ReadAllText(infoPath));
        version = info.RootElement.TryGetProperty("Version", out JsonElement value)
            ? value.GetString() ?? "bilinmeyen"
            : "bilinmeyen";
        error = string.Empty;
        return true;
    }

    private static string GetDependencyError(string gameRoot)
    {
        string ue4ss = Path.Combine(gameRoot, "Mods", "NativeMods", "UE4SS", "UE4SS.dll");
        string managedDependency = Path.Combine(gameRoot, "Mods", "ManagedMods", "UE4SSExperimentalPW", "Info.json");
        if (!File.Exists(ue4ss))
        {
            return "UE4SS kurulu değil. Onaylı UE4SS dağıtımı launcher paketine eklenmeden otomatik kurulum yapılamaz.";
        }

        if (!File.Exists(managedDependency))
        {
            return "UE4SSExperimentalPW bağımlılığı kurulu değil. Onaylı bağımlılık paketi gerekli.";
        }

        return string.Empty;
    }

    private IReadOnlyList<FileMapping> BuildMappings(string gameRoot)
    {
        List<FileMapping> mappings = new();
        AddFile(mappings, "Info.json", Path.Combine("Mods", "NativeMods", "UE4SS", "Mods", "PalTRUI", "Info.json"));
        AddFile(mappings, Path.Combine("LogicMods", "PalTRUI.pak"), Path.Combine("Pal", "Content", "Paks", "LogicMods", "PalTRUI.pak"));

        string sourceScripts = Path.Combine(payloadRoot, "Scripts");
        foreach (string source in Directory.EnumerateFiles(sourceScripts, "*.lua", SearchOption.AllDirectories))
        {
            string relativeScript = Path.GetRelativePath(sourceScripts, source);
            string relativeSource = Path.Combine("Scripts", relativeScript);
            string relativeDestination = Path.Combine("Mods", "NativeMods", "UE4SS", "Mods", "PalTRUI", "Scripts", relativeScript);
            mappings.Add(new FileMapping(source, Path.Combine(gameRoot, relativeDestination), relativeDestination));
        }

        return mappings;

        void AddFile(List<FileMapping> target, string relativeSource, string relativeDestination)
            => target.Add(new FileMapping(
                Path.Combine(payloadRoot, relativeSource),
                Path.Combine(gameRoot, relativeDestination),
                relativeDestination));
    }

    private static bool FilesMatch(string first, string second)
    {
        FileInfo firstInfo = new(first);
        FileInfo secondInfo = new(second);
        if (firstInfo.Length != secondInfo.Length)
        {
            return false;
        }

        using SHA256 sha256 = SHA256.Create();
        using FileStream firstStream = File.OpenRead(first);
        byte[] firstHash = sha256.ComputeHash(firstStream);
        using FileStream secondStream = File.OpenRead(second);
        byte[] secondHash = sha256.ComputeHash(secondStream);
        return firstHash.AsSpan().SequenceEqual(secondHash);
    }

    private static bool IsPalworldRunning()
        => Process.GetProcesses().Any(process =>
            process.ProcessName.Equals("Palworld-Win64-Shipping", StringComparison.OrdinalIgnoreCase) ||
            process.ProcessName.Equals("Palworld", StringComparison.OrdinalIgnoreCase));

    private static bool IsPalTRUIEnabled(string gameRoot)
    {
        string modsFile = GetModsFile(gameRoot);
        if (!File.Exists(modsFile))
        {
            return false;
        }

        return File.ReadLines(modsFile).Any(line =>
            line.Trim().Equals("PalTRUI : 1", StringComparison.OrdinalIgnoreCase));
    }

    private static void EnsurePalTRUIEnabled(
        string gameRoot,
        string backupRoot,
        ICollection<(string Destination, string? Backup)> changedFiles)
    {
        if (IsPalTRUIEnabled(gameRoot))
        {
            return;
        }

        string modsFile = GetModsFile(gameRoot);
        Directory.CreateDirectory(Path.GetDirectoryName(modsFile)!);
        string? backup = null;
        List<string> lines = new();
        if (File.Exists(modsFile))
        {
            lines.AddRange(File.ReadAllLines(modsFile));
            backup = Path.Combine(backupRoot, "Mods", "NativeMods", "UE4SS", "Mods", "mods.txt");
            Directory.CreateDirectory(Path.GetDirectoryName(backup)!);
            File.Copy(modsFile, backup, true);
        }

        int existing = lines.FindIndex(line =>
            line.TrimStart().StartsWith("PalTRUI ", StringComparison.OrdinalIgnoreCase));
        if (existing >= 0)
        {
            lines[existing] = "PalTRUI : 1";
        }
        else
        {
            int keybinds = lines.FindIndex(line =>
                line.TrimStart().StartsWith("Keybinds ", StringComparison.OrdinalIgnoreCase));
            if (keybinds >= 0)
            {
                lines.Insert(keybinds, "PalTRUI : 1");
            }
            else
            {
                lines.Add("PalTRUI : 1");
            }
        }

        string temporary = modsFile + ".paltr-new";
        File.WriteAllLines(temporary, lines);
        File.Move(temporary, modsFile, true);
        changedFiles.Add((modsFile, backup));
    }

    private static string GetModsFile(string gameRoot)
        => Path.Combine(gameRoot, "Mods", "NativeMods", "UE4SS", "Mods", "mods.txt");

    private static void RollBack(IEnumerable<(string Destination, string? Backup)> changedFiles)
    {
        foreach ((string destination, string? backup) in changedFiles.Reverse())
        {
            try
            {
                if (backup is not null && File.Exists(backup))
                {
                    File.Copy(backup, destination, true);
                }
                else if (File.Exists(destination))
                {
                    File.Delete(destination);
                }
            }
            catch
            {
                // İlk hatayı korumak için rollback hataları burada bastırılır.
            }
        }
    }

    private static InstallationSnapshot Blocked(
        string title,
        string detail,
        string? gameRoot = null,
        string? packageVersion = null)
        => new(InstallationState.Blocked, title, detail, gameRoot, packageVersion);

    private sealed record FileMapping(string Source, string Destination, string RelativeDestination);
}
