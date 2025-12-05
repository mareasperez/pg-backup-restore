using System.CommandLine;
using DbTool.Application.DTOs;
using DbTool.Application.Interfaces;
using DbTool.Application.Settings;
using DbTool.Infrastructure;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

// Load configuration
var configuration = new ConfigurationBuilder()
    .SetBasePath(Directory.GetCurrentDirectory())
    .AddJsonFile("appsettings.json", optional: true, reloadOnChange: true)
    .Build();

var services = new ServiceCollection();

// Configure Options Pattern
services.Configure<DbToolSettings>(configuration.GetSection("DbTool"));

services.AddInfrastructure();
var serviceProvider = services.BuildServiceProvider();

var rootCommand = new RootCommand("DbTool - Multi-Engine Database Backup & Restore Tool");

// Database commands
var dbCommand = new Command("db", "Manage database connections");

// db add
var dbAddCommand = new Command("add", "Add a new database connection");
var nameOption = new Option<string>("--name", "Connection name") { IsRequired = true };
var engineOption = new Option<string>("--engine", "Database engine (postgres, mysql, sqlserver, mariadb)") { IsRequired = true };
var hostOption = new Option<string>("--host", "Database host") { IsRequired = true };
var portOption = new Option<int>("--port", "Database port") { IsRequired = true };
var databaseOption = new Option<string>("--database", "Database name") { IsRequired = true };
var usernameOption = new Option<string>("--username", "Database username") { IsRequired = true };
var passwordOption = new Option<string>("--password", "Database password") { IsRequired = true };

dbAddCommand.AddOption(nameOption);
dbAddCommand.AddOption(engineOption);
dbAddCommand.AddOption(hostOption);
dbAddCommand.AddOption(portOption);
dbAddCommand.AddOption(databaseOption);
dbAddCommand.AddOption(usernameOption);
dbAddCommand.AddOption(passwordOption);

dbAddCommand.SetHandler(async (name, engine, host, port, database, username, password) =>
{
    var dbService = serviceProvider.GetRequiredService<IDatabaseConnectionService>();
    
    try
    {
        var dto = new CreateDatabaseConnectionDto(name, engine, host, port, database, username, password);
        var id = await dbService.CreateDatabaseConnectionAsync(dto);
        Console.WriteLine($"✓ Database connection '{name}' created successfully (ID: {id})");
    }
    catch (Exception ex)
    {
        Console.WriteLine($"✗ Error: {ex.Message}");
        Environment.Exit(1);
    }
}, nameOption, engineOption, hostOption, portOption, databaseOption, usernameOption, passwordOption);

