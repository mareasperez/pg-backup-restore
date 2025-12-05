using Dapper;
using DbTool.Domain.Entities;
using DbTool.Domain.Enums;
using DbTool.Domain.Interfaces;
using DbTool.Infrastructure.Data;

namespace DbTool.Infrastructure.Repositories;

/// <summary>
/// SQLite implementation of IBackupRepository.
/// </summary>
public class BackupRepository : IBackupRepository
{
    private readonly AppDbContext _context;

    public BackupRepository(AppDbContext context)
    {
        _context = context;
    }

    public async Task<int> AddAsync(Backup backup, CancellationToken cancellationToken = default)
    {
        var sql = @"
            INSERT INTO Backups (DatabaseConnectionId, FilePath, FileSizeBytes, Checksum, Status, ErrorMessage, CreatedAt)
            VALUES (@DatabaseConnectionId, @FilePath, @FileSizeBytes, @Checksum, @Status, @ErrorMessage, @CreatedAt);
            SELECT last_insert_rowid();
        ";

        return await _context.Connection.ExecuteScalarAsync<int>(sql, new
        {
            backup.DatabaseConnectionId,
            backup.FilePath,
            backup.FileSizeBytes,
            backup.Checksum,
            Status = (int)backup.Status,
            backup.ErrorMessage,
            CreatedAt = backup.CreatedAt.ToString("O")
        });
    }

    public async Task<Backup?> GetByIdAsync(int id, CancellationToken cancellationToken = default)
    {
        var sql = "SELECT * FROM Backups WHERE Id = @Id";
        var result = await _context.Connection.QuerySingleOrDefaultAsync<BackupDto>(sql, new { Id = id });
        return result != null ? MapToEntity(result) : null;
    }

    public async Task<IEnumerable<Backup>> GetByEnvironmentIdAsync(int environmentId, CancellationToken cancellationToken = default)
    {
        var sql = "SELECT * FROM Backups WHERE DatabaseConnectionId = @DatabaseConnectionId ORDER BY CreatedAt DESC";
        var results = await _context.Connection.QueryAsync<BackupDto>(sql, new { DatabaseConnectionId = environmentId });
        return results.Select(MapToEntity);
    }

    public async Task<Backup?> GetLatestSuccessfulAsync(int environmentId, CancellationToken cancellationToken = default)
    {
        var sql = @"
            SELECT * FROM Backups 
            WHERE DatabaseConnectionId = @DatabaseConnectionId AND Status = @Status
            ORDER BY CreatedAt DESC 
            LIMIT 1
        ";
        var result = await _context.Connection.QuerySingleOrDefaultAsync<BackupDto>(sql, new 
        { 
            DatabaseConnectionId = environmentId,
            Status = (int)BackupStatus.Success
        });
        return result != null ? MapToEntity(result) : null;
    }

    public async Task<bool> UpdateAsync(Backup backup, CancellationToken cancellationToken = default)
    {
        var sql = @"
            UPDATE Backups 
            SET FilePath = @FilePath, FileSizeBytes = @FileSizeBytes, Checksum = @Checksum,
                Status = @Status, ErrorMessage = @ErrorMessage
            WHERE Id = @Id
        ";

        var rowsAffected = await _context.Connection.ExecuteAsync(sql, new
        {
            backup.Id,
            backup.FilePath,
            backup.FileSizeBytes,
            backup.Checksum,
            Status = (int)backup.Status,
            backup.ErrorMessage
        });

        return rowsAffected > 0;
    }

    public async Task<bool> DeleteAsync(int id, CancellationToken cancellationToken = default)
    {
        var sql = "DELETE FROM Backups WHERE Id = @Id";
        var rowsAffected = await _context.Connection.ExecuteAsync(sql, new { Id = id });
        return rowsAffected > 0;
    }

    private static Backup MapToEntity(BackupDto dto)
    {
        return new Backup
        {
            Id = dto.Id,
            DatabaseConnectionId = dto.DatabaseConnectionId,
            FilePath = dto.FilePath,
            FileSizeBytes = dto.FileSizeBytes,
            Checksum = dto.Checksum,
            Status = (BackupStatus)dto.Status,
            ErrorMessage = dto.ErrorMessage,
            CreatedAt = DateTime.Parse(dto.CreatedAt)
        };
    }

    // Internal DTO for Dapper mapping
    private class BackupDto
    {
        public int Id { get; set; }
        public int DatabaseConnectionId { get; set; }
        public string FilePath { get; set; } = string.Empty;
        public long FileSizeBytes { get; set; }
        public string? Checksum { get; set; }
        public int Status { get; set; }
        public string? ErrorMessage { get; set; }
        public string CreatedAt { get; set; } = string.Empty;
    }
}
