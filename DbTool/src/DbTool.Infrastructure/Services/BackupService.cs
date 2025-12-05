using DbTool.Application.DTOs;
using DbTool.Application.Interfaces;
using DbTool.Domain.Entities;
using DbTool.Domain.Enums;
using DbTool.Domain.Interfaces;
using DbTool.Infrastructure.Providers;

namespace DbTool.Infrastructure.Services;

/// <summary>
/// Implementation of IBackupService.
/// </summary>
public class BackupService : IBackupService
{
    private readonly IDatabaseConnectionRepository _connectionRepository;
    private readonly IBackupRepository _backupRepository;
    private readonly string _defaultBackupRoot;

    public BackupService(
        IDatabaseConnectionRepository connectionRepository,
        IBackupRepository backupRepository,
        string? backupRoot = null)
    {
        _connectionRepository = connectionRepository;
        _backupRepository = backupRepository;
        _defaultBackupRoot = backupRoot ?? Path.Combine(Directory.GetCurrentDirectory(), "backups");
    }

    public async Task<BackupResultDto> CreateBackupAsync(
        string databaseName, 
        string? outputDirectory = null,
        IProgress<string>? progress = null,
        CancellationToken cancellationToken = default)
    {
        // Get database connection
        var connection = await _connectionRepository.GetByNameAsync(databaseName, cancellationToken);
        if (connection == null)
        {
            throw new InvalidOperationException($"Database connection '{databaseName}' not found");
        }

        // Create output directory
        var backupDir = outputDirectory ?? Path.Combine(_defaultBackupRoot, databaseName, DateTime.UtcNow.ToString("yyyy-MM-dd-HH-mm-ss"));
        Directory.CreateDirectory(backupDir);

        var backupFilePath = Path.Combine(backupDir, $"{databaseName}.sql");

        // Create backup record
        var backup = new Backup
        {
            DatabaseConnectionId = connection.Id,
            FilePath = backupFilePath,
            Status = BackupStatus.InProgress,
            CreatedAt = DateTime.UtcNow
        };

        var backupId = await _backupRepository.AddAsync(backup, cancellationToken);

        try
        {
            // Perform backup
            var provider = ProviderFactory.CreateProvider(connection.EngineType);
            await provider.BackupAsync(connection, backupFilePath, progress, cancellationToken);

            // Update backup record
            var fileInfo = new FileInfo(backupFilePath);
            backup.Id = backupId;
            backup.FileSizeBytes = fileInfo.Length;
            backup.Status = BackupStatus.Success;
            await _backupRepository.UpdateAsync(backup, cancellationToken);

            return new BackupResultDto(true, backupFilePath, fileInfo.Length);
        }
        catch (Exception ex)
        {
            // Update backup record with error
            backup.Id = backupId;
            backup.Status = BackupStatus.Failed;
            backup.ErrorMessage = ex.Message;
            await _backupRepository.UpdateAsync(backup, cancellationToken);

            return new BackupResultDto(false, backupFilePath, 0, ex.Message);
        }
    }

    public async Task<IEnumerable<BackupInfoDto>> ListBackupsAsync(
        string databaseName,
        CancellationToken cancellationToken = default)
    {
        var connection = await _connectionRepository.GetByNameAsync(databaseName, cancellationToken);
        if (connection == null)
        {
            throw new InvalidOperationException($"Database connection '{databaseName}' not found");
        }

        var backups = await _backupRepository.GetByEnvironmentIdAsync(connection.Id, cancellationToken);
        return backups.Select(b => new BackupInfoDto(
            b.Id,
            b.FilePath,
            b.FileSizeBytes,
            b.Status.ToString(),
            b.CreatedAt
        ));
    }

    public async Task<BackupInfoDto?> GetLatestBackupAsync(
        string databaseName,
        CancellationToken cancellationToken = default)
    {
        var connection = await _connectionRepository.GetByNameAsync(databaseName, cancellationToken);
        if (connection == null)
        {
            throw new InvalidOperationException($"Database connection '{databaseName}' not found");
        }

        var backup = await _backupRepository.GetLatestSuccessfulAsync(connection.Id, cancellationToken);
        if (backup == null) return null;

        return new BackupInfoDto(
            backup.Id,
            backup.FilePath,
            backup.FileSizeBytes,
            backup.Status.ToString(),
            backup.CreatedAt
        );
    }

    public async Task<RestoreResultDto> RestoreBackupAsync(
        string databaseName,
        string backupFilePath,
        IProgress<string>? progress = null,
        CancellationToken cancellationToken = default)
    {
        // Validate backup file exists
        if (!File.Exists(backupFilePath))
        {
            return new RestoreResultDto(
                false,
                databaseName,
                backupFilePath,
                $"Backup file not found: {backupFilePath}"
            );
        }

        // Get database connection
        var connection = await _connectionRepository.GetByNameAsync(databaseName, cancellationToken);
        if (connection == null)
        {
            return new RestoreResultDto(
                false,
                databaseName,
                backupFilePath,
                $"Database connection '{databaseName}' not found"
            );
        }

        try
        {
            progress?.Report($"Starting restore to '{databaseName}' from {Path.GetFileName(backupFilePath)}...");

            // Perform restore
            var provider = ProviderFactory.CreateProvider(connection.EngineType);
            await provider.RestoreAsync(connection, backupFilePath, progress, cancellationToken);

            progress?.Report("✓ Restore completed successfully");

            return new RestoreResultDto(
                true,
                databaseName,
                backupFilePath
            );
        }
        catch (Exception ex)
        {
            return new RestoreResultDto(
                false,
                databaseName,
                backupFilePath,
                ex.Message
            );
        }
    }
}
