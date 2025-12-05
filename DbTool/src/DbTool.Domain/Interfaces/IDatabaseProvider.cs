using DbTool.Domain.Entities;

namespace DbTool.Domain.Interfaces;

/// <summary>
/// Interface for database-specific backup/restore operations.
/// Implement this interface for each supported database engine.
/// </summary>
public interface IDatabaseProvider
{
    /// <summary>
    /// The name of the database engine (e.g., "postgres", "mysql").
    /// </summary>
    string EngineName { get; }

    /// <summary>
    /// Performs a backup of the specified database connection.
    /// </summary>
    /// <param name="connection">The database connection configuration.</param>
    /// <param name="outputPath">The full path where the backup file should be created.</param>
    /// <param name="progress">Optional progress reporter.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    Task BackupAsync(
        DatabaseConnection connection, 
        string outputPath, 
        IProgress<string>? progress = null,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Restores a backup to the specified database connection.
    /// </summary>
    /// <param name="connection">The target database connection configuration.</param>
    /// <param name="backupPath">The full path to the backup file.</param>
    /// <param name="progress">Optional progress reporter.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    Task RestoreAsync(
        DatabaseConnection connection, 
        string backupPath, 
        IProgress<string>? progress = null,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Drops all tables in the specified database.
    /// </summary>
    /// <param name="connection">The database connection configuration.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    Task DropAllTablesAsync(DatabaseConnection connection, CancellationToken cancellationToken = default);

    /// <summary>
    /// Tests the connection to the database.
    /// </summary>
    /// <param name="connection">The database connection configuration.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>True if connection is successful, false otherwise.</returns>
    Task<bool> TestConnectionAsync(DatabaseConnection connection, CancellationToken cancellationToken = default);
}
