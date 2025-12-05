# DbTool - N-Tier Architecture - File Structure

This document outlines the complete file structure and class definitions for each layer of the DbTool project.

---

## 📁 Complete Project Structure

```
DbTool/
├── DbTool.sln
├── .gitignore
├── README.md
├── SETUP_N_TIER.md
│
├── src/
│   ├── DbTool.Domain/
│   │   ├── Entities/
│   │   │   ├── Environment.cs
│   │   │   ├── Backup.cs
│   │   │   └── DatabaseEngine.cs
│   │   ├── Enums/
│   │   │   ├── BackupStatus.cs
│   │   │   └── DatabaseEngineType.cs
│   │   ├── Interfaces/
│   │   │   ├── IDatabaseProvider.cs
│   │   │   ├── IEnvironmentRepository.cs
│   │   │   └── IBackupRepository.cs
│   │   └── ValueObjects/
│   │       └── ConnectionString.cs
│   │
│   ├── DbTool.Application/
│   │   ├── DTOs/
│   │   │   ├── CreateEnvironmentDto.cs
│   │   │   ├── UpdateEnvironmentDto.cs
│   │   │   ├── BackupResultDto.cs
│   │   │   └── RestoreResultDto.cs
│   │   ├── Interfaces/
│   │   │   ├── IBackupService.cs
│   │   │   ├── IRestoreService.cs
│   │   │   └── IEnvironmentService.cs
│   │   ├── UseCases/
│   │   │   ├── Backup/
│   │   │   │   └── CreateBackupUseCase.cs
│   │   │   ├── Restore/
│   │   │   │   └── RestoreBackupUseCase.cs
│   │   │   └── Environment/
│   │   │       ├── CreateEnvironmentUseCase.cs
│   │   │       ├── ListEnvironmentsUseCase.cs
│   │   │       └── DeleteEnvironmentUseCase.cs
│   │   └── Validators/
│   │       ├── CreateEnvironmentValidator.cs
│   │       └── BackupRequestValidator.cs
│   │
│   ├── DbTool.Infrastructure/
│   │   ├── Data/
│   │   │   ├── AppDbContext.cs
│   │   │   └── Migrations/
│   │   ├── Repositories/
│   │   │   ├── EnvironmentRepository.cs
│   │   │   └── BackupRepository.cs
│   │   ├── Providers/
│   │   │   ├── PostgresProvider.cs
│   │   │   ├── MySqlProvider.cs
│   │   │   └── ProviderFactory.cs
│   │   ├── Services/
│   │   │   ├── BackupService.cs
│   │   │   ├── RestoreService.cs
│   │   │   ├── EnvironmentService.cs
│   │   │   ├── FileService.cs
│   │   │   └── ToolDownloader.cs
│   │   └── DependencyInjection.cs
│   │
│   └── DbTool.CLI/
│       ├── Program.cs
│       ├── Commands/
│       │   ├── EnvCommand.cs
│       │   ├── BackupCommand.cs
│       │   ├── RestoreCommand.cs
│       │   └── DriversCommand.cs
│       └── DependencyInjection.cs
│
└── tests/
    ├── DbTool.Domain.Tests/
    ├── DbTool.Application.Tests/
    └── DbTool.Infrastructure.Tests/
```

---

## 🎯 Domain Layer Classes

### Entities/Environment.cs
```csharp
namespace DbTool.Domain.Entities;

public class Environment
{
    public int Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public DatabaseEngineType EngineType { get; set; }
    public string Host { get; set; } = string.Empty;
    public int Port { get; set; }
    public string DatabaseName { get; set; } = string.Empty;
    public string Username { get; set; } = string.Empty;
    public string Password { get; set; } = string.Empty;
    public DateTime CreatedAt { get; set; }
    public DateTime? UpdatedAt { get; set; }
    
    public ICollection<Backup> Backups { get; set; } = new List<Backup>();
}
```

### Entities/Backup.cs
```csharp
namespace DbTool.Domain.Entities;

public class Backup
{
    public int Id { get; set; }
    public int EnvironmentId { get; set; }
    public string FilePath { get; set; } = string.Empty;
    public long FileSizeBytes { get; set; }
    public string? Checksum { get; set; }
    public BackupStatus Status { get; set; }
    public string? ErrorMessage { get; set; }
    public DateTime CreatedAt { get; set; }
    
    public Environment Environment { get; set; } = null!;
}
```

### Enums/DatabaseEngineType.cs
```csharp
namespace DbTool.Domain.Enums;

public enum DatabaseEngineType
{
    PostgreSQL = 1,
    MySQL = 2,
    SQLServer = 3,
    MariaDB = 4
}
```

