namespace DbTool.Domain.Enums;

/// <summary>
/// Status of a backup operation.
/// </summary>
public enum BackupStatus
{
    InProgress = 1,
    Success = 2,
    Failed = 3,
    Cancelled = 4
}
