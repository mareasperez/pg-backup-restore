namespace DbTool.Application.DTOs;

/// <summary>
/// DTO for database connection information.
/// </summary>
public record DatabaseConnectionDto(
    int Id,
    string Name,
    string Engine,
    string Host,
    int Port,
    string DatabaseName,
    string Username,
    DateTime CreatedAt
);
