# DbTool - N-Tier Architecture Setup Guide

This guide will walk you through setting up the DbTool project with a proper N-tier architecture.

## 🏗️ Architecture Overview

```
DbTool/
├── src/
│   ├── DbTool.Domain          # Entities, Interfaces, Enums (no external dependencies)
│   ├── DbTool.Application     # Use Cases, DTOs, Service Interfaces
│   ├── DbTool.Infrastructure  # Implementations (SQLite, Providers, File I/O)
│   ├── DbTool.CLI             # Console Interface
│   └── DbTool.UI              # (Future) Graphical Interface
└── tests/
    ├── DbTool.Domain.Tests
    ├── DbTool.Application.Tests
    └── DbTool.Infrastructure.Tests
```

**Dependency Flow:**
```
CLI → Application → Infrastructure → Domain
UI  → Application → Infrastructure → Domain
```

---

## 📋 Step-by-Step Setup

### Step 1: Clean Start (Optional)

If you want to start fresh, delete the current DbTool folder and create a new one:

```powershell
cd c:\Users\marea\OneDrive\Documentos\projects\bash\pg-backup-restore
Remove-Item -Recurse -Force DbTool
mkdir DbTool
cd DbTool
```

**Or** if you want to keep the current structure, just navigate to DbTool:

```powershell
cd c:\Users\marea\OneDrive\Documentos\projects\bash\pg-backup-restore\DbTool
```

---

### Step 2: Create Solution

```powershell
dotnet new sln -n DbTool
```

**Expected output:** `The template "Solution File" was created successfully.`

---

### Step 3: Create Domain Layer (Core Business Entities)

```powershell
dotnet new classlib -n DbTool.Domain -o src/DbTool.Domain
```

