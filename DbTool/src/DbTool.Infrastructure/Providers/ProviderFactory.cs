using DbTool.Domain.Enums;
using DbTool.Domain.Interfaces;

namespace DbTool.Infrastructure.Providers;

/// <summary>
/// Factory for creating database provider instances based on engine type.
/// </summary>
public static class ProviderFactory
{
    /// <summary>
    /// Creates a provider instance for the specified database engine.
    /// </summary>
    public static IDatabaseProvider CreateProvider(DatabaseEngineType engineType)
    {
        return engineType switch
        {
            DatabaseEngineType.PostgreSQL => new PostgresProvider(),
            DatabaseEngineType.MySQL => new MySqlProvider(),
            DatabaseEngineType.SQLServer => new SqlServerProvider(),
            DatabaseEngineType.MariaDB => new MySqlProvider(), // MariaDB uses MySQL protocol
            _ => throw new NotSupportedException($"Database engine '{engineType}' is not supported")
        };
    }

    /// <summary>
    /// Creates a provider instance from a string engine name.
    /// </summary>
    public static IDatabaseProvider CreateProvider(string engineName)
    {
        var engineType = ParseEngineType(engineName);
        return CreateProvider(engineType);
    }

    /// <summary>
    /// Parses a string engine name to DatabaseEngineType.
    /// </summary>
    public static DatabaseEngineType ParseEngineType(string engineName)
    {
        return engineName.ToLowerInvariant() switch
        {
            "postgres" or "postgresql" => DatabaseEngineType.PostgreSQL,
            "mysql" => DatabaseEngineType.MySQL,
            "sqlserver" or "mssql" => DatabaseEngineType.SQLServer,
            "mariadb" => DatabaseEngineType.MariaDB,
            _ => throw new ArgumentException($"Unknown database engine: {engineName}", nameof(engineName))
        };
    }

    /// <summary>
    /// Gets a list of all supported database engines.
    /// </summary>
    public static DatabaseEngineType[] GetSupportedEngines()
    {
        return new[] 
        { 
            DatabaseEngineType.PostgreSQL,
            DatabaseEngineType.MySQL,
            DatabaseEngineType.SQLServer,
            DatabaseEngineType.MariaDB
        };
    }
}
