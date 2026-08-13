using Microsoft.Data.Sqlite;

namespace PalTR.Accounts;

public sealed record AccountRecord(long Id, string Username, string Email, string PasswordHash, bool EmailVerified);
public sealed record SessionRecord(long AccountId, string Username, string Email, string AccessTokenHash,
    DateTimeOffset AccessExpiresAt, string RefreshTokenHash, DateTimeOffset RefreshExpiresAt);

public sealed class AccountStore
{
    private readonly string connectionString;

    public AccountStore(IConfiguration configuration, IWebHostEnvironment environment)
    {
        AccountOptions options = configuration.GetSection("AccountService").Get<AccountOptions>() ?? new();
        string path = Path.IsPathRooted(options.DatabasePath)
            ? options.DatabasePath
            : Path.Combine(environment.ContentRootPath, options.DatabasePath);
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);
        connectionString = new SqliteConnectionStringBuilder
        {
            DataSource = path,
            Mode = SqliteOpenMode.ReadWriteCreate
        }.ToString();
    }

    public async Task InitializeAsync()
    {
        await using SqliteConnection connection = await OpenAsync();
        await using SqliteCommand command = connection.CreateCommand();
        command.CommandText = """
            PRAGMA journal_mode = WAL;
            CREATE TABLE IF NOT EXISTS accounts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                username TEXT NOT NULL,
                normalized_username TEXT NOT NULL UNIQUE,
                email TEXT NOT NULL,
                normalized_email TEXT NOT NULL UNIQUE,
                password_hash TEXT NOT NULL,
                email_verified INTEGER NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS email_verifications (
                account_id INTEGER PRIMARY KEY,
                token_hash TEXT NOT NULL UNIQUE,
                expires_at TEXT NOT NULL,
                FOREIGN KEY(account_id) REFERENCES accounts(id) ON DELETE CASCADE
            );
            CREATE TABLE IF NOT EXISTS sessions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                account_id INTEGER NOT NULL,
                access_token_hash TEXT NOT NULL UNIQUE,
                access_expires_at TEXT NOT NULL,
                refresh_token_hash TEXT NOT NULL UNIQUE,
                refresh_expires_at TEXT NOT NULL,
                revoked_at TEXT NULL,
                created_at TEXT NOT NULL,
                FOREIGN KEY(account_id) REFERENCES accounts(id) ON DELETE CASCADE
            );
            CREATE INDEX IF NOT EXISTS idx_sessions_account ON sessions(account_id);
            """;
        await command.ExecuteNonQueryAsync();
    }

    public async Task<AccountRecord?> FindAccountAsync(string identifier)
    {
        await using SqliteConnection connection = await OpenAsync();
        await using SqliteCommand command = connection.CreateCommand();
        command.CommandText = """
            SELECT id, username, email, password_hash, email_verified
            FROM accounts WHERE normalized_username = $value OR normalized_email = $value LIMIT 1;
            """;
        command.Parameters.AddWithValue("$value", Normalize(identifier));
        await using SqliteDataReader reader = await command.ExecuteReaderAsync();
        return await reader.ReadAsync()
            ? new(reader.GetInt64(0), reader.GetString(1), reader.GetString(2), reader.GetString(3), reader.GetBoolean(4))
            : null;
    }

    public async Task<AccountRecord?> CreateAccountAsync(string username, string email, string passwordHash)
    {
        try
        {
            await using SqliteConnection connection = await OpenAsync();
            await using SqliteCommand command = connection.CreateCommand();
            command.CommandText = """
                INSERT INTO accounts(username, normalized_username, email, normalized_email, password_hash, created_at)
                VALUES($username, $normalizedUsername, $email, $normalizedEmail, $passwordHash, $createdAt);
                SELECT last_insert_rowid();
                """;
            command.Parameters.AddWithValue("$username", username);
            command.Parameters.AddWithValue("$normalizedUsername", Normalize(username));
            command.Parameters.AddWithValue("$email", email);
            command.Parameters.AddWithValue("$normalizedEmail", Normalize(email));
            command.Parameters.AddWithValue("$passwordHash", passwordHash);
            command.Parameters.AddWithValue("$createdAt", DateTimeOffset.UtcNow.ToString("O"));
            long id = (long)(await command.ExecuteScalarAsync())!;
            return new(id, username, email, passwordHash, false);
        }
        catch (SqliteException ex) when (ex.SqliteErrorCode == 19) { return null; }
    }

    public async Task SaveVerificationAsync(long accountId, string tokenHash, DateTimeOffset expiresAt)
    {
        await using SqliteConnection connection = await OpenAsync();
        await using SqliteCommand command = connection.CreateCommand();
        command.CommandText = """
            INSERT INTO email_verifications(account_id, token_hash, expires_at) VALUES($accountId, $hash, $expires)
            ON CONFLICT(account_id) DO UPDATE SET token_hash = excluded.token_hash, expires_at = excluded.expires_at;
            """;
        command.Parameters.AddWithValue("$accountId", accountId);
        command.Parameters.AddWithValue("$hash", tokenHash);
        command.Parameters.AddWithValue("$expires", expiresAt.ToString("O"));
        await command.ExecuteNonQueryAsync();
    }

    public async Task<bool> VerifyEmailAsync(string tokenHash)
    {
        await using SqliteConnection connection = await OpenAsync();
        await using SqliteTransaction transaction = (SqliteTransaction)await connection.BeginTransactionAsync();
        await using SqliteCommand find = connection.CreateCommand();
        find.Transaction = transaction;
        find.CommandText = "SELECT account_id, expires_at FROM email_verifications WHERE token_hash = $hash LIMIT 1;";
        find.Parameters.AddWithValue("$hash", tokenHash);
        await using SqliteDataReader reader = await find.ExecuteReaderAsync();
        if (!await reader.ReadAsync() || DateTimeOffset.Parse(reader.GetString(1)) <= DateTimeOffset.UtcNow)
            return false;
        long accountId = reader.GetInt64(0);
        await reader.DisposeAsync();
        await using SqliteCommand update = connection.CreateCommand();
        update.Transaction = transaction;
        update.CommandText = "UPDATE accounts SET email_verified = 1 WHERE id = $id; DELETE FROM email_verifications WHERE account_id = $id;";
        update.Parameters.AddWithValue("$id", accountId);
        await update.ExecuteNonQueryAsync();
        await transaction.CommitAsync();
        return true;
    }

    public async Task CreateSessionAsync(long accountId, string accessHash, DateTimeOffset accessExpires,
        string refreshHash, DateTimeOffset refreshExpires)
    {
        await using SqliteConnection connection = await OpenAsync();
        await using SqliteCommand command = connection.CreateCommand();
        command.CommandText = """
            INSERT INTO sessions(account_id, access_token_hash, access_expires_at, refresh_token_hash,
                refresh_expires_at, created_at) VALUES($account, $access, $accessExpires, $refresh, $refreshExpires, $created);
            """;
        command.Parameters.AddWithValue("$account", accountId);
        command.Parameters.AddWithValue("$access", accessHash);
        command.Parameters.AddWithValue("$accessExpires", accessExpires.ToString("O"));
        command.Parameters.AddWithValue("$refresh", refreshHash);
        command.Parameters.AddWithValue("$refreshExpires", refreshExpires.ToString("O"));
        command.Parameters.AddWithValue("$created", DateTimeOffset.UtcNow.ToString("O"));
        await command.ExecuteNonQueryAsync();
    }

    public Task<SessionRecord?> FindSessionByRefreshAsync(string refreshHash)
        => FindSessionAsync("refresh_token_hash", refreshHash, true);
    public Task<SessionRecord?> FindSessionByAccessAsync(string accessHash)
        => FindSessionAsync("access_token_hash", accessHash, false);

    public async Task RevokeSessionAsync(string refreshHash)
    {
        await using SqliteConnection connection = await OpenAsync();
        await using SqliteCommand command = connection.CreateCommand();
        command.CommandText = "UPDATE sessions SET revoked_at = $now WHERE refresh_token_hash = $hash AND revoked_at IS NULL;";
        command.Parameters.AddWithValue("$now", DateTimeOffset.UtcNow.ToString("O"));
        command.Parameters.AddWithValue("$hash", refreshHash);
        await command.ExecuteNonQueryAsync();
    }

    private async Task<SessionRecord?> FindSessionAsync(string column, string hash, bool requireRefreshValidity)
    {
        await using SqliteConnection connection = await OpenAsync();
        await using SqliteCommand command = connection.CreateCommand();
        command.CommandText = $"""
            SELECT a.id, a.username, a.email, s.access_token_hash, s.access_expires_at,
                   s.refresh_token_hash, s.refresh_expires_at
            FROM sessions s JOIN accounts a ON a.id = s.account_id
            WHERE s.{column} = $hash AND s.revoked_at IS NULL LIMIT 1;
            """;
        command.Parameters.AddWithValue("$hash", hash);
        await using SqliteDataReader reader = await command.ExecuteReaderAsync();
        if (!await reader.ReadAsync()) return null;
        SessionRecord session = new(reader.GetInt64(0), reader.GetString(1), reader.GetString(2), reader.GetString(3),
            DateTimeOffset.Parse(reader.GetString(4)), reader.GetString(5), DateTimeOffset.Parse(reader.GetString(6)));
        DateTimeOffset expiry = requireRefreshValidity ? session.RefreshExpiresAt : session.AccessExpiresAt;
        return expiry > DateTimeOffset.UtcNow ? session : null;
    }

    private async Task<SqliteConnection> OpenAsync()
    {
        SqliteConnection connection = new(connectionString);
        await connection.OpenAsync();
        await using SqliteCommand pragma = connection.CreateCommand();
        pragma.CommandText = "PRAGMA foreign_keys = ON;";
        await pragma.ExecuteNonQueryAsync();
        return connection;
    }

    private static string Normalize(string value) => value.Trim().ToUpperInvariant();
}
