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
    private readonly Func<bool> isPalworldRunning;

    internal string DependencyRoot { get; }

    public LocalPalTRInstallationService(
        PalworldInstallLocator installLocator,
        string? applicationRoot = null,
        string? dependencyRoot = null,
        Func<bool>? isPalworldRunning = null)
    {
        this.installLocator = installLocator;
        string root = applicationRoot ?? AppContext.BaseDirectory;
        payloadRoot = Path.Combine(root, "Payload", "PalTRUI");
        DependencyRoot = dependencyRoot ?? Path.Combine(root, "Payload", "Dependencies");
        this.isPalworldRunning = isPalworldRunning ?? IsPalworldRunning;
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

        if (!TryValidateDependencyPayload(out string dependencyPayloadError))
        {
            return Blocked("Kurulum bileşenleri eksik", dependencyPayloadError, gameRoot, packageVersion);
        }

        string dependencyError = GetDependencyError(gameRoot);
        if (dependencyError.Length > 0)
        {
            return new InstallationSnapshot(
                InstallationState.InstallRequired,
                "PalTR bileşenleri kurulacak",
                $"{dependencyError} Launcher gerekli bileşenleri otomatik kuracak.",
                gameRoot,
                packageVersion);
        }

        string registrationError = GetManagedDependencyRegistrationError(gameRoot);
        if (registrationError.Length > 0)
        {
            return new InstallationSnapshot(
                InstallationState.InstallRequired,
                "UE4SS etkinleştirilecek",
                $"{registrationError} Launcher resmi Palworld mod kaydını onaracak.",
                gameRoot,
                packageVersion);
        }

        IReadOnlyList<FileMapping> mappings = BuildMappings(gameRoot);
        foreach (FileMapping mapping in mappings)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (!File.Exists(mapping.Destination) ||
                (!mapping.CopyOnlyIfMissing && !FilesMatch(mapping.Source, mapping.Destination)))
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
        if ((!inspection.CanInstall && !inspection.CanRepair) || inspection.GameRoot is null)
        {
            return new InstallationActionResult(false, inspection);
        }

        if (isPalworldRunning())
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
                // Kullanıcı ayar dosyalarını koru; diğer tüm PalTR/UE4SS dosyalarını
                // yeniden yazarak "Onar / Yeniden Kur" işlemini gerçek bir onarım yap.
                if (File.Exists(mapping.Destination) && mapping.CopyOnlyIfMissing)
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


            EnsureManagedDependencyRegistered(inspection.GameRoot, backupRoot, changedFiles);
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

    private bool TryValidateDependencyPayload(out string error)
    {
        string ue4ss = Path.Combine(DependencyRoot, "Mods", "NativeMods", "UE4SS", "UE4SS.dll");
        string managedDependency = Path.Combine(
            DependencyRoot,
            "Mods",
            "ManagedMods",
            "UE4SSExperimentalPW",
            "Info.json");
        if (!File.Exists(ue4ss) || !File.Exists(managedDependency))
        {
            error = "Launcher dağıtımında UE4SS veya UE4SSExperimentalPW payload'ı eksik. Launcher paketini yeniden indir.";
            return false;
        }

        error = string.Empty;
        return true;
    }

    private static string GetDependencyError(string gameRoot)
    {
        string ue4ss = Path.Combine(gameRoot, "Mods", "NativeMods", "UE4SS", "UE4SS.dll");
        string managedDependency = Path.Combine(gameRoot, "Mods", "ManagedMods", "UE4SSExperimentalPW", "Info.json");
        if (!File.Exists(ue4ss))
        {
            return "UE4SS kurulu değil.";
        }

        if (!File.Exists(managedDependency))
        {
            return "UE4SSExperimentalPW bağımlılığı kurulu değil.";
        }

        return string.Empty;
    }

    private static string GetManagedDependencyRegistrationError(string gameRoot)
    {
        string settingsPath = GetPalModSettingsFile(gameRoot);
        if (!File.Exists(settingsPath))
        {
            return "Palworld mod etkinleştirme ayarı bulunamadı.";
        }

        string[] lines = File.ReadAllLines(settingsPath);
        bool globallyEnabled = lines.Any(line =>
            line.Trim().Equals("bGlobalEnableMod=True", StringComparison.OrdinalIgnoreCase));
        bool dependencyEnabled = lines.Any(line =>
            line.Trim().Equals("ActiveModList=UE4SSExperimentalPW", StringComparison.OrdinalIgnoreCase));
        if (!globallyEnabled || !dependencyEnabled)
        {
            return "UE4SSExperimentalPW resmi mod listesinde etkin değil.";
        }

        if (!File.Exists(GetManagedDependencyManifestFile(gameRoot)))
        {
            return "UE4SSExperimentalPW kurulum manifesti eksik.";
        }

        return string.Empty;
    }

    private IReadOnlyList<FileMapping> BuildMappings(string gameRoot)
    {
        List<FileMapping> mappings = new();
        AddDependencyMappings(mappings, gameRoot);
        AddFile(mappings, "Info.json", Path.Combine("Mods", "NativeMods", "UE4SS", "Mods", "PalTRUI", "Info.json"));
        AddFile(mappings, Path.Combine("LogicMods", "PalTRUI.pak"), Path.Combine("Pal", "Content", "Paks", "LogicMods", "PalTRUI.pak"));

        string sourceScripts = Path.Combine(payloadRoot, "Scripts");
        foreach (string source in Directory.EnumerateFiles(sourceScripts, "*.lua", SearchOption.AllDirectories))
        {
            string relativeScript = Path.GetRelativePath(sourceScripts, source);
            string relativeSource = Path.Combine("Scripts", relativeScript);
            string relativeDestination = Path.Combine("Mods", "NativeMods", "UE4SS", "Mods", "PalTRUI", "Scripts", relativeScript);
            mappings.Add(new FileMapping(
                source,
                Path.Combine(gameRoot, relativeDestination),
                relativeDestination,
                false));
        }

        return mappings;

        void AddFile(List<FileMapping> target, string relativeSource, string relativeDestination)
            => target.Add(new FileMapping(
                Path.Combine(payloadRoot, relativeSource),
                Path.Combine(gameRoot, relativeDestination),
                relativeDestination,
                false));
    }

    private void AddDependencyMappings(ICollection<FileMapping> mappings, string gameRoot)
    {
        foreach (string source in Directory.EnumerateFiles(DependencyRoot, "*", SearchOption.AllDirectories))
        {
            string relative = Path.GetRelativePath(DependencyRoot, source);
            bool copyOnlyIfMissing = relative.Equals(
                    Path.Combine("Mods", "NativeMods", "UE4SS", "UE4SS-settings.ini"),
                    StringComparison.OrdinalIgnoreCase) ||
                relative.Equals(
                    Path.Combine("Mods", "NativeMods", "UE4SS", "Mods", "mods.json"),
                    StringComparison.OrdinalIgnoreCase) ||
                relative.Equals(
                    Path.Combine("Mods", "NativeMods", "UE4SS", "Mods", "mods.txt"),
                    StringComparison.OrdinalIgnoreCase);

            mappings.Add(new FileMapping(
                source,
                Path.Combine(gameRoot, relative),
                relative,
                copyOnlyIfMissing));
        }
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

    private void EnsureManagedDependencyRegistered(
        string gameRoot,
        string backupRoot,
        ICollection<(string Destination, string? Backup)> changedFiles)
    {
        EnsurePalModSettings(gameRoot, backupRoot, changedFiles);
        EnsureManagedDependencyManifest(gameRoot, backupRoot, changedFiles);
    }

    private static void EnsurePalModSettings(
        string gameRoot,
        string backupRoot,
        ICollection<(string Destination, string? Backup)> changedFiles)
    {
        string settingsPath = GetPalModSettingsFile(gameRoot);
        Directory.CreateDirectory(Path.GetDirectoryName(settingsPath)!);
        List<string> lines = File.Exists(settingsPath)
            ? File.ReadAllLines(settingsPath).ToList()
            : new List<string>();

        bool changed = false;
        if (!lines.Any(line => line.Trim().Equals("[PalModSettings]", StringComparison.OrdinalIgnoreCase)))
        {
            lines.Insert(0, "[PalModSettings]");
            changed = true;
        }

        changed |= SetSingleSetting(lines, "bGlobalEnableMod", "True");
        changed |= SetSingleSetting(lines, "ConfigVersion", "1.0", addOnlyIfMissing: true);

        string steamApps = Directory.GetParent(Directory.GetParent(gameRoot)!.FullName)!.FullName;
        string workshopRoot = Path.Combine(steamApps, "workshop", "content", "1623730");
        changed |= SetSingleSetting(lines, "WorkshopRootDir", workshopRoot, addOnlyIfMissing: true);

        if (!lines.Any(line =>
                line.Trim().Equals("ActiveModList=UE4SSExperimentalPW", StringComparison.OrdinalIgnoreCase)))
        {
            int lastActiveMod = lines.FindLastIndex(line =>
                line.TrimStart().StartsWith("ActiveModList=", StringComparison.OrdinalIgnoreCase));
            lines.Insert(lastActiveMod >= 0 ? lastActiveMod + 1 : lines.Count, "ActiveModList=UE4SSExperimentalPW");
            changed = true;
        }

        if (!changed)
        {
            return;
        }

        string? backup = BackUpFile(settingsPath, backupRoot, gameRoot);
        WriteAllLinesAtomically(settingsPath, lines);
        changedFiles.Add((settingsPath, backup));
    }

    private void EnsureManagedDependencyManifest(
        string gameRoot,
        string backupRoot,
        ICollection<(string Destination, string? Backup)> changedFiles)
    {
        string manifestPath = GetManagedDependencyManifestFile(gameRoot);
        if (File.Exists(manifestPath))
        {
            return;
        }

        List<string> files = Directory
            .EnumerateFiles(DependencyRoot, "*", SearchOption.AllDirectories)
            .Select(source => Path.GetRelativePath(DependencyRoot, source).Replace('\\', '/'))
            .Where(relative => !relative.EndsWith("/InstallManifest.json", StringComparison.OrdinalIgnoreCase))
            .OrderBy(relative => relative, StringComparer.OrdinalIgnoreCase)
            .ToList();
        List<string> directories = files
            .Select(relative => Path.GetDirectoryName(relative.Replace('/', Path.DirectorySeparatorChar)))
            .Where(directory => !string.IsNullOrWhiteSpace(directory))
            .Select(directory => directory!.Replace('\\', '/'))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .OrderBy(directory => directory, StringComparer.OrdinalIgnoreCase)
            .ToList();

        var manifest = new
        {
            Files = files,
            Dirs = directories,
            Backups = Array.Empty<string>(),
            WorkshopId = 3625223587,
            LastInstallTimeUtc = DateTime.UtcNow.ToString("O"),
            LastWorkshopUpdateTimeUtc = DateTime.UtcNow.ToString("O")
        };

        Directory.CreateDirectory(Path.GetDirectoryName(manifestPath)!);
        string? backup = BackUpFile(manifestPath, backupRoot, gameRoot);
        string temporary = manifestPath + ".paltr-new";
        File.WriteAllText(temporary, JsonSerializer.Serialize(manifest, new JsonSerializerOptions
        {
            WriteIndented = true
        }));
        File.Move(temporary, manifestPath, true);
        changedFiles.Add((manifestPath, backup));
    }

    private static bool SetSingleSetting(
        IList<string> lines,
        string key,
        string value,
        bool addOnlyIfMissing = false)
    {
        int index = -1;
        for (int current = 0; current < lines.Count; current++)
        {
            if (lines[current].TrimStart().StartsWith(key + "=", StringComparison.OrdinalIgnoreCase))
            {
                index = current;
                break;
            }
        }

        if (index < 0)
        {
            lines.Add($"{key}={value}");
            return true;
        }

        if (addOnlyIfMissing || lines[index].Trim().Equals($"{key}={value}", StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        lines[index] = $"{key}={value}";
        return true;
    }

    private static string? BackUpFile(string path, string backupRoot, string gameRoot)
    {
        if (!File.Exists(path))
        {
            return null;
        }

        string backup = Path.Combine(backupRoot, Path.GetRelativePath(gameRoot, path));
        Directory.CreateDirectory(Path.GetDirectoryName(backup)!);
        File.Copy(path, backup, true);
        return backup;
    }

    private static void WriteAllLinesAtomically(string path, IEnumerable<string> lines)
    {
        string temporary = path + ".paltr-new";
        File.WriteAllLines(temporary, lines);
        File.Move(temporary, path, true);
    }

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

    private static string GetPalModSettingsFile(string gameRoot)
        => Path.Combine(gameRoot, "Mods", "PalModSettings.ini");

    private static string GetManagedDependencyManifestFile(string gameRoot)
        => Path.Combine(gameRoot, "Mods", "ManagedMods", "UE4SSExperimentalPW", "InstallManifest.json");

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

    private sealed record FileMapping(
        string Source,
        string Destination,
        string RelativeDestination,
        bool CopyOnlyIfMissing);
}
