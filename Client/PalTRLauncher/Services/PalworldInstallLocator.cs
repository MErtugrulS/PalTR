using System.IO;
using System.Text.RegularExpressions;
using Microsoft.Win32;

namespace PalTRLauncher.Services;

public sealed class PalworldInstallLocator
{
    private const string PalworldAppId = "1623730";
    private readonly string? explicitGameRoot;

    public PalworldInstallLocator(string? explicitGameRoot = null)
    {
        this.explicitGameRoot = explicitGameRoot;
    }

    public string? FindGameRoot()
    {
        if (!string.IsNullOrWhiteSpace(explicitGameRoot))
        {
            string candidate = Path.GetFullPath(explicitGameRoot);
            return File.Exists(Path.Combine(candidate, "Palworld.exe")) ? candidate : null;
        }

        foreach (string steamRoot in FindSteamRoots())
        {
            foreach (string libraryRoot in FindLibraryRoots(steamRoot))
            {
                string manifestPath = Path.Combine(libraryRoot, "steamapps", $"appmanifest_{PalworldAppId}.acf");
                if (!File.Exists(manifestPath))
                {
                    continue;
                }

                string manifest = File.ReadAllText(manifestPath);
                Match installDir = Regex.Match(manifest, "\\\"installdir\\\"\\s+\\\"(?<value>[^\\\"]+)\\\"");
                if (!installDir.Success)
                {
                    continue;
                }

                string candidate = Path.GetFullPath(Path.Combine(
                    libraryRoot,
                    "steamapps",
                    "common",
                    installDir.Groups["value"].Value));
                if (File.Exists(Path.Combine(candidate, "Palworld.exe")))
                {
                    return candidate;
                }
            }
        }

        return null;
    }

    private static IEnumerable<string> FindSteamRoots()
    {
        HashSet<string> roots = new(StringComparer.OrdinalIgnoreCase);
        AddRegistryRoot(roots, Registry.CurrentUser, @"Software\Valve\Steam", "SteamPath");
        AddRegistryRoot(roots, Registry.LocalMachine, @"SOFTWARE\WOW6432Node\Valve\Steam", "InstallPath");

        string programFilesX86 = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86);
        if (!string.IsNullOrWhiteSpace(programFilesX86))
        {
            roots.Add(Path.Combine(programFilesX86, "Steam"));
        }

        return roots.Where(Directory.Exists);
    }

    private static void AddRegistryRoot(
        ISet<string> roots,
        RegistryKey hive,
        string keyPath,
        string valueName)
    {
        using RegistryKey? key = hive.OpenSubKey(keyPath);
        if (key?.GetValue(valueName) is string value && !string.IsNullOrWhiteSpace(value))
        {
            roots.Add(value.Replace('/', Path.DirectorySeparatorChar));
        }
    }

    private static IEnumerable<string> FindLibraryRoots(string steamRoot)
    {
        HashSet<string> libraries = new(StringComparer.OrdinalIgnoreCase) { steamRoot };
        string libraryFile = Path.Combine(steamRoot, "steamapps", "libraryfolders.vdf");
        if (!File.Exists(libraryFile))
        {
            return libraries;
        }

        string contents = File.ReadAllText(libraryFile);
        foreach (Match match in Regex.Matches(contents, "\\\"path\\\"\\s+\\\"(?<value>[^\\\"]+)\\\""))
        {
            string path = match.Groups["value"].Value.Replace("\\\\", "\\");
            if (Directory.Exists(path))
            {
                libraries.Add(path);
            }
        }

        return libraries;
    }
}
