using DbTool.Application.DTOs;

namespace DbTool.Application.Interfaces;

/// <summary>
/// Service interface for database connection management.
/// </summary>
public interface IDatabaseConnectionService
{
    /// <summary>
    /// Creates a new database connection.
    /// </summary>
    Task<int> CreateDatabaseConnectionAsync(CreateDatabaseConnectionDto dto, CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets all database connections.
    /// </summary>
    Task<IEnumerable<DatabaseConnectionDto>> GetAllDatabaseConnectionsAsync(CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets a database connection by name.
    /// </summary>
    Task<DatabaseConnectionDto?> GetDatabaseConnectionByNameAsync(string name, CancellationToken cancellationToken = default);

    /// <summary>
    /// Deletes a database connection by name.
    /// </summary>
    Task<bool> DeleteDatabaseConnectionAsync(string name, CancellationToken cancellationToken = default);

    /// <summary>
    /// Tests connection to a database.
    /// </summary>
    Task<bool> TestConnectionAsync(string name, CancellationToken cancellationToken = default);
}
