using DbTool.Application.Interfaces;
using DbTool.Application.Validators;
using DbTool.Domain.Interfaces;
using DbTool.Infrastructure.Data;
using DbTool.Infrastructure.Repositories;
using DbTool.Infrastructure.Services;
using FluentValidation;
using Microsoft.Extensions.DependencyInjection;

namespace DbTool.Infrastructure;

/// <summary>
/// Dependency injection configuration for Infrastructure layer.
/// </summary>
public static class DependencyInjection
{
    public static IServiceCollection AddInfrastructure(this IServiceCollection services, string? dbPath = null)
    {
        // Register DbContext
        services.AddSingleton(sp => new AppDbContext(dbPath));

        // Register Repositories
        services.AddScoped<IDatabaseConnectionRepository, DatabaseConnectionRepository>();
        services.AddScoped<IBackupRepository, BackupRepository>();

        // Register Services
        services.AddScoped<IDatabaseConnectionService, DatabaseConnectionService>();
        services.AddScoped<IBackupService, BackupService>();

        // Register Validators
        services.AddValidatorsFromAssemblyContaining<CreateDatabaseConnectionValidator>();

        return services;
    }
}
