using DbTool.Domain.Enums;

namespace DbTool.Domain.Entities;

/// <summary>
/// Represents a backup operation and its metadata.
/// </summary>
public class Backup
{
    public int Id { get; set; }
    
    public int DatabaseConnectionId { get; set; }
    
    /// <summary>
    /// Full path to the backup file.
    /// </summary>
    public string FilePath { get; set; } = string.Empty;
    
    /// <summary>
    /// Size of the backup file in bytes.
    /// </summary>
    public long FileSizeBytes { get; set; }
    
    /// <summary>
    /// CRC32 or SHA256 checksum for integrity verification.
    /// </summary>
    public string? Checksum { get; set; }
    
    /// <summary>
    /// Current status of the backup operation.
    /// </summary>
    public BackupStatus Status { get; set; } = BackupStatus.InProgress;
    
    /// <summary>
    /// Error message if backup failed.
    /// </summary>
    public string? ErrorMessage { get; set; }
    
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    
    /// <summary>
    /// Navigation property to database connection.
    /// </summary>
    public DatabaseConnection DatabaseConnection { get; set; } = null!;
}