### Enums/BackupStatus.cs
```csharp
namespace DbTool.Domain.Enums;

public enum BackupStatus
{
    InProgress = 1,
    Success = 2,
    Failed = 3,
    Cancelled = 4
}
```

### Interfaces/IDatabaseProvider.cs
```csharp
namespace DbTool.Domain.Interfaces;

public interface IDatabaseProvider
{
    string EngineName { get; }
    Task BackupAsync(Environment environment, string outputPath, IProgress<string>? progress = null);
    Task RestoreAsync(Environment environment, string backupPath, IProgress<string>? progress = null);
    Task DropAllTablesAsync(Environment environment);
    Task<bool> TestConnectionAsync(Environment environment);
}
```

### Interfaces/IEnvironmentRepository.cs
```csharp
namespace DbTool.Domain.Interfaces;

public interface IEnvironmentRepository
{
    Task<int> AddAsync(Environment environment);
    Task<Environment?> GetByIdAsync(int id);
    Task<Environment?> GetByNameAsync(string name);
    Task<IEnumerable<Environment>> GetAllAsync();
    Task<bool> UpdateAsync(Environment environment);
    Task<bool> DeleteAsync(int id);
}
```

---

## 🎯 Application Layer Classes

### DTOs/CreateEnvironmentDto.cs
```csharp
namespace DbTool.Application.DTOs;

public record CreateEnvironmentDto(
    string Name,
    string Engine,
    string Host,
    int Port,
    string DatabaseName,
    string Username,
    string Password
);
```

### Interfaces/IEnvironmentService.cs
```csharp
namespace DbTool.Application.Interfaces;

public interface IEnvironmentService
{
    Task<int> CreateEnvironmentAsync(CreateEnvironmentDto dto);
    Task<IEnumerable<EnvironmentDto>> GetAllEnvironmentsAsync();
    Task<EnvironmentDto?> GetEnvironmentByNameAsync(string name);
    Task<bool> DeleteEnvironmentAsync(string name);
}
```

### UseCases/Environment/CreateEnvironmentUseCase.cs
```csharp
namespace DbTool.Application.UseCases.Environment;

public class CreateEnvironmentUseCase
{
    private readonly IEnvironmentRepository _repository;
    private readonly IValidator<CreateEnvironmentDto> _validator;

    public CreateEnvironmentUseCase(
        IEnvironmentRepository repository,
        IValidator<CreateEnvironmentDto> validator)
    {
        _repository = repository;
        _validator = validator;
    }

    public async Task<int> ExecuteAsync(CreateEnvironmentDto dto)
    {
        var validationResult = await _validator.ValidateAsync(dto);
        if (!validationResult.IsValid)
            throw new ValidationException(validationResult.Errors);

        var environment = MapToEntity(dto);
        return await _repository.AddAsync(environment);
    }

    private Domain.Entities.Environment MapToEntity(CreateEnvironmentDto dto)
    {
        // Mapping logic
    }
}
```

---

## 🎯 Infrastructure Layer Classes

### Data/AppDbContext.cs
```csharp
namespace DbTool.Infrastructure.Data;

public class AppDbContext : IDisposable
{
    private readonly SqliteConnection _connection;

    public AppDbContext(string dbPath)
    {
        _connection = new SqliteConnection($"Data Source={dbPath}");
        _connection.Open();
        InitializeDatabase();
    }

    private void InitializeDatabase()
    {
        // Create tables
    }

    public SqliteConnection Connection => _connection;

    public void Dispose() => _connection?.Dispose();
}
```

### Repositories/EnvironmentRepository.cs
```csharp
namespace DbTool.Infrastructure.Repositories;

public class EnvironmentRepository : IEnvironmentRepository
{
    private readonly AppDbContext _context;

    public EnvironmentRepository(AppDbContext context)
    {
        _context = context;
    }

    public async Task<int> AddAsync(Domain.Entities.Environment environment)
    {
        // Implementation using Dapper
    }

    // Other methods...
}
```

---

## 🎯 CLI Layer Classes

### Program.cs
```csharp
using Microsoft.Extensions.DependencyInjection;
using System.CommandLine;

var services = new ServiceCollection();
ConfigureServices(services);
var serviceProvider = services.BuildServiceProvider();

var rootCommand = new RootCommand("DbTool - Multi-Engine Database Backup Tool");

// Add commands
var envCommand = new EnvCommand(serviceProvider);
rootCommand.AddCommand(envCommand.Build());

return await rootCommand.InvokeAsync(args);

void ConfigureServices(IServiceCollection services)
{
    // Register all dependencies
}
```

---

## ✅ Next Steps

After setting up the structure:

1. Copy the class definitions above into their respective files
2. Implement the mapping logic
3. Add validation rules
4. Wire up dependency injection
5. Test each layer independently

Would you like me to generate the complete implementation for any specific layer?