// db list
var dbListCommand = new Command("list", "List all database connections");
dbListCommand.SetHandler(async () =>
{
    var dbService = serviceProvider.GetRequiredService<IDatabaseConnectionService>();
    
    try
    {
        var connections = await dbService.GetAllDatabaseConnectionsAsync();
        
        Console.WriteLine("\nConfigured Database Connections:");
        Console.WriteLine("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
        
        foreach (var conn in connections)
        {
            Console.WriteLine($"  {conn.Name,-15} | {conn.Engine,-12} | {conn.Host}:{conn.Port}/{conn.DatabaseName}");
        }
        
        Console.WriteLine("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
    }
    catch (Exception ex)
    {
        Console.WriteLine($"✗ Error: {ex.Message}");
        Environment.Exit(1);
    }
});

// db test
var dbTestCommand = new Command("test", "Test connection to a database");
var testNameOption = new Option<string>("--name", "Connection name") { IsRequired = true };
dbTestCommand.AddOption(testNameOption);

dbTestCommand.SetHandler(async (name) =>
{
    var dbService = serviceProvider.GetRequiredService<IDatabaseConnectionService>();
    
    try
    {
        Console.Write($"Testing connection to '{name}'... ");
        var success = await dbService.TestConnectionAsync(name);
        
        if (success)
        {
            Console.WriteLine("✓ Connection successful");
        }
        else
        {
            Console.WriteLine("✗ Connection failed");
            Environment.Exit(1);
        }
    }
    catch (Exception ex)
    {
        Console.WriteLine($"\n✗ Error: {ex.Message}");
        Environment.Exit(1);
    }
}, testNameOption);

// db delete
var dbDeleteCommand = new Command("delete", "Delete a database connection");
var deleteNameOption = new Option<string>("--name", "Connection name") { IsRequired = true };
dbDeleteCommand.AddOption(deleteNameOption);

dbDeleteCommand.SetHandler(async (name) =>
{
    var dbService = serviceProvider.GetRequiredService<IDatabaseConnectionService>();
    
    try
    {
        var deleted = await dbService.DeleteDatabaseConnectionAsync(name);
        
        if (deleted)
        {
            Console.WriteLine($"✓ Database connection '{name}' deleted successfully");
        }
        else
        {
            Console.WriteLine($"✗ Database connection '{name}' not found");
            Environment.Exit(1);
        }
    }
    catch (Exception ex)
    {
        Console.WriteLine($"✗ Error: {ex.Message}");
        Environment.Exit(1);
    }
}, deleteNameOption);

dbCommand.AddCommand(dbAddCommand);
dbCommand.AddCommand(dbListCommand);
dbCommand.AddCommand(dbTestCommand);
dbCommand.AddCommand(dbDeleteCommand);

// Backup command
var backupCommand = new Command("backup", "Create a database backup");
var backupDbOption = new Option<string>("--db", "Database connection name") { IsRequired = true };
var backupOutputOption = new Option<string?>("--output", "Output directory (optional)");
backupCommand.AddOption(backupDbOption);
backupCommand.AddOption(backupOutputOption);

backupCommand.SetHandler(async (dbName, outputDir) =>
{
    var backupService = serviceProvider.GetRequiredService<IBackupService>();
    
    try
    {
        var progress = new Progress<string>(msg => Console.WriteLine(msg));
        var result = await backupService.CreateBackupAsync(dbName, outputDir, progress);
        
        if (result.Success)
        {
            Console.WriteLine($"\n✓ Backup completed successfully");
            Console.WriteLine($"  File: {result.FilePath}");
            Console.WriteLine($"  Size: {result.FileSizeBytes / 1024.0 / 1024.0:F2} MB");
        }
        else
        {
            Console.WriteLine($"\n✗ Backup failed: {result.ErrorMessage}");
            Environment.Exit(1);
        }
    }
    catch (Exception ex)
    {
        Console.WriteLine($"✗ Error: {ex.Message}");
        Environment.Exit(1);
    }
}, backupDbOption, backupOutputOption);

// List backups command
var listBackupsCommand = new Command("list-backups", "List all backups for a database");
var listBackupsDbOption = new Option<string>("--db", "Database connection name") { IsRequired = true };
listBackupsCommand.AddOption(listBackupsDbOption);

listBackupsCommand.SetHandler(async (dbName) =>
{
    var backupService = serviceProvider.GetRequiredService<IBackupService>();
    
    try
    {
        var backups = await backupService.ListBackupsAsync(dbName);
        
        Console.WriteLine($"\nBackups for '{dbName}':");
        Console.WriteLine("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
        
        foreach (var backup in backups)
        {
            var sizeMB = backup.FileSizeBytes / 1024.0 / 1024.0;
            Console.WriteLine($"  [{backup.Status,-10}] {backup.CreatedAt:yyyy-MM-dd HH:mm} | {sizeMB:F2} MB | {backup.FilePath}");
        }
        
        Console.WriteLine("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
    }
    catch (Exception ex)
    {
        Console.WriteLine($"✗ Error: {ex.Message}");
        Environment.Exit(1);
    }
}, listBackupsDbOption);

// Restore command
var restoreCommand = new Command("restore", "Restore a database from a backup file");
var restoreDbOption = new Option<string>("--db", "Database connection name") { IsRequired = true };
var restoreFileOption = new Option<string>("--file", "Path to backup file") { IsRequired = true };
var restoreForceOption = new Option<bool>("--force", "Skip confirmation prompt");
restoreCommand.AddOption(restoreDbOption);
restoreCommand.AddOption(restoreFileOption);
restoreCommand.AddOption(restoreForceOption);

restoreCommand.SetHandler(async (dbName, backupFile, force) =>
{
    var backupService = serviceProvider.GetRequiredService<IBackupService>();
    
    try
    {
        // Validate file exists
        if (!File.Exists(backupFile))
        {
            Console.WriteLine($"✗ Error: Backup file not found: {backupFile}");
            Environment.Exit(1);
            return;
        }

        // Safety confirmation
        if (!force)
        {
            Console.WriteLine($"\n⚠️  WARNING: This will restore the database '{dbName}' from:");
            Console.WriteLine($"   {backupFile}");
            Console.WriteLine($"\n   This operation will overwrite existing data!");
            Console.Write($"\nContinue? (yes/N): ");
            
            var response = Console.ReadLine()?.Trim().ToLowerInvariant();
            if (response != "yes")
            {
                Console.WriteLine("Restore cancelled.");
                Environment.Exit(0);
                return;
            }
        }

        var progress = new Progress<string>(msg => Console.WriteLine(msg));
        var result = await backupService.RestoreBackupAsync(dbName, backupFile, progress);
        
        if (result.Success)
        {
            Console.WriteLine($"\n✓ Restore completed successfully");
            Console.WriteLine($"  Database: {result.DatabaseName}");
            Console.WriteLine($"  From: {result.BackupFilePath}");
        }
        else
        {
            Console.WriteLine($"\n✗ Restore failed: {result.ErrorMessage}");
            Environment.Exit(1);
        }
    }
    catch (Exception ex)
    {
        Console.WriteLine($"✗ Error: {ex.Message}");
        Environment.Exit(1);
    }
}, restoreDbOption, restoreFileOption, restoreForceOption);

rootCommand.AddCommand(dbCommand);
rootCommand.AddCommand(backupCommand);
rootCommand.AddCommand(listBackupsCommand);
rootCommand.AddCommand(restoreCommand);

return await rootCommand.InvokeAsync(args);
