# C# Migration Guide (Project: DbTool)

This guide details the steps required to migrate the Bash backup tools to a modern, cross-platform C# console application (.NET 8+).

## 🎯 Objectives
- **Cross-Platform**: Native executable on Windows, Linux, and macOS.
- **Zero Dependencies**: Self-contained binary.
- **Local Database**: Replace `.env` files with SQLite.
- **Multi-Engine**: Extensible support for PostgreSQL, MySQL, etc.
- **GUI Ready**: Strict separation between Logic (Core) and CLI.
- **Driver Management**: Automated download of database tools (drivers/connectors).

---

## 🛠️ Step 1: Project Initialization

The first step is to create the solution structure, separating logic from the console interface.

### 1.1 Create Solution and Projects
Run these commands in the repository root:

```powershell
# Create source folder
mkdir DbTool
cd DbTool

# Create empty solution
dotnet new sln -n DbTool

# Create Class Library (Core) - All logic goes here
dotnet new classlib -n DbTool.Core -o src/DbTool.Core

# Create Console App (CLI) - User interface goes here
dotnet new console -n DbTool.CLI -o src/DbTool.CLI

# Add projects to solution
dotnet sln add src/DbTool.Core/DbTool.Core.csproj
dotnet sln add src/DbTool.CLI/DbTool.CLI.csproj

# Reference Core from CLI
dotnet add src/DbTool.CLI/DbTool.CLI.csproj reference src/DbTool.Core/DbTool.Core.csproj
```

### 1.2 Install Dependencies
We will need libraries for SQLite, command line parsing, and data access.

```powershell
# In DbTool.Core (Logic & Data)
dotnet add src/DbTool.Core package Microsoft.Data.Sqlite
dotnet add src/DbTool.Core package Dapper

# In DbTool.CLI (Console Arguments)
dotnet add src/DbTool.CLI package System.CommandLine
```

---

## 🏗️ Step 2: Core Implementation (DbTool.Core)

### 2.1 Data Model (SQLite)
Define classes representing your tables in `src/DbTool.Core/Models/`.

```csharp
// Environment.cs
public class EnvironmentConfig
{
    public int Id { get; set; }
    public string Name { get; set; }      // "dev", "prod"
    public string Engine { get; set; }    // "postgres", "mysql"
    public string Host { get; set; }
    public int Port { get; set; }
    public string Database { get; set; }
    public string Username { get; set; }
    public string Password { get; set; }  // Consider encryption
}
```

### 2.2 Configuration Service
Create `src/DbTool.Core/Services/ConfigService.cs` to handle SQLite.
- On startup, check if `.db` exists and create tables if not.
- CRUD Methods: `AddEnvironment`, `GetEnvironment`, `ListEnvironments`.

### 2.3 Provider Pattern (Strategy Pattern)
To support multiple engines, define a common interface.

**`src/DbTool.Core/Providers/IDatabaseProvider.cs`**
```csharp
public interface IDatabaseProvider
{
    Task BackupAsync(EnvironmentConfig env, string outputPath);
    Task RestoreAsync(EnvironmentConfig env, string backupPath);
    Task DropAllTablesAsync(EnvironmentConfig env);
}
```

### 2.4 Driver/Tool Management [NEW]
Create `src/DbTool.Core/Services/ToolDownloader.cs`.
- This service will be responsible for downloading external binaries (like `pg_dump`, `mysql_dump`) if they are not found in the system PATH.
- It should download the appropriate version for the current OS (Windows/Linux/macOS).
- Store tools in a local `tools/` directory.

---

## 🖥️ Step 3: CLI Implementation (DbTool.CLI)

Use `System.CommandLine` in `Program.cs` to create commands.

### 3.1 Main Commands

1.  **`env`**: Environment management.
    *   `dbtool env add --name dev --engine postgres ...`
    *   `dbtool env list`
2.  **`backup`**: Perform backups.
    *   `dbtool backup --env dev`
3.  **`restore`**: Restore backups.
    *   `dbtool restore --target dev --source prod`
4.  **`drivers`**: Manage database drivers [NEW].
    *   `dbtool drivers install --engine postgres` (Downloads pg_dump/pg_restore)

### 3.2 Code Example (Program.cs)

```csharp
var rootCommand = new RootCommand("Multi-Engine Backup Tool");

var backupCommand = new Command("backup", "Perform a backup");
var envOption = new Option<string>("--env", "Environment name");
backupCommand.AddOption(envOption);

backupCommand.SetHandler(async (envName) => {
    // 1. Get config from Core
    // 2. Instantiate ProviderFactory
    // 3. Execute Backup
}, envOption);

rootCommand.AddCommand(backupCommand);
await rootCommand.InvokeAsync(args);
```

---

## 🚀 Step 4: Publish (Build)

To generate the single executable (no external .NET dependencies):

**Windows:**
```powershell
dotnet publish src/DbTool.CLI -c Release -r win-x64 --self-contained -p:PublishSingleFile=true -o ./dist/win
```

**Linux:**
```powershell
dotnet publish src/DbTool.CLI -c Release -r linux-x64 --self-contained -p:PublishSingleFile=true -o ./dist/linux
```

---

## 🔮 Future: Graphical User Interface (GUI)

When you want to add a GUI:
1.  Create a new project: `dotnet new maui -n DbTool.UI` (or WPF/Avalonia).
2.  Add reference to Core: `dotnet add reference src/DbTool.Core`.
3.  Reuse all services (`ConfigService`, `BackupService`) directly in your buttons and forms.
