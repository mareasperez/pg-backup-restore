using DbTool.Domain.Entities;

namespace DbTool.Domain.Interfaces;

/// <summary>
/// Repository interface for backup metadata persistence.
/// </summary>
public interface IBackupRepository
{
    /// <summary>
    /// Adds a new backup record.
    /// </summary>
    /// <returns>The ID of the created backup.</returns>
    Task<int> AddAsync(Backup backup, CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets a backup by its ID.
    /// </summary>
    Task<Backup?> GetByIdAsync(int id, CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets all backups for a specific environment.
    /// </summary>
    Task<IEnumerable<Backup>> GetByEnvironmentIdAsync(int environmentId, CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets the most recent successful backup for an environment.
    /// </summary>
    Task<Backup?> GetLatestSuccessfulAsync(int environmentId, CancellationToken cancellationToken = default);

    /// <summary>
    /// Updates an existing backup record.
    /// </summary>
    /// <returns>True if updated successfully, false otherwise.</returns>
    Task<bool> UpdateAsync(Backup backup, CancellationToken cancellationToken = default);

    /// <summary>
    /// Deletes a backup record by its ID.
    /// </summary>
    /// <returns>True if deleted successfully, false otherwise.</returns>
    Task<bool> DeleteAsync(int id, CancellationToken cancellationToken = default);
}
