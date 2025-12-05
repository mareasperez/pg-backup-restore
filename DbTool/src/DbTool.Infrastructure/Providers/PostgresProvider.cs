using System.Data;
using System.Text;
using DbTool.Domain.Entities;
using DbTool.Domain.Interfaces;
using Npgsql;

namespace DbTool.Infrastructure.Providers;

/// <summary>
/// PostgreSQL database provider using Npgsql (native .NET driver).
/// No external dependencies on pg_dump or other tools.
/// </summary>
public class PostgresProvider : IDatabaseProvider
{
    public string EngineName => "postgres";

    public async Task BackupAsync(
        DatabaseConnection DatabaseConnection, 
        string outputPath, 
        IProgress<string>? progress = null,
        CancellationToken cancellationToken = default)
    {
        progress?.Report($"Starting backup of {DatabaseConnection.DatabaseName}...");

        // Ensure output directory exists
        var directory = Path.GetDirectoryName(outputPath);
        if (!string.IsNullOrEmpty(directory) && !Directory.Exists(directory))
        {
            Directory.CreateDirectory(directory);
        }

        var connectionString = BuildConnectionString(DatabaseConnection);

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);

        // Get all table names
        var tables = await GetAllTablesAsync(connection, cancellationToken);
        progress?.Report($"Found {tables.Count} tables to backup");

        var backupSql = new StringBuilder();
        
        // Generate CREATE TABLE statements and data
        foreach (var table in tables)
        {
            progress?.Report($"Backing up table: {table}");
            
            // Get CREATE TABLE statement
            var createTableSql = await GetCreateTableStatementAsync(connection, table, cancellationToken);
            backupSql.AppendLine(createTableSql);
            backupSql.AppendLine();

            // Get table data as INSERT statements
            var insertStatements = await GetTableDataAsInsertStatementsAsync(connection, table, cancellationToken);
            backupSql.AppendLine(insertStatements);
            backupSql.AppendLine();
        }

        // Write to file
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

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);

        // Execute the backup SQL
        await using var command = new NpgsqlCommand(backupSql, connection);
        command.CommandTimeout = 0; // No timeout for large restores
        
        await command.ExecuteNonQueryAsync(cancellationToken);

        progress?.Report($"✓ Restore completed successfully");
    }

    public async Task DropAllTablesAsync(DatabaseConnection DatabaseConnection, CancellationToken cancellationToken = default)
    {
        var connectionString = BuildConnectionString(DatabaseConnection);

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);

        // Drop and recreate public schema
        var sql = "DROP SCHEMA public CASCADE; CREATE SCHEMA public;";
        await using var command = new NpgsqlCommand(sql, connection);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task<bool> TestConnectionAsync(DatabaseConnection DatabaseConnection, CancellationToken cancellationToken = default)
    {
        try
        {
            var connectionString = BuildConnectionString(DatabaseConnection);

            await using var connection = new NpgsqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            await using var command = new NpgsqlCommand("SELECT 1", connection);
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
        return $"Host={DatabaseConnection.Host};Port={DatabaseConnection.Port};Database={DatabaseConnection.DatabaseName};Username={DatabaseConnection.Username};Password={DatabaseConnection.Password}";
    }

    private static async Task<List<string>> GetAllTablesAsync(NpgsqlConnection connection, CancellationToken cancellationToken)
    {
        var tables = new List<string>();
        var sql = @"
            SELECT table_name 
            FROM information_schema.tables 
            WHERE table_schema = 'public' 
            AND table_type = 'BASE TABLE'
            ORDER BY table_name";

        await using var command = new NpgsqlCommand(sql, connection);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);

        while (await reader.ReadAsync(cancellationToken))
        {
            tables.Add(reader.GetString(0));
        }

        return tables;
    }

    private static async Task<string> GetCreateTableStatementAsync(NpgsqlConnection connection, string tableName, CancellationToken cancellationToken)
    {
        var sql = $@"
            SELECT 
                'CREATE TABLE ' || table_name || ' (' || 
                string_agg(
                    column_name || ' ' || 
                    CASE 
                        WHEN data_type = 'character varying' THEN 'VARCHAR(' || character_maximum_length || ')'
                        WHEN data_type = 'character' THEN 'CHAR(' || character_maximum_length || ')'
                        WHEN data_type = 'numeric' THEN 'NUMERIC(' || numeric_precision || ',' || numeric_scale || ')'
                        ELSE UPPER(data_type)
                    END ||
                    CASE WHEN is_nullable = 'NO' THEN ' NOT NULL' ELSE '' END,
                    ', '
                ) || ');' as create_statement
            FROM information_schema.columns
            WHERE table_schema = 'public' AND table_name = '{tableName}'
            GROUP BY table_name";

        await using var command = new NpgsqlCommand(sql, connection);
        var result = await command.ExecuteScalarAsync(cancellationToken);
        return result?.ToString() ?? $"-- Could not generate CREATE TABLE for {tableName}";
    }

    private static async Task<string> GetTableDataAsInsertStatementsAsync(NpgsqlConnection connection, string tableName, CancellationToken cancellationToken)
    {
        var insertStatements = new StringBuilder();

        // Get column names
        var columnsSql = $@"
            SELECT column_name 
            FROM information_schema.columns 
            WHERE table_schema = 'public' AND table_name = '{tableName}'
            ORDER BY ordinal_position";

        var columns = new List<string>();
        await using (var command = new NpgsqlCommand(columnsSql, connection))
        await using (var reader = await command.ExecuteReaderAsync(cancellationToken))
        {
            while (await reader.ReadAsync(cancellationToken))
            {
                columns.Add(reader.GetString(0));
            }
        }

        if (columns.Count == 0) return string.Empty;

        // Get data
        var dataSql = $"SELECT * FROM {tableName}";
        await using (var command = new NpgsqlCommand(dataSql, connection))
        await using (var reader = await command.ExecuteReaderAsync(cancellationToken))
        {
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
        }

        return insertStatements.ToString();
    }
}
