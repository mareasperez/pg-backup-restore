# Migration Tasks: Bash to C# (DbTool)

## Planning & Setup
- [ ] Create implementation plan (`implementation_plan.md`)
- [ ] Initialize .NET Solution (`DbTool.sln`)
- [ ] Create `DbTool.Core` (Class Library)
- [ ] Create `DbTool.CLI` (Console App)
- [ ] Configure `.gitignore` and project references

## Core Infrastructure (Local DB)
- [ ] Install `Microsoft.Data.Sqlite` and Dapper/EF Core
- [ ] Create `AppDbContext` and Database Initialization (Migrations/EnsureCreated)
- [ ] Implement `EnvironmentRepository` (CRUD for environments)
- [ ] Create CLI commands for Environment Management (`env add`, `env list`, `env remove`)

## Core Logic (Provider Pattern)
- [ ] Define `IDatabaseProvider` interface
- [ ] Implement `PostgresProvider` (Port logic from `backup.sh` and `restore_db.sh`)
- [ ] Implement `ProviderFactory`

## Feature Implementation
- [ ] Implement `BackupCommand` (Logic to fetch env, get provider, run backup)
- [ ] Implement `RestoreCommand`
- [ ] Implement `DropCommand` (with safety checks)
- [ ] Implement `SyncCommand` (Prod -> Dev flow)
- [ ] Implement `ToolDownloader` service (Download pg_dump/etc)
- [ ] Implement `DriversCommand` (CLI for downloading tools)

## Verification & Polish
- [ ] Verify Self-Contained Build (Windows/Linux)
- [ ] Test with local PostgreSQL instance
- [ ] Create `README.md` with new usage instructions
