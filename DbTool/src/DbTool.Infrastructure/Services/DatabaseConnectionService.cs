using DbTool.Application.DTOs;
using DbTool.Application.Interfaces;
using DbTool.Domain.Entities;
using DbTool.Domain.Interfaces;
using DbTool.Infrastructure.Providers;
using FluentValidation;

namespace DbTool.Infrastructure.Services;

/// <summary>
/// Implementation of IDatabaseConnectionService.
/// </summary>
public class DatabaseConnectionService : IDatabaseConnectionService
{
    private readonly IDatabaseConnectionRepository _repository;
    private readonly IValidator<CreateDatabaseConnectionDto> _validator;

    public DatabaseConnectionService(
        IDatabaseConnectionRepository repository,
        IValidator<CreateDatabaseConnectionDto> validator)
    {
        _repository = repository;
        _validator = validator;
    }

    public async Task<int> CreateDatabaseConnectionAsync(CreateDatabaseConnectionDto dto, CancellationToken cancellationToken = default)
    {
        // Validate
        var validationResult = await _validator.ValidateAsync(dto, cancellationToken);
        if (!validationResult.IsValid)
        {
            var errors = string.Join(", ", validationResult.Errors.Select(e => e.ErrorMessage));
            throw new ValidationException($"Validation failed: {errors}");
        }

        // Check if connection with same name already exists
        var existing = await _repository.GetByNameAsync(dto.Name, cancellationToken);
        if (existing != null)
        {
            throw new InvalidOperationException($"Database connection '{dto.Name}' already exists");
        }

        // Map to entity
        var engineType = ProviderFactory.ParseEngineType(dto.Engine);
        var connection = new DatabaseConnection
        {
            Name = dto.Name,
            EngineType = engineType,
            Host = dto.Host,
            Port = dto.Port,
            DatabaseName = dto.DatabaseName,
            Username = dto.Username,
            Password = dto.Password,
            CreatedAt = DateTime.UtcNow
        };

        return await _repository.AddAsync(connection, cancellationToken);
    }

    public async Task<IEnumerable<DatabaseConnectionDto>> GetAllDatabaseConnectionsAsync(CancellationToken cancellationToken = default)
    {
        var connections = await _repository.GetAllAsync(cancellationToken);
        return connections.Select(c => new DatabaseConnectionDto(
            c.Id,
            c.Name,
            c.EngineType.ToString(),
            c.Host,
            c.Port,
            c.DatabaseName,
            c.Username,
            c.CreatedAt
        ));
    }

    public async Task<DatabaseConnectionDto?> GetDatabaseConnectionByNameAsync(string name, CancellationToken cancellationToken = default)
    {
        var connection = await _repository.GetByNameAsync(name, cancellationToken);
        if (connection == null) return null;

        return new DatabaseConnectionDto(
            connection.Id,
            connection.Name,
            connection.EngineType.ToString(),
            connection.Host,
            connection.Port,
            connection.DatabaseName,
            connection.Username,
            connection.CreatedAt
        );
    }

    public async Task<bool> DeleteDatabaseConnectionAsync(string name, CancellationToken cancellationToken = default)
    {
        var connection = await _repository.GetByNameAsync(name, cancellationToken);
        if (connection == null) return false;

        return await _repository.DeleteAsync(connection.Id, cancellationToken);
    }

    public async Task<bool> TestConnectionAsync(string name, CancellationToken cancellationToken = default)
    {
        var connection = await _repository.GetByNameAsync(name, cancellationToken);
        if (connection == null)
        {
            throw new InvalidOperationException($"Database connection '{name}' not found");
        }

        var provider = ProviderFactory.CreateProvider(connection.EngineType);
        return await provider.TestConnectionAsync(connection, cancellationToken);
    }
}
