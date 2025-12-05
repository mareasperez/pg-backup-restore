using DbTool.Application.Interfaces;
using DbTool.Application.Settings;
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
        services.AddSingleton(sp =>
        {
            var settings = sp.GetService<Microsoft.Extensions.Options.IOptions<DbToolSettings>>();
            var configPath = dbPath ?? settings?.Value.Database.ConfigDatabasePath;
            return new AppDbContext(configPath);
        });

        // Register Repositories
        services.AddScoped<IDatabaseConnectionRepository, DatabaseConnectionRepository>();
        services.AddScoped<IBackupRepository, BackupRepository>();

        // Register Services
        services.AddScoped<IDatabaseConnectionService, DatabaseConnectionService>();
        services.AddScoped<IBackupService, BackupService>();
        services.AddSingleton<ICompressionService, GzipCompressionService>();

        // Register Validators
        services.AddValidatorsFromAssemblyContaining<CreateDatabaseConnectionValidator>();

        return services;
    }
}
