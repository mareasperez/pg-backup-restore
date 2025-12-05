# Configuration System - Options Pattern

## ✅ Implementación Completada

El sistema de configuración ahora usa el **Options Pattern** de .NET, siguiendo las mejores prácticas.

---

## 📋 Configuración (`appsettings.json`)

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

---

## 🏗️ Arquitectura - Options Pattern

### Modelo de Configuración

```csharp
public class DbToolSettings
{
    public BackupSettings Backup { get; set; } = new();
    public DatabaseSettings Database { get; set; } = new();
}

public class BackupSettings
{
    public bool EnableCompression { get; set; } = false;
    public string CompressionLevel { get; set; } = "Optimal";
    public string DefaultBackupDirectory { get; set; } = "./backups";
}
```

### Registro en DI (Program.cs)

```csharp
// Load configuration
var configuration = new ConfigurationBuilder()
    .SetBasePath(Directory.GetCurrentDirectory())
    .AddJsonFile("appsettings.json", optional: true, reloadOnChange: true)
    .Build();

var services = new ServiceCollection();

// Configure Options Pattern ✅
services.Configure<DbToolSettings>(configuration.GetSection("DbTool"));

services.AddInfrastructure();
```

### Inyección en Servicios

```csharp
public class BackupService : IBackupService
{
    private readonly DbToolSettings _settings;

    public BackupService(
        IDatabaseConnectionRepository connectionRepository,
        IBackupRepository backupRepository,
        ICompressionService compressionService,
        IOptions<DbToolSettings> options)  // ✅ Options Pattern
    {
        _settings = options.Value;
        // ...
    }
}
```

---

## ✨ Ventajas del Options Pattern

✅ **Strongly Typed** - Configuración con tipos seguros  
✅ **Validation** - Soporte para validación de configuración  
✅ **Reload on Change** - Recarga automática cuando cambia el archivo  
✅ **Testeable** - Fácil de mockear en tests  
✅ **Best Practice** - Patrón recomendado por Microsoft  
✅ **IOptionsSnapshot** - Soporte para configuración por request (futuro)  
✅ **IOptionsMonitor** - Soporte para cambios en tiempo real (futuro)  

---

## 🔧 Opciones de Configuración

### Compresión

| Opción | Valores | Default | Descripción |
|--------|---------|---------|-------------|
| `EnableCompression` | `true`/`false` | `false` | Activa compresión gzip |
| `CompressionLevel` | `Optimal`, `Fastest`, `SmallestSize`, `NoCompression` | `Optimal` | Nivel de compresión |
| `DefaultBackupDirectory` | string | `./backups` | Directorio por defecto |

### Base de Datos

| Opción | Valores | Default | Descripción |
|--------|---------|---------|-------------|
| `ConfigDatabasePath` | string o `null` | `null` | Ruta personalizada para config.db |

---

## 📝 Ejemplos de Configuración

### Desarrollo (Sin Compresión)

```json
{
  "DbTool": {
    "Backup": {
      "EnableCompression": false,
      "DefaultBackupDirectory": "./backups"
    }
  }
}
```

### Producción (Con Compresión)

```json
{
  "DbTool": {
    "Backup": {
      "EnableCompression": true,
      "CompressionLevel": "Optimal",
      "DefaultBackupDirectory": "/var/backups/dbtool"
    },
    "Database": {
      "ConfigDatabasePath": "/etc/dbtool/config.db"
    }
  }
}
```

### Máxima Compresión

```json
{
  "DbTool": {
    "Backup": {
      "EnableCompression": true,
      "CompressionLevel": "SmallestSize"
    }
  }
}
```

---

## 🚀 Futuras Mejoras

Con Options Pattern implementado, es fácil agregar:

- **IOptionsSnapshot** - Configuración por scope
- **IOptionsMonitor** - Notificaciones de cambios
- **Validation** - Validación de configuración con DataAnnotations
- **Named Options** - Múltiples configuraciones con nombres
- **Post-Configure** - Modificación de opciones después de carga

---

## ✅ Estado

- ✅ Options Pattern implementado
- ✅ Configuración cargada desde appsettings.json
- ✅ Inyección con `IOptions<DbToolSettings>`
- ✅ Soporte para reload on change
- ✅ Build exitoso
- ✅ Backward compatible
