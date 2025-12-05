# DbTool - Database Backup & Restore Tool

## 📋 Project Context

**DbTool** is a cross-platform database backup and restore tool developed in C# with .NET 9. It replaces bash scripts dependent on external tools (pg_dump, mysqldump) with a fully autonomous native .NET solution.

---

## 🎯 Main Objective

Create a professional backup/restore tool that:
- ✅ Works on Windows, Linux, and macOS without external dependencies
- ✅ Supports multiple database engines (PostgreSQL, MySQL, SQL Server, MariaDB)
- ✅ Uses native .NET drivers (Npgsql, MySqlConnector, Microsoft.Data.SqlClient)
- ✅ Has clean N-tier architecture (Domain, Application, Infrastructure, UI/CLI)
- ✅ Includes CLI and GUI (Avalonia)
- ✅ Supports optional compression (gzip)
- ✅ Uses configuration with Options Pattern

---

## 🏗️ Architecture

### N-Tier Architecture

```
DbTool/
├── Domain/          → Entities, Enums, Interfaces (no dependencies)
├── Application/     → DTOs, Service Interfaces, Validators, Settings
├── Infrastructure/  → Repositories, Providers, Services, SQLite
├── CLI/             → Command-line interface
└── UI/              → Graphical interface (Avalonia MVVM)
```

**Dependency flow:** `UI/CLI → Application → Infrastructure → Domain`

### Layers

#### 1. **Domain** (Core)
- **Purpose**: Pure business logic, no external dependencies
- **Contents**:
  - `Entities/`: `DatabaseConnection`, `Backup`
  - `Enums/`: `DatabaseEngineType`, `BackupStatus`
  - `Interfaces/`: `IDatabaseProvider`, `IDatabaseConnectionRepository`, `IBackupRepository`

#### 2. **Application** (Use Cases)
- **Purpose**: Use cases, service contracts, DTOs
- **Contents**:
  - `DTOs/`: `CreateDatabaseConnectionDto`, `BackupResultDto`, `RestoreResultDto`
  - `Interfaces/`: `IDatabaseConnectionService`, `IBackupService`
  - `Validators/`: `CreateDatabaseConnectionValidator` (FluentValidation)
  - `Settings/`: `DbToolSettings` (configuration)

#### 3. **Infrastructure** (Implementation)
- **Purpose**: Concrete implementations, data access
- **Contents**:
  - `Data/`: `AppDbContext` (SQLite with Dapper)
  - `Repositories/`: `DatabaseConnectionRepository`, `BackupRepository`
  - `Services/`: `DatabaseConnectionService`, `BackupService`, `GzipCompressionService`
  - `Providers/`: `PostgresProvider`, `MySqlProvider`, `SqlServerProvider`

#### 4. **CLI** (Command Interface)
- **Purpose**: Command-line interface
- **Technology**: System.CommandLine
- **Commands**: `db`, `backup`, `restore`, `list-backups`

#### 5. **UI** (Graphical Interface)
- **Purpose**: Graphical user interface
- **Technology**: Avalonia UI (MVVM)
- **Screens**: Connections, Backups, Restore, Settings

---

## 🔧 Implemented Features

### ✅ Connection Management
- Add, list, test, delete database connections
- Local SQLite storage
- Validation with FluentValidation

### ✅ Backup
- Plain SQL file generation (CREATE TABLE + INSERT)
- Support for PostgreSQL, MySQL, SQL Server, MariaDB
- Optional gzip compression (configurable)
- Metadata tracking (size, date, status)
- Progress reporting

### ✅ Restore
- Restoration from SQL or SQL.GZ files
- Auto-detection of compression
- Safety confirmation (requires "yes")
- `--force` flag for automation

### ✅ Configuration
- `appsettings.json` with Options Pattern
- Compression configuration (on/off, level)
- Customizable backup directory
- Customizable SQLite database path

### ✅ Compression
- Gzip compression (70-90% reduction)
- Levels: Optimal, Fastest, SmallestSize
- Disabled by default (backward compatible)
- Auto-decompression on restore

---

## 📦 Supported Database Engines

| Engine | Driver | NuGet Package | Status |
|--------|--------|---------------|--------|
| PostgreSQL | Npgsql | Npgsql 9.0.2 | ✅ |
| MySQL | MySqlConnector | MySqlConnector 2.4.0 | ✅ |
| SQL Server | Microsoft.Data.SqlClient | Microsoft.Data.SqlClient 5.2.2 | ✅ |
| MariaDB | MySqlConnector | MySqlConnector 2.4.0 | ✅ |

**All use native .NET drivers** - No external tool dependencies

---

## 🗂️ Data Storage

### SQLite Configuration Database
- **Location**: `%APPDATA%/DbTool/config.db` (Windows) or `~/.config/DbTool/config.db` (Linux/macOS)
- **Tables**:
  - `DatabaseConnections`: Saved connections
  - `Backups`: Backup metadata (path, size, status, date)

### Backups
- **Format**: Plain SQL (`.sql`) or compressed (`.sql.gz`)
- **Default location**: `./backups/<db-name>/<date-time>/`
- **Structure**:
  ```
  backups/
  └── production/
      ├── 2025-12-05-08-30-15/
      │   └── production.sql.gz
      └── 2025-12-05-14-45-30/
          └── production.sql
  ```

---

## ⚙️ Configuration (appsettings.json)

