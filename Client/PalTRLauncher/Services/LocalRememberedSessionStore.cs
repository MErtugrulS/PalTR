using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using PalTRLauncher.Models;

namespace PalTRLauncher.Services;

public sealed class LocalRememberedSessionStore : IRememberedSessionStore
{
    private static readonly byte[] Entropy = Encoding.UTF8.GetBytes("PalTRLauncher.AccountSession.v1");
    private readonly string sessionFilePath;

    public LocalRememberedSessionStore(string? sessionFilePath = null)
    {
        string applicationData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        this.sessionFilePath = sessionFilePath ?? Path.Combine(applicationData, "PalTRLauncher", "session.json");
    }

    public AccountSession? Load()
    {
        try
        {
            if (!File.Exists(sessionFilePath))
            {
                return null;
            }

            byte[] encrypted = File.ReadAllBytes(sessionFilePath);
            byte[] json = ProtectedData.Unprotect(encrypted, Entropy, DataProtectionScope.CurrentUser);
            AccountSession? session = JsonSerializer.Deserialize<AccountSession>(json);
            return string.IsNullOrWhiteSpace(session?.RefreshToken) ? null : session;
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
        catch (CryptographicException)
        {
            Clear();
            return null;
        }
    }

    public void Save(AccountSession session)
    {
        try
        {
            string directory = Path.GetDirectoryName(sessionFilePath)!;
            Directory.CreateDirectory(directory);
            byte[] json = JsonSerializer.SerializeToUtf8Bytes(session);
            byte[] encrypted = ProtectedData.Protect(json, Entropy, DataProtectionScope.CurrentUser);
            File.WriteAllBytes(sessionFilePath, encrypted);
        }
        catch (IOException)
        {
        }
        catch (UnauthorizedAccessException)
        {
        }
        catch (CryptographicException)
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

}
