using System.Text;
using DbTool.Domain.Entities;
using DbTool.Domain.Interfaces;
using Microsoft.Data.SqlClient;

namespace DbTool.Infrastructure.Providers;

/// <summary>
/// SQL Server database provider using Microsoft.Data.SqlClient (native .NET driver).
/// No external dependencies on sqlcmd or other tools.
/// </summary>
public class SqlServerProvider : IDatabaseProvider
{
    public string EngineName => "sqlserver";

    public async Task BackupAsync(
        DatabaseConnection DatabaseConnection, 
        string outputPath, 
        IProgress<string>? progress = null,
        CancellationToken cancellationToken = default)
    {
        progress?.Report($"Starting backup of {DatabaseConnection.DatabaseName}...");

        var directory = Path.GetDirectoryName(outputPath);
        if (!string.IsNullOrEmpty(directory) && !Directory.Exists(directory))
        {
            Directory.CreateDirectory(directory);
        }

        var connectionString = BuildConnectionString(DatabaseConnection);

        await using var connection = new SqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);

        var tables = await GetAllTablesAsync(connection, cancellationToken);
        progress?.Report($"Found {tables.Count} tables to backup");

        var backupSql = new StringBuilder();

        foreach (var table in tables)
        {
            progress?.Report($"Backing up table: {table}");
            
            var createTableSql = await GetCreateTableStatementAsync(connection, table, cancellationToken);
            backupSql.AppendLine(createTableSql);
            backupSql.AppendLine();

            var insertStatements = await GetTableDataAsInsertStatementsAsync(connection, table, cancellationToken);
            backupSql.AppendLine(insertStatements);
            backupSql.AppendLine();
        }

