namespace DbTool.Application.Settings;

/// <summary>
/// Main configuration settings for DbTool.
/// </summary>
public class DbToolSettings
{
    public BackupSettings Backup { get; set; } = new();
    public DatabaseSettings Database { get; set; } = new();
}

/// <summary>
/// Backup-related settings.
/// </summary>
public class BackupSettings
{
    /// <summary>
    /// Enable gzip compression for backup files.
    /// Default: false
    /// </summary>
    public bool EnableCompression { get; set; } = false;

    /// <summary>
    /// Compression level: Optimal, Fastest, SmallestSize, NoCompression
    /// Default: Optimal
    /// </summary>
    public string CompressionLevel { get; set; } = "Optimal";

    /// <summary>
    /// Default directory for storing backups.
    /// Default: ./backups
    /// </summary>
    public string DefaultBackupDirectory { get; set; } = "./backups";
}

/// <summary>
/// Database configuration settings.
/// </summary>
public class DatabaseSettings
{
    /// <summary>
    /// Path to SQLite configuration database.
    /// If null, uses default location in AppData.
    /// </summary>
    public string? ConfigDatabasePath { get; set; }
}
