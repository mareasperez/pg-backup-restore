namespace DbTool.Application.DTOs;

/// <summary>
/// DTO for backup operation result.
/// </summary>
public record BackupResultDto(
    bool Success,
    string FilePath,
    long FileSizeBytes,
    string? ErrorMessage = null
);
