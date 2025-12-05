using Dapper;
using Microsoft.Data.Sqlite;

namespace DbTool.Infrastructure.Data;

/// <summary>
/// SQLite database context for managing application configuration and metadata.
/// </summary>
public class AppDbContext : IDisposable
{
    private readonly SqliteConnection _connection;
    private readonly string _dbPath;

    public AppDbContext(string? dbPath = null)
    {
        _dbPath = dbPath ?? GetDefaultDbPath();

        // Ensure directory exists
        var directory = Path.GetDirectoryName(_dbPath);
        if (!string.IsNullOrEmpty(directory) && !Directory.Exists(directory))
        {
            Directory.CreateDirectory(directory);
        }

        _connection = new SqliteConnection($"Data Source={_dbPath}");
        _connection.Open();
        
        InitializeDatabase();
    }

    private static string GetDefaultDbPath()
    {
        var appDataPath = System.Environment.GetFolderPath(System.Environment.SpecialFolder.ApplicationData);
        return Path.Combine(appDataPath, "DbTool", "config.db");
    }

    private void InitializeDatabase()
    {
        var createDatabaseConnectionsTable = @"
            CREATE TABLE IF NOT EXISTS DatabaseConnections (
                Id INTEGER PRIMARY KEY AUTOINCREMENT,
                Name TEXT NOT NULL UNIQUE,
                EngineType INTEGER NOT NULL,
                Host TEXT NOT NULL,
                Port INTEGER NOT NULL,
                DatabaseName TEXT NOT NULL,
                Username TEXT NOT NULL,
                Password TEXT NOT NULL,
                CreatedAt TEXT NOT NULL,
                UpdatedAt TEXT
            );
        ";

        var createBackupsTable = @"
            CREATE TABLE IF NOT EXISTS Backups (
                Id INTEGER PRIMARY KEY AUTOINCREMENT,
                DatabaseConnectionId INTEGER NOT NULL,
                FilePath TEXT NOT NULL,
                FileSizeBytes INTEGER NOT NULL,
                Checksum TEXT,
                Status INTEGER NOT NULL,
                ErrorMessage TEXT,
                CreatedAt TEXT NOT NULL,
                FOREIGN KEY (DatabaseConnectionId) REFERENCES DatabaseConnections(Id) ON DELETE CASCADE
            );
        ";

        var createIndexes = @"
            CREATE INDEX IF NOT EXISTS IX_Backups_DatabaseConnectionId ON Backups(DatabaseConnectionId);
            CREATE INDEX IF NOT EXISTS IX_Backups_Status ON Backups(Status);
            CREATE INDEX IF NOT EXISTS IX_Backups_CreatedAt ON Backups(CreatedAt DESC);
        ";

        _connection.Execute(createDatabaseConnectionsTable);
        _connection.Execute(createBackupsTable);
        _connection.Execute(createIndexes);
    }

    public SqliteConnection Connection => _connection;

    public void Dispose()
    {
        _connection?.Dispose();
    }
}
