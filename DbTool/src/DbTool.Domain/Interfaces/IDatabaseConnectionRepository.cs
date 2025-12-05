using DbTool.Domain.Entities;

namespace DbTool.Domain.Interfaces;

/// <summary>
/// Repository interface for database connection persistence.
/// </summary>
public interface IDatabaseConnectionRepository
{
    /// <summary>
    /// Adds a new database connection.
    /// </summary>
    /// <returns>The ID of the created connection.</returns>
    Task<int> AddAsync(DatabaseConnection connection, CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets a database connection by its ID.
    /// </summary>
    Task<DatabaseConnection?> GetByIdAsync(int id, CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets a database connection by its name.
    /// </summary>
    Task<DatabaseConnection?> GetByNameAsync(string name, CancellationToken cancellationToken = default);

    /// <summary>
    /// Gets all database connections.
    /// </summary>
    Task<IEnumerable<DatabaseConnection>> GetAllAsync(CancellationToken cancellationToken = default);

    /// <summary>
    /// Updates an existing database connection.
    /// </summary>
    /// <returns>True if updated successfully, false otherwise.</returns>
    Task<bool> UpdateAsync(DatabaseConnection connection, CancellationToken cancellationToken = default);

    /// <summary>
    /// Deletes a database connection by its ID.
    /// </summary>
    /// <returns>True if deleted successfully, false otherwise.</returns>
    Task<bool> DeleteAsync(int id, CancellationToken cancellationToken = default);
}
