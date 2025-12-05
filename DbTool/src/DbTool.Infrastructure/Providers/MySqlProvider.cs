using System.Text;
using DbTool.Domain.Entities;
using DbTool.Domain.Interfaces;
using MySqlConnector;

namespace DbTool.Infrastructure.Providers;

/// <summary>
/// MySQL database provider using MySqlConnector (native .NET driver).
/// No external dependencies on mysqldump or other tools.
/// </summary>
public class MySqlProvider : IDatabaseProvider
{
    public string EngineName => "mysql";

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

        await using var connection = new MySqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);

        var tables = await GetAllTablesAsync(connection, cancellationToken);
        progress?.Report($"Found {tables.Count} tables to backup");

        var backupSql = new StringBuilder();
        backupSql.AppendLine("SET FOREIGN_KEY_CHECKS=0;");
        backupSql.AppendLine();

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

        backupSql.AppendLine("SET FOREIGN_KEY_CHECKS=1;");

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

        await using var connection = new MySqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);

        await using var command = new MySqlCommand(backupSql, connection);
        command.CommandTimeout = 0;
        
        await command.ExecuteNonQueryAsync(cancellationToken);

        progress?.Report($"✓ Restore completed successfully");
    }

    public async Task DropAllTablesAsync(DatabaseConnection DatabaseConnection, CancellationToken cancellationToken = default)
    {
        var connectionString = BuildConnectionString(DatabaseConnection);

        await using var connection = new MySqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);

        // Get all tables
        var tables = await GetAllTablesAsync(connection, cancellationToken);

        // Disable foreign key checks
        await using (var command = new MySqlCommand("SET FOREIGN_KEY_CHECKS=0", connection))
        {
            await command.ExecuteNonQueryAsync(cancellationToken);
        }

        // Drop all tables
        foreach (var table in tables)
        {
            await using var command = new MySqlCommand($"DROP TABLE IF EXISTS `{table}`", connection);
            await command.ExecuteNonQueryAsync(cancellationToken);
        }

        // Re-enable foreign key checks
        await using (var command = new MySqlCommand("SET FOREIGN_KEY_CHECKS=1", connection))
        {
            await command.ExecuteNonQueryAsync(cancellationToken);
        }
    }

    public async Task<bool> TestConnectionAsync(DatabaseConnection DatabaseConnection, CancellationToken cancellationToken = default)
    {
        try
        {
            var connectionString = BuildConnectionString(DatabaseConnection);

            await using var connection = new MySqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            await using var command = new MySqlCommand("SELECT 1", connection);
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
        return $"Server={DatabaseConnection.Host};Port={DatabaseConnection.Port};Database={DatabaseConnection.DatabaseName};User={DatabaseConnection.Username};Password={DatabaseConnection.Password}";
    }

    private static async Task<List<string>> GetAllTablesAsync(MySqlConnection connection, CancellationToken cancellationToken)
    {
        var tables = new List<string>();
        var sql = "SHOW TABLES";

        await using var command = new MySqlCommand(sql, connection);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);

        while (await reader.ReadAsync(cancellationToken))
        {
            tables.Add(reader.GetString(0));
        }

        return tables;
    }

    private static async Task<string> GetCreateTableStatementAsync(MySqlConnection connection, string tableName, CancellationToken cancellationToken)
    {
        var sql = $"SHOW CREATE TABLE `{tableName}`";

        await using var command = new MySqlCommand(sql, connection);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);

        if (await reader.ReadAsync(cancellationToken))
        {
            return reader.GetString(1) + ";";
        }

        return $"-- Could not generate CREATE TABLE for {tableName}";
    }

    private static async Task<string> GetTableDataAsInsertStatementsAsync(MySqlConnection connection, string tableName, CancellationToken cancellationToken)
    {
        var insertStatements = new StringBuilder();

        var dataSql = $"SELECT * FROM `{tableName}`";
        await using var command = new MySqlCommand(dataSql, connection);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);

        if (reader.FieldCount == 0) return string.Empty;

        var columns = new List<string>();
        for (int i = 0; i < reader.FieldCount; i++)
        {
            columns.Add($"`{reader.GetName(i)}`");
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

            var insertSql = $"INSERT INTO `{tableName}` ({string.Join(", ", columns)}) VALUES ({string.Join(", ", values)});";
            insertStatements.AppendLine(insertSql);
        }

        return insertStatements.ToString();
    }
}
