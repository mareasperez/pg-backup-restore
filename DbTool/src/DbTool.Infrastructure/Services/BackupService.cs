using System.IO.Compression;
using DbTool.Application.DTOs;
using DbTool.Application.Interfaces;
using DbTool.Application.Settings;
using DbTool.Domain.Entities;
using DbTool.Domain.Enums;
using DbTool.Domain.Interfaces;
using DbTool.Infrastructure.Providers;
using Microsoft.Extensions.Options;

namespace DbTool.Infrastructure.Services;

/// <summary>
/// Implementation of IBackupService with compression support.
/// </summary>
public class BackupService : IBackupService
{
    private readonly IDatabaseConnectionRepository _connectionRepository;
    private readonly IBackupRepository _backupRepository;
    private readonly ICompressionService _compressionService;
    private readonly DbToolSettings _settings;
    private readonly string _defaultBackupRoot;

    public BackupService(
        IDatabaseConnectionRepository connectionRepository,
        IBackupRepository backupRepository,
        ICompressionService compressionService,
        IOptions<DbToolSettings> options)
    {
        _connectionRepository = connectionRepository;
        _backupRepository = backupRepository;
        _compressionService = compressionService;
        _settings = options.Value;
        _defaultBackupRoot = _settings.Backup.DefaultBackupDirectory;
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
        var finalFilePath = backupFilePath;

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

            var fileInfo = new FileInfo(backupFilePath);
            var originalSize = fileInfo.Length;

            // Compress if enabled
            if (_settings.Backup.EnableCompression)
            {
                progress?.Report("Compressing backup...");
                
                var compressedPath = backupFilePath + ".gz";
                var compressionLevel = ParseCompressionLevel(_settings.Backup.CompressionLevel);
                
                await _compressionService.CompressFileAsync(backupFilePath, compressedPath, compressionLevel, cancellationToken);
                
                // Delete original uncompressed file
                File.Delete(backupFilePath);
                
                finalFilePath = compressedPath;
                var compressedInfo = new FileInfo(compressedPath);
                var compressedSize = compressedInfo.Length;
                var reduction = (1 - (double)compressedSize / originalSize) * 100;
                
                progress?.Report($"✓ Compressed: {FormatBytes(originalSize)} → {FormatBytes(compressedSize)} ({reduction:F1}% reduction)");
            }

            // Update backup record
            var finalFileInfo = new FileInfo(finalFilePath);
            backup.Id = backupId;
            backup.FilePath = finalFilePath;
            backup.FileSizeBytes = finalFileInfo.Length;
            backup.Status = BackupStatus.Success;
            await _backupRepository.UpdateAsync(backup, cancellationToken);

            return new BackupResultDto(true, finalFilePath, finalFileInfo.Length);
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

        string? tempDecompressedFile = null;

        try
        {
            progress?.Report($"Starting restore to '{databaseName}' from {Path.GetFileName(backupFilePath)}...");

            var sqlFilePath = backupFilePath;

            // Check if file is compressed
            if (_compressionService.IsCompressed(backupFilePath))
            {
                progress?.Report("Decompressing backup...");
                
                tempDecompressedFile = Path.Combine(Path.GetTempPath(), $"{Guid.NewGuid()}.sql");
                await _compressionService.DecompressFileAsync(backupFilePath, tempDecompressedFile, cancellationToken);
                
                sqlFilePath = tempDecompressedFile;
                progress?.Report("✓ Decompression complete");
            }

            // Perform restore
            var provider = ProviderFactory.CreateProvider(connection.EngineType);
            await provider.RestoreAsync(connection, sqlFilePath, progress, cancellationToken);

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
        finally
        {
            // Clean up temp file
            if (tempDecompressedFile != null && File.Exists(tempDecompressedFile))
            {
                try
                {
                    File.Delete(tempDecompressedFile);
                }
                catch
                {
                    // Ignore cleanup errors
                }
            }
        }
    }

    private static CompressionLevel ParseCompressionLevel(string level)
    {
        return level.ToLowerInvariant() switch
        {
            "fastest" => CompressionLevel.Fastest,
            "optimal" => CompressionLevel.Optimal,
            "smallestsize" => CompressionLevel.SmallestSize,
            "nocompression" => CompressionLevel.NoCompression,
            _ => CompressionLevel.Optimal
        };
    }

    private static string FormatBytes(long bytes)
    {
        string[] sizes = { "B", "KB", "MB", "GB" };
        double len = bytes;
        int order = 0;
        while (len >= 1024 && order < sizes.Length - 1)
        {
            order++;
            len = len / 1024;
        }
        return $"{len:0.##} {sizes[order]}";
    }
}
