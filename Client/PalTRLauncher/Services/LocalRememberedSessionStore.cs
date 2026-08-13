using System.IO;
using System.Text.Json;

namespace PalTRLauncher.Services;

public sealed class LocalRememberedSessionStore : IRememberedSessionStore
{
    private readonly string sessionFilePath;

    public LocalRememberedSessionStore()
    {
        string applicationData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        sessionFilePath = Path.Combine(applicationData, "PalTRLauncher", "session.json");
    }

    public string? LoadAccountName()
    {
        try
        {
            if (!File.Exists(sessionFilePath))
            {
                return null;
            }

            RememberedSession? session = JsonSerializer.Deserialize<RememberedSession>(
                File.ReadAllText(sessionFilePath));
            return string.IsNullOrWhiteSpace(session?.AccountName)
                ? null
                : session.AccountName.Trim();
        }
        catch (IOException)
        {
            return null;
        }
        catch (UnauthorizedAccessException)
        {
            return null;
        }
        catch (JsonException)
        {
            return null;
        }
    }

    public void SaveAccountName(string accountName)
    {
        try
        {
            string directory = Path.GetDirectoryName(sessionFilePath)!;
            Directory.CreateDirectory(directory);
            string json = JsonSerializer.Serialize(new RememberedSession(accountName.Trim()));
            File.WriteAllText(sessionFilePath, json);
        }
        catch (IOException)
        {
        }
        catch (UnauthorizedAccessException)
        {
        }
    }

    public void Clear()
    {
        try
        {
            if (File.Exists(sessionFilePath))
            {
                File.Delete(sessionFilePath);
            }
        }
        catch (IOException)
        {
        }
        catch (UnauthorizedAccessException)
        {
        }
    }

    private sealed record RememberedSession(string AccountName);
}