        await File.WriteAllTextAsync(outputPath, backupSql.ToString(), cancellationToken);
        progress?.Report($"✓ Backup completed: {outputPath}");
    }

    public async Task RestoreAsync(
        DatabaseConnection DatabaseConnection, 
        string backupPath, 
        IProgress<string>? progress = null,
        CancellationToken cancellationToken = default)
    {
        if (!File.Exists(backupPath))
        {
            throw new FileNotFoundException($"Backup file not found: {backupPath}");
        }

        progress?.Report($"Starting restore to {DatabaseConnection.DatabaseName}...");

        var connectionString = BuildConnectionString(DatabaseConnection);
        var backupSql = await File.ReadAllTextAsync(backupPath, cancellationToken);

        await using var connection = new SqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);

        // Split by GO statements (SQL Server batch separator)
        var batches = backupSql.Split(new[] { "\nGO\n", "\ngo\n" }, StringSplitOptions.RemoveEmptyEntries);

        foreach (var batch in batches)
        {
            if (string.IsNullOrWhiteSpace(batch)) continue;

            await using var command = new SqlCommand(batch, connection);
            command.CommandTimeout = 0;
            await command.ExecuteNonQueryAsync(cancellationToken);
        }

        progress?.Report($"✓ Restore completed successfully");
    }

    public async Task DropAllTablesAsync(DatabaseConnection DatabaseConnection, CancellationToken cancellationToken = default)
    {
        var connectionString = BuildConnectionString(DatabaseConnection);

        await using var connection = new SqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);

        // Drop all foreign key constraints first
        var dropFkSql = @"
            DECLARE @sql NVARCHAR(MAX) = N'';
            SELECT @sql += 'ALTER TABLE ' + QUOTENAME(OBJECT_SCHEMA_NAME(parent_object_id)) + '.' + QUOTENAME(OBJECT_NAME(parent_object_id)) + 
                           ' DROP CONSTRAINT ' + QUOTENAME(name) + ';'
            FROM sys.foreign_keys;
            EXEC sp_executesql @sql;";

        await using (var command = new SqlCommand(dropFkSql, connection))
        {
            await command.ExecuteNonQueryAsync(cancellationToken);
        }

        // Drop all tables
        var dropTablesSql = @"
            DECLARE @sql NVARCHAR(MAX) = N'';
            SELECT @sql += 'DROP TABLE ' + QUOTENAME(TABLE_SCHEMA) + '.' + QUOTENAME(TABLE_NAME) + ';'
            FROM INFORMATION_SCHEMA.TABLES
            WHERE TABLE_TYPE = 'BASE TABLE';
            EXEC sp_executesql @sql;";

        await using (var command = new SqlCommand(dropTablesSql, connection))
        {
            await command.ExecuteNonQueryAsync(cancellationToken);
        }
    }

    public async Task<bool> TestConnectionAsync(DatabaseConnection DatabaseConnection, CancellationToken cancellationToken = default)
    {
        try
        {
            var connectionString = BuildConnectionString(DatabaseConnection);

            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            await using var command = new SqlCommand("SELECT 1", connection);
            await command.ExecuteScalarAsync(cancellationToken);

            return true;
        }
        catch
        {
            return false;
        }
    }

    private static string BuildConnectionString(DatabaseConnection DatabaseConnection)
    {
        return $"Server={DatabaseConnection.Host},{DatabaseConnection.Port};Database={DatabaseConnection.DatabaseName};User Id={DatabaseConnection.Username};Password={DatabaseConnection.Password};TrustServerCertificate=True";
    }

    private static async Task<List<string>> GetAllTablesAsync(SqlConnection connection, CancellationToken cancellationToken)
    {
        var tables = new List<string>();
        var sql = @"
            SELECT TABLE_SCHEMA + '.' + TABLE_NAME 
            FROM INFORMATION_SCHEMA.TABLES 
            WHERE TABLE_TYPE = 'BASE TABLE'
            ORDER BY TABLE_NAME";

        await using var command = new SqlCommand(sql, connection);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);

        while (await reader.ReadAsync(cancellationToken))
        {
            tables.Add(reader.GetString(0));
        }

        return tables;
    }

    private static async Task<string> GetCreateTableStatementAsync(SqlConnection connection, string tableName, CancellationToken cancellationToken)
    {
        var parts = tableName.Split('.');
        var schema = parts.Length > 1 ? parts[0] : "dbo";
        var table = parts.Length > 1 ? parts[1] : parts[0];

        var sql = $@"
            SELECT 
                'CREATE TABLE ' + QUOTENAME('{schema}') + '.' + QUOTENAME('{table}') + ' (' + 
                STRING_AGG(
                    QUOTENAME(COLUMN_NAME) + ' ' + 
                    DATA_TYPE + 
                    CASE 
                        WHEN DATA_TYPE IN ('varchar', 'char', 'nvarchar', 'nchar') 
                        THEN '(' + CAST(CHARACTER_MAXIMUM_LENGTH AS VARCHAR) + ')'
                        WHEN DATA_TYPE IN ('decimal', 'numeric')
                        THEN '(' + CAST(NUMERIC_PRECISION AS VARCHAR) + ',' + CAST(NUMERIC_SCALE AS VARCHAR) + ')'
                        ELSE ''
                    END +
                    CASE WHEN IS_NULLABLE = 'NO' THEN ' NOT NULL' ELSE '' END,
                    ', '
                ) + ');' as CreateStatement
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = '{schema}' AND TABLE_NAME = '{table}'
            GROUP BY TABLE_SCHEMA, TABLE_NAME";

        await using var command = new SqlCommand(sql, connection);
        var result = await command.ExecuteScalarAsync(cancellationToken);
        return result?.ToString() ?? $"-- Could not generate CREATE TABLE for {tableName}";
    }

    private static async Task<string> GetTableDataAsInsertStatementsAsync(SqlConnection connection, string tableName, CancellationToken cancellationToken)
    {
        var insertStatements = new StringBuilder();

        var dataSql = $"SELECT * FROM {tableName}";
        await using var command = new SqlCommand(dataSql, connection);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);

        if (reader.FieldCount == 0) return string.Empty;

        var columns = new List<string>();
        for (int i = 0; i < reader.FieldCount; i++)
        {
            columns.Add($"[{reader.GetName(i)}]");
        }

        while (await reader.ReadAsync(cancellationToken))
        {
            var values = new List<string>();
            for (int i = 0; i < reader.FieldCount; i++)
            {
                if (reader.IsDBNull(i))
                {
                    values.Add("NULL");
                }
                else
                {
                    var value = reader.GetValue(i);
                    var valueStr = value.ToString()?.Replace("'", "''") ?? "";
                    values.Add($"'{valueStr}'");
                }
            }

            var insertSql = $"INSERT INTO {tableName} ({string.Join(", ", columns)}) VALUES ({string.Join(", ", values)});";
            insertStatements.AppendLine(insertSql);
        }

        return insertStatements.ToString();
    }
}
