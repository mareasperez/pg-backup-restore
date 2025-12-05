using DbTool.Application.DTOs;

namespace DbTool.Application.Interfaces;

/// <summary>
/// Service interface for backup operations.
/// </summary>
public interface IBackupService
{
    /// <summary>
    /// Performs a backup of the specified database.
    /// </summary>
    Task<BackupResultDto> CreateBackupAsync(
        string databaseName, 
        string? outputDirectory = null,
        IProgress<string>? progress = null,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Lists all backups for a database.
    /// </summary>
    Task<IEnumerable<BackupInfoDto>> ListBackupsAsync(
        string databaseName,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets the latest backup for a database.
    /// </summary>
    Task<BackupInfoDto?> GetLatestBackupAsync(
        string databaseName,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Restores a database from a backup file.
    /// </summary>
    Task<RestoreResultDto> RestoreBackupAsync(
        string databaseName,
        string backupFilePath,
        IProgress<string>? progress = null,
        CancellationToken cancellationToken = default);
}

/// <summary>
/// DTO for backup information.
/// </summary>
public record BackupInfoDto(
    int Id,
    string FilePath,
    long FileSizeBytes,
    string Status,
    DateTime CreatedAt
);
