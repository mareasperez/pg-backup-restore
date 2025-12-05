using DbTool.Domain.Enums;

namespace DbTool.Domain.Entities;

/// <summary>
/// Represents a database connection configuration.
/// </summary>
public class DatabaseConnection
{
    public int Id { get; set; }
    
    /// <summary>
    /// Unique name for the database connection (e.g., "dev", "prod").
    /// </summary>
    public string Name { get; set; } = string.Empty;
    
    /// <summary>
    /// Database engine type.
    /// </summary>
    public DatabaseEngineType EngineType { get; set; }
    
    public string Host { get; set; } = string.Empty;
    
    public int Port { get; set; }
    
    public string DatabaseName { get; set; } = string.Empty;
    
    public string Username { get; set; } = string.Empty;
    
    /// <summary>
    /// Password stored in plain text for now. Consider encryption in production.
    /// </summary>
    public string Password { get; set; } = string.Empty;
    
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    
    public DateTime? UpdatedAt { get; set; }
    
    /// <summary>
    /// Navigation property to backups.
    /// </summary>
    public ICollection<Backup> Backups { get; set; } = new List<Backup>();
}