**What goes here:**
- Entities: `Environment`, `Backup`, `DatabaseEngine`
- Interfaces: `IDatabaseProvider`, `IEnvironmentRepository`, `IBackupRepository`
- Enums: `BackupStatus`, `DatabaseEngineType`
- **NO external dependencies** (pure C#)

---

### Step 4: Create Application Layer (Business Logic)

```powershell
dotnet new classlib -n DbTool.Application -o src/DbTool.Application
```

**What goes here:**
- Use Cases: `CreateBackupUseCase`, `RestoreBackupUseCase`, `ManageEnvironmentUseCase`
- DTOs: `CreateEnvironmentDto`, `BackupResultDto`
- Service Interfaces: `IBackupService`, `IConfigService`
- Validators (FluentValidation)

---

### Step 5: Create Infrastructure Layer (Implementations)

```powershell
dotnet new classlib -n DbTool.Infrastructure -o src/DbTool.Infrastructure
```

**What goes here:**
- Database Context: `AppDbContext`
- Repositories: `EnvironmentRepository`, `BackupRepository`
- Providers: `PostgresProvider`, `MySqlProvider`
- External Services: `ToolDownloader`, `FileService`

---

### Step 6: Create CLI Layer (User Interface)

```powershell
dotnet new console -n DbTool.CLI -o src/DbTool.CLI
```

**What goes here:**
- Commands: `EnvCommand`, `BackupCommand`, `RestoreCommand`
- Dependency Injection setup
- Entry point (`Program.cs`)

---

### Step 7: Add Projects to Solution

```powershell
dotnet sln add src/DbTool.Domain/DbTool.Domain.csproj
dotnet sln add src/DbTool.Application/DbTool.Application.csproj
dotnet sln add src/DbTool.Infrastructure/DbTool.Infrastructure.csproj
dotnet sln add src/DbTool.CLI/DbTool.CLI.csproj
```

**Verify:** Run `dotnet sln list` to see all projects.

---

### Step 8: Set Up Project References

```powershell
# Application depends on Domain
dotnet add src/DbTool.Application reference src/DbTool.Domain

# Infrastructure depends on Domain and Application
dotnet add src/DbTool.Infrastructure reference src/DbTool.Domain
dotnet add src/DbTool.Infrastructure reference src/DbTool.Application

# CLI depends on Application and Infrastructure
dotnet add src/DbTool.CLI reference src/DbTool.Application
dotnet add src/DbTool.CLI reference src/DbTool.Infrastructure
```

---

### Step 9: Create Test Projects (Optional but Recommended)

```powershell
dotnet new xunit -n DbTool.Domain.Tests -o tests/DbTool.Domain.Tests
dotnet new xunit -n DbTool.Application.Tests -o tests/DbTool.Application.Tests
dotnet new xunit -n DbTool.Infrastructure.Tests -o tests/DbTool.Infrastructure.Tests

dotnet sln add tests/DbTool.Domain.Tests/DbTool.Domain.Tests.csproj
dotnet sln add tests/DbTool.Application.Tests/DbTool.Application.Tests.csproj
dotnet sln add tests/DbTool.Infrastructure.Tests/DbTool.Infrastructure.Tests.csproj

# Add references to test projects
dotnet add tests/DbTool.Domain.Tests reference src/DbTool.Domain
dotnet add tests/DbTool.Application.Tests reference src/DbTool.Application
dotnet add tests/DbTool.Infrastructure.Tests reference src/DbTool.Infrastructure
```

---

### Step 10: Install NuGet Packages

#### Domain Layer (NO packages - keep it pure)
```powershell
# No packages needed - this layer should have zero external dependencies
```

#### Application Layer
```powershell
cd src/DbTool.Application
dotnet add package FluentValidation
cd ../..
```

#### Infrastructure Layer
```powershell
cd src/DbTool.Infrastructure
dotnet add package Microsoft.Data.Sqlite
dotnet add package Dapper
cd ../..
```

#### CLI Layer
```powershell
cd src/DbTool.CLI
dotnet add package System.CommandLine --version 2.0.0-beta4.22272.1
dotnet add package Microsoft.Extensions.DependencyInjection
dotnet add package Microsoft.Extensions.Logging.Console
cd ../..
```

---

### Step 11: Verify the Setup

```powershell
# Build the entire solution
dotnet build

# List all projects
dotnet sln list
```

**Expected output:** All projects should build successfully.

---

### Step 12: Create .gitignore

```powershell
# Create a .gitignore file
dotnet new gitignore
```

---

## 📦 Package Summary

| Layer | Packages |
|-------|----------|
| **Domain** | None (pure C#) |
| **Application** | FluentValidation |
| **Infrastructure** | Microsoft.Data.Sqlite, Dapper |
| **CLI** | System.CommandLine, Microsoft.Extensions.DependencyInjection, Microsoft.Extensions.Logging.Console |

---

## 🎯 Layer Responsibilities

### **DbTool.Domain**
- ✅ Entity definitions
- ✅ Repository interfaces
- ✅ Provider interfaces
- ✅ Enums and value objects
- ❌ NO implementations
- ❌ NO external packages

### **DbTool.Application**
- ✅ Use case orchestration
- ✅ DTOs (Data Transfer Objects)
- ✅ Service interfaces
- ✅ Business validation rules
- ❌ NO database code
- ❌ NO UI code

### **DbTool.Infrastructure**
- ✅ Database implementations (SQLite)
- ✅ Repository implementations
- ✅ Provider implementations (PostgresProvider, etc.)
- ✅ File system operations
- ✅ External tool management

### **DbTool.CLI**
- ✅ Command definitions
- ✅ Dependency injection configuration
- ✅ User input/output
- ❌ NO business logic

---

## ✅ Verification Checklist

After completing all steps, verify:

- [ ] Solution builds without errors: `dotnet build`
- [ ] All projects are in the solution: `dotnet sln list`
- [ ] Project references are correct (no circular dependencies)
- [ ] NuGet packages are installed in the correct layers
- [ ] Domain layer has NO external dependencies

---

## 🚀 Next Steps

Once the structure is ready:

1. Define entities in `DbTool.Domain`
2. Define interfaces in `DbTool.Domain`
3. Implement use cases in `DbTool.Application`
4. Implement repositories and providers in `DbTool.Infrastructure`
5. Create CLI commands in `DbTool.CLI`

---

## 📞 Need Help?

If you encounter any issues:
- Check that .NET 8 SDK is installed: `dotnet --version`
- Ensure you're in the correct directory
- Verify project references: `dotnet list reference`
