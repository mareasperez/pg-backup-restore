namespace DbTool.Application.DTOs;

/// <summary>
/// DTO for restore operation results.
/// </summary>
public record RestoreResultDto(
    bool Success,
    string DatabaseName,
    string BackupFilePath,
    string? ErrorMessage = null
);
