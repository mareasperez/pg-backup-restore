# DbTool

> **Multi-Engine Database Backup & Restore Tool**  
> Cross-platform • Zero Dependencies • Native .NET Drivers

[![.NET](https://img.shields.io/badge/.NET-9.0-512BD4)](https://dotnet.microsoft.com/)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

---

## 🚀 Quick Start

```powershell
# Build the project
dotnet build

# Add a database connection
dotnet run --project src/DbTool.CLI -- db add \
  --name prod \
  --engine postgres \
  --host localhost \
  --port 5432 \
  --database myapp \
  --username postgres \
  --password yourpass

# Create a backup
dotnet run --project src/DbTool.CLI -- backup --db prod

# List all backups
dotnet run --project src/DbTool.CLI -- list-backups --db prod
```

---

## ✨ Features

- ✅ **Zero External Dependencies** - No pg_dump, mysqldump, or sqlcmd required
- ✅ **Multi-Database Support** - PostgreSQL, MySQL, SQL Server, MariaDB
- ✅ **Cross-Platform** - Works on Windows, Linux, macOS
- ✅ **Native .NET Drivers** - Uses official database drivers (Npgsql, MySqlConnector, etc.)
- ✅ **Clean Architecture** - N-tier design with Domain, Application, Infrastructure, CLI, UI layers
- ✅ **Self-Contained** - Can be published as a single executable
- ✅ **SQLite Configuration** - Local database for connection management
- ✅ **Optional Compression** - Gzip compression (disabled by default)
- ✅ **CLI & GUI** - Command-line interface and Avalonia desktop application
- ✅ **GUI-Ready** - Core logic ready for future GUI implementation

---

## 📦 Supported Databases

| Database | Driver | Status |
|----------|--------|--------|
| PostgreSQL | Npgsql 9.0.2 | ✅ |
| MySQL | MySqlConnector 2.4.0 | ✅ |
| SQL Server | Microsoft.Data.SqlClient 5.2.2 | ✅ |
| MariaDB | MySqlConnector 2.4.0 | ✅ |

---

## 📖 Usage

### Database Connection Management

```powershell
# Add a new connection
dotnet run --project src/DbTool.CLI -- db add \
  --name <connection-name> \
  --engine <postgres|mysql|sqlserver|mariadb> \
  --host <hostname> \
  --port <port> \
  --database <database-name> \
  --username <username> \
  --password <password>

# List all connections
dotnet run --project src/DbTool.CLI -- db list

# Test a connection
dotnet run --project src/DbTool.CLI -- db test --name <connection-name>

# Delete a connection
dotnet run --project src/DbTool.CLI -- db delete --name <connection-name>
```

### Backup Operations

```powershell
# Create a backup
dotnet run --project src/DbTool.CLI -- backup --db <connection-name>

# Create a backup with custom output directory
dotnet run --project src/DbTool.CLI -- backup --db <connection-name> --output /path/to/backups

# List all backups for a database
dotnet run --project src/DbTool.CLI -- list-backups --db <connection-name>
```

### Restore Operations

```powershell
# Restore from a backup file (with confirmation prompt)
dotnet run --project src/DbTool.CLI -- restore --db <connection-name> --file <backup-file-path>

# Restore without confirmation (use with caution!)
dotnet run --project src/DbTool.CLI -- restore --db <connection-name> --file <backup-file-path> --force
```

> **⚠️ Warning**: Restore operations will overwrite existing data. Always verify the backup file before restoring.

---

## 🏗️ Architecture

```
DbTool/
├── src/
│   ├── DbTool.Domain/          # Entities, Enums, Interfaces (pure C#)
│   ├── DbTool.Application/     # DTOs, Service Interfaces, Validators
│   ├── DbTool.Infrastructure/  # Repositories, Providers, Services
│   └── DbTool.CLI/             # Command-line interface
└── tests/
    ├── DbTool.Domain.Tests/
    ├── DbTool.Application.Tests/
    └── DbTool.Infrastructure.Tests/
```

**Dependency Flow**: `CLI → Application → Infrastructure → Domain`

---

## 🔧 Installation

### Prerequisites

- [.NET 9 SDK](https://dotnet.microsoft.com/download) or later

### Build from Source

```powershell
# Clone the repository
git clone <repository-url>
cd DbTool

# Restore dependencies and build
dotnet restore
dotnet build

# Run
dotnet run --project src/DbTool.CLI -- --help
```

### Create Self-Contained Executable

```powershell
# Windows
dotnet publish src/DbTool.CLI -c Release -r win-x64 --self-contained -p:PublishSingleFile=true -o ./dist/win

# Linux
dotnet publish src/DbTool.CLI -c Release -r linux-x64 --self-contained -p:PublishSingleFile=true -o ./dist/linux

# macOS
dotnet publish src/DbTool.CLI -c Release -r osx-x64 --self-contained -p:PublishSingleFile=true -o ./dist/mac
```

The executable will be in the `dist` folder (~70MB, includes all dependencies).

---

## 📁 Configuration

Database connections are stored in a local SQLite database:

- **Windows**: `%APPDATA%\DbTool\config.db`
- **Linux/macOS**: `~/.config/DbTool/config.db`

---

## 🧪 Testing

```powershell
# Run all tests
dotnet test

# Run tests with coverage
dotnet test --collect:"XPlat Code Coverage"
```

---

## 📊 Backup Format

Backups are generated as **plain SQL files** containing:
- CREATE TABLE statements (full schema definition)
- INSERT statements (all data)
- Database-specific optimizations

**Advantages**:
- Human-readable and easy to inspect
- Version control friendly
- Can be modified before restore
- Cross-platform compatible

---

## 🛠️ Development

### Project Structure

- **Domain**: Core business entities and interfaces (no external dependencies)
- **Application**: Use cases, DTOs, and service contracts
- **Infrastructure**: Database implementations, providers, and services
- **CLI**: Command-line interface using System.CommandLine

### Adding a New Database Provider

1. Create a new provider class implementing `IDatabaseProvider`
2. Add the provider to `ProviderFactory`
3. Add the corresponding NuGet package to `DbTool.Infrastructure.csproj`
4. Update `DatabaseEngineType` enum

Example:
```csharp
public class OracleProvider : IDatabaseProvider
{
    public string EngineName => "oracle";
    
    public async Task BackupAsync(DatabaseConnection connection, string outputPath, ...)
    {
        // Implementation using Oracle.ManagedDataAccess.Core
    }
    
    // Implement other methods...
}
```

---

## 🚧 Roadmap

- [x] Implement restore functionality ✅
- [ ] Add backup compression (gzip)
- [ ] Implement backup encryption
- [ ] Add scheduled backups
- [ ] Build GUI (Avalonia/MAUI)
- [ ] Cloud storage integration (Azure, AWS S3)
- [ ] Backup retention policies
- [ ] Email notifications
- [ ] Backup verification

---

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

- [Npgsql](https://www.npgsql.org/) - PostgreSQL .NET driver
- [MySqlConnector](https://mysqlconnector.net/) - MySQL .NET driver
- [Microsoft.Data.SqlClient](https://github.com/dotnet/SqlClient) - SQL Server .NET driver
- [Dapper](https://github.com/DapperLib/Dapper) - Micro ORM
- [FluentValidation](https://fluentvalidation.net/) - Validation library
- [System.CommandLine](https://github.com/dotnet/command-line-api) - Command-line parsing

---

## 📞 Support

For issues, questions, or suggestions, please [open an issue](https://github.com/yourusername/DbTool/issues).

---

**Made with ❤️ using .NET**
