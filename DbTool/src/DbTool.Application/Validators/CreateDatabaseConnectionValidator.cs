using DbTool.Application.DTOs;
using FluentValidation;

namespace DbTool.Application.Validators;

/// <summary>
/// Validator for CreateDatabaseConnectionDto.
/// </summary>
public class CreateDatabaseConnectionValidator : AbstractValidator<CreateDatabaseConnectionDto>
{
    public CreateDatabaseConnectionValidator()
    {
        RuleFor(x => x.Name)
            .NotEmpty().WithMessage("Database connection name is required")
            .MaximumLength(50).WithMessage("Database connection name must not exceed 50 characters")
            .Matches("^[a-zA-Z0-9_-]+$").WithMessage("Database connection name can only contain letters, numbers, hyphens, and underscores");

        RuleFor(x => x.Engine)
            .NotEmpty().WithMessage("Database engine is required")
            .Must(BeValidEngine).WithMessage("Invalid database engine. Supported: postgres, mysql, sqlserver, mariadb");

        RuleFor(x => x.Host)
            .NotEmpty().WithMessage("Host is required");

        RuleFor(x => x.Port)
            .InclusiveBetween(1, 65535).WithMessage("Port must be between 1 and 65535");

        RuleFor(x => x.DatabaseName)
            .NotEmpty().WithMessage("Database name is required");

        RuleFor(x => x.Username)
            .NotEmpty().WithMessage("Username is required");

        RuleFor(x => x.Password)
            .NotEmpty().WithMessage("Password is required");
    }

    private bool BeValidEngine(string engine)
    {
        var validEngines = new[] { "postgres", "postgresql", "mysql", "sqlserver", "mariadb" };
        return validEngines.Contains(engine.ToLowerInvariant());
    }
}
