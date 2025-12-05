namespace DbTool.Application.DTOs;

/// <summary>
/// DTO for creating a new database connection.
/// </summary>
public record CreateDatabaseConnectionDto(
    string Name,
    string Engine,
    string Host,
    int Port,
    string DatabaseName,
    string Username,
    string Password
);