```json
{
  "DbTool": {
    "Backup": {
      "EnableCompression": false,
      "CompressionLevel": "Optimal",
      "DefaultBackupDirectory": "./backups"
    },
    "Database": {
      "ConfigDatabasePath": null
    }
  }
}
```

**Options Pattern**: Uses `IOptions<DbToolSettings>` for configuration injection

---

## 🚀 Usage

### CLI

```bash
# Connection management
dotnet run --project src/DbTool.CLI -- db add --name prod --engine postgres --host localhost --port 5432 --database mydb --username user --password pass
dotnet run --project src/DbTool.CLI -- db list
dotnet run --project src/DbTool.CLI -- db test --name prod
dotnet run --project src/DbTool.CLI -- db delete --name prod

# Backups
dotnet run --project src/DbTool.CLI -- backup --db prod
dotnet run --project src/DbTool.CLI -- backup --db prod --output /custom/path
dotnet run --project src/DbTool.CLI -- list-backups --db prod

# Restore
dotnet run --project src/DbTool.CLI -- restore --db prod --file /path/to/backup.sql
dotnet run --project src/DbTool.CLI -- restore --db prod --file /path/to/backup.sql.gz --force
```

### GUI (Avalonia)

```bash
dotnet run --project src/DbTool.UI
```

---

## 🔑 Design Decisions

### 1. **N-Tier Architecture**
- **Reason**: Separation of concerns, testability, reusability
- **Benefit**: Business logic (Application/Infrastructure) is reused in CLI and UI

### 2. **Native .NET Drivers**
- **Reason**: Eliminate dependencies on external tools (pg_dump, mysqldump)
- **Benefit**: Total portability, no additional installations

### 3. **Plain SQL as Format**
- **Reason**: Readable, editable, versionable with Git
- **Benefit**: Easy debugging, manual modification possible

### 4. **Optional Compression**
- **Reason**: Backward compatibility, flexibility
- **Benefit**: User decides between speed/space

### 5. **Options Pattern**
- **Reason**: .NET best practice for configuration
- **Benefit**: Strongly typed, testable, reload on change

### 6. **SQLite for Configuration**
- **Reason**: Serverless, portable, embedded
- **Benefit**: No additional database installation required

### 7. **Avalonia for GUI**
- **Reason**: Cross-platform, familiar XAML, mature
- **Benefit**: Single codebase for Windows/Linux/macOS

---

## 📊 Project Status

### ✅ Completed
- [x] N-tier architecture
- [x] Domain layer (entities, interfaces)
- [x] Application layer (DTOs, services, validators)
- [x] Infrastructure layer (repositories, providers, services)
- [x] Complete CLI (db, backup, restore, list-backups)
- [x] Native providers (PostgreSQL, MySQL, SQL Server, MariaDB)
- [x] Configuration system (Options Pattern)
- [x] Optional gzip compression
- [x] UI project created (Avalonia)

### 🚧 In Progress
- [ ] UI customization (Connections, Backups, Restore, Settings screens)
- [ ] DI integration in Avalonia
- [ ] Custom ViewModels and Views

### 📋 Pending (Future)
- [ ] Scheduled backups (cron-like)
- [ ] Retention policies
- [ ] Cloud integration (Azure, AWS S3)
- [ ] Backup encryption
- [ ] Notifications (email, webhooks)

---

## 🛠️ Technologies and Packages

### Core
- .NET 9.0
- C# 13

### NuGet Packages
- **Database**: Npgsql, MySqlConnector, Microsoft.Data.SqlClient, Dapper, Microsoft.Data.Sqlite
- **Validation**: FluentValidation, FluentValidation.DependencyInjectionExtensions
- **Configuration**: Microsoft.Extensions.Configuration, Microsoft.Extensions.Options
- **DI**: Microsoft.Extensions.DependencyInjection
- **CLI**: System.CommandLine
- **UI**: Avalonia, Avalonia.Themes.Fluent, CommunityToolkit.Mvvm

---

## 📝 Important Notes

### Namespace Conflicts
- **Problem**: `DbTool.Application` (namespace) vs `Avalonia.Application` (class)
- **Solution**: Use fully qualified `Avalonia.Application` in `App.axaml.cs`

### Environment → DatabaseConnection Rename
- **Reason**: Conflict with `System.Environment`
- **Impact**: All references updated in Domain, Application, Infrastructure, CLI

### Package Management
- **Preference**: Use `dotnet add package` commands instead of manually editing `.csproj`
- **Reason**: Better version and dependency management

---

## 🎯 Next Steps

1. **Complete Avalonia UI**:
   - Create ViewModels for Connections, Backups, Restore, Settings
   - Design Views with Material Design
   - Integrate DI and services

2. **Improve UX**:
   - Dark/light theme
   - Toast notifications
   - Animated progress bars

3. **Testing**:
   - Unit tests for services
   - Integration tests for providers
   - UI tests with Avalonia

4. **Deployment**:
   - Self-contained executables
   - Installers (MSI, DEB, DMG)
   - Publish on GitHub Releases

---

## 📚 Additional Documentation

- `README.md` - User guide and quick start
- `CONFIGURATION.md` - Configuration system details
- `walkthrough.md` - Complete technical walkthrough
- `task.md` - Task checklist

---

**Version**: 1.0.0  
**Last updated**: 2025-12-05  
**License**: MIT
