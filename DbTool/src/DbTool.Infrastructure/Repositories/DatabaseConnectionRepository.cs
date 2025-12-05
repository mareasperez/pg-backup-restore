using Dapper;
using DbTool.Domain.Entities;
using DbTool.Domain.Enums;
using DbTool.Domain.Interfaces;
using DbTool.Infrastructure.Data;

namespace DbTool.Infrastructure.Repositories;

/// <summary>
/// SQLite implementation of IDatabaseConnectionRepository.
/// </summary>
public class DatabaseConnectionRepository : IDatabaseConnectionRepository
{
    private readonly AppDbContext _context;

    public DatabaseConnectionRepository(AppDbContext context)
    {
        _context = context;
    }

    public async Task<int> AddAsync(DatabaseConnection connection, CancellationToken cancellationToken = default)
    {
        var sql = @"
            INSERT INTO DatabaseConnections (Name, EngineType, Host, Port, DatabaseName, Username, Password, CreatedAt, UpdatedAt)
            VALUES (@Name, @EngineType, @Host, @Port, @DatabaseName, @Username, @Password, @CreatedAt, @UpdatedAt);
            SELECT last_insert_rowid();
        ";

        return await _context.Connection.ExecuteScalarAsync<int>(sql, new
        {
            connection.Name,
            EngineType = (int)connection.EngineType,
            connection.Host,
            connection.Port,
            connection.DatabaseName,
            connection.Username,
            connection.Password,
            CreatedAt = connection.CreatedAt.ToString("O"),
            UpdatedAt = connection.UpdatedAt?.ToString("O")
        });
    }

    public async Task<DatabaseConnection?> GetByIdAsync(int id, CancellationToken cancellationToken = default)
    {
        var sql = "SELECT * FROM DatabaseConnections WHERE Id = @Id";
        var result = await _context.Connection.QuerySingleOrDefaultAsync<DatabaseConnectionDto>(sql, new { Id = id });
        return result != null ? MapToEntity(result) : null;
    }

    public async Task<DatabaseConnection?> GetByNameAsync(string name, CancellationToken cancellationToken = default)
    {
        var sql = "SELECT * FROM DatabaseConnections WHERE Name = @Name";
        var result = await _context.Connection.QuerySingleOrDefaultAsync<DatabaseConnectionDto>(sql, new { Name = name });
        return result != null ? MapToEntity(result) : null;
    }

    public async Task<IEnumerable<DatabaseConnection>> GetAllAsync(CancellationToken cancellationToken = default)
    {
        var sql = "SELECT * FROM DatabaseConnections ORDER BY Name";
        var results = await _context.Connection.QueryAsync<DatabaseConnectionDto>(sql);
        return results.Select(MapToEntity);
    }

    public async Task<bool> UpdateAsync(DatabaseConnection connection, CancellationToken cancellationToken = default)
    {
        var sql = @"
            UPDATE DatabaseConnections 
            SET EngineType = @EngineType, Host = @Host, Port = @Port, 
                DatabaseName = @DatabaseName, Username = @Username, Password = @Password,
                UpdatedAt = @UpdatedAt
            WHERE Id = @Id
        ";

        var rowsAffected = await _context.Connection.ExecuteAsync(sql, new
        {
            connection.Id,
            EngineType = (int)connection.EngineType,
            connection.Host,
            connection.Port,
            connection.DatabaseName,
            connection.Username,
            connection.Password,
            UpdatedAt = DateTime.UtcNow.ToString("O")
        });

        return rowsAffected > 0;
    }

    public async Task<bool> DeleteAsync(int id, CancellationToken cancellationToken = default)
    {
        var sql = "DELETE FROM DatabaseConnections WHERE Id = @Id";
        var rowsAffected = await _context.Connection.ExecuteAsync(sql, new { Id = id });
        return rowsAffected > 0;
    }

    private static DatabaseConnection MapToEntity(DatabaseConnectionDto dto)
    {
        return new DatabaseConnection
        {
            Id = dto.Id,
            Name = dto.Name,
            EngineType = (DatabaseEngineType)dto.EngineType,
            Host = dto.Host,
            Port = dto.Port,
            DatabaseName = dto.DatabaseName,
            Username = dto.Username,
            Password = dto.Password,
            CreatedAt = DateTime.Parse(dto.CreatedAt),
            UpdatedAt = string.IsNullOrEmpty(dto.UpdatedAt) ? null : DateTime.Parse(dto.UpdatedAt)
        };
    }

    // Internal DTO for Dapper mapping
    private class DatabaseConnectionDto
    {
        public int Id { get; set; }
        public string Name { get; set; } = string.Empty;
        public int EngineType { get; set; }
        public string Host { get; set; } = string.Empty;
        public int Port { get; set; }
        public string DatabaseName { get; set; } = string.Empty;
        public string Username { get; set; } = string.Empty;
        public string Password { get; set; } = string.Empty;
        public string CreatedAt { get; set; } = string.Empty;
        public string? UpdatedAt { get; set; }
    }
}
