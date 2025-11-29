# Database Backup & Restore Toolkit

This repository contains a safe and consistent set of scripts for:

- **Entry point** `tool.sh` to run all operations
- **Backing up** PostgreSQL databases (`scripts/backup.sh`)
- **Restoring** a chosen backup (`scripts/restore_db.sh`)
- **Dropping all tables** (with automatic pre-drop backup) (`scripts/drop_all_tables.sh`)
- **Installing/checking dependencies** (`scripts/backup_deps.sh`)

The scripts are designed for Linux/WSL environments and use **dev/prod** flags for environment isolation.

---

## 📌 Folder Structure

```
 project/
  ├── tool.sh
  ├── dev.env
  ├── prod.env
  ├── scripts/
  │   ├── backup.sh
  │   ├── restore_db.sh
  │   ├── drop_all_tables.sh
  │   └── backup_deps.sh
  └── backups/
      ├── dev/
      │    └── <TIMESTAMP>/
      │         ├── dev.dump
      │         └── dev.meta
      └── prod/
           └── <TIMESTAMP>/
                ├── prod.dump
                └── prod.meta
```

---

# 1. Environment Files

Each environment (`dev` or `prod`) requires its own `.env` file.

Example `dev.env`:

```
DB_DATABASE=myapp_dev
DB_HOST=localhost
DB_USERNAME=postgres
DB_PASSWORD=password123
DB_PORT=5432
```

Example `prod.env`:

```
DB_DATABASE=myapp_prod
DB_HOST=10.10.0.15
DB_USERNAME=postgres
DB_PASSWORD=super-secure
DB_PORT=5432
```

---

# 2. Installing Dependencies

Install:

```
sudo ./backup_deps.sh --install
```

Check only:

```
./backup_deps.sh --check
```

Dependencies:

- postgresql-client  
- coreutils  
- libarchive-zip-perl (optional `crc32`)

---

# 3. Central Entry (`tool.sh`)

Run everything via the central entry point (each operation performs a pre-connection test `SELECT 1`). Commands are grouped by workflow for clarity:

```
Prod -> Dev:
     ./tool.sh sync-dev --dev        # Fresh PROD backup then restore into DEV (1 step)
     ./tool.sh refresh-dev --dev     # Use latest existing PROD backup
     ./tool.sh restore-prod --dev    # Choose specific PROD backup → DEV

Dev Restore / Maintenance:
     ./tool.sh restore --dev         # Choose specific DEV backup → DEV
     ./tool.sh drop --dev --yes      # Reset DEV schema (auto pre-drop backup)
     # Hidden: latest dev restore via script: scripts/restore_db.sh --target dev --latest

Backups:
     ./tool.sh backup --prod         # Non-destructive PROD backup
     ./tool.sh backup --dev          # DEV backup
     ./tool.sh list --prod           # List PROD backups
     ./tool.sh list --dev            # List DEV backups

Utilities:
     ./tool.sh deps --check
     sudo ./tool.sh deps --install
     ./tool.sh                        # Interactive menu
```

## 3.1 Global Configuration (`config.ini`)

An optional non-secret settings file loaded before defaults. Precedence: exported env vars > `config.ini` > script defaults. Do NOT store credentials here (keep them in `dev.env` / `prod.env`).

Example:
```
[paths]
BACKUP_ROOT=./backups
LOG_FILE=./backup.log

[formats]
TIMESTAMP_FORMAT=%Y-%m-%d-%H-%M

[progress]
PROGRESS_INTERVAL=1

[restore]
DEFAULT_SOURCE=prod
```

Implemented keys today:
- BACKUP_ROOT: Root directory containing per-environment timestamp folders.
- LOG_FILE: Shared log file for backup runs.
- TIMESTAMP_FORMAT: Naming pattern for new backup folders (existing ones unchanged).
- PROGRESS_INTERVAL: Polling interval hook (currently fixed at 1s; future use).

Override examples (env var precedence):
```
BACKUP_ROOT=/data/bk LOG_FILE=/var/log/db-bk.log ./tool.sh backup --prod
TIMESTAMP_FORMAT=%Y%m%d-%H%M GLOBAL_CONFIG_FILE=/etc/pgtool/config.ini ./tool.sh sync-dev --dev
```

Manual PROD destructive operations (run underlying scripts directly):

```
scripts/restore_db.sh --prod
scripts/drop_all_tables.sh --prod
```

Flags:

- `--config <path>` to override env file (passthrough to scripts)
- `--dev` / `--prod` are required for env selection

# 4. Backup Script (`scripts/backup.sh`)

```
./backup.sh --dev
./backup.sh --prod
```

Creates:

- `<env>.dump`
- `<env>.meta`
- `transfer.dump`
- Timestamped backup folders

### Backup Progress & ETA

During a backup a live progress line is shown:

```
Elapsed mm:ss | Size X.YZ MB | +Δ KB/s | ETA mm:ss
```

Details:
- Size: current dump file size (custom format `-Fc`, may be smaller than raw DB size).
- +Δ KB/s: growth in the last second (simple instantaneous delta).
- ETA: estimated time to completion based on raw database size (`pg_database_size`) and average speed (bytes_so_far / elapsed). Shown as `-` when an estimate is unreliable (early phase or missing size).
- Initial Delay: `pg_dump` may spend several seconds (catalog phase) before file grows; line displays `awaiting dump creation...` until size > 0.

Limitations & Interpretation:
- Early ETAs can be exaggerated or very large because compression and catalog phases distort average speed.
- If speed is very low or raw size cannot be fetched, ETA is suppressed (`-`).
- Raw size is uncompressed; final dump almost always finishes earlier than initial ETA suggests.
- For long-running backups you can safely ignore ETA until a few MB have been written.

Future Improvements (not yet implemented): smoothing speed, HH:MM:SS formatting for large ETAs, optional `--no-progress` flag.

---

# 4. Wrapper Restrictions & Refresh

To reduce risk, the interactive wrapper `tool.sh` forbids destructive production actions:

- Allowed on PROD via wrapper: backups, listing backups, dependency checks.
- Blocked on PROD via wrapper: restore, drop.
- Manual override: call underlying scripts directly for PROD restore or drop (still requires confirmation & pre-drop backup).

Rationale: avoiding accidental production data loss by requiring deliberate, explicit manual script invocation for destructive actions.

### Prod → Dev Workflows (Source/Target Model)

1. Sync (fresh snapshot):
```
./tool.sh sync-dev --dev
```
Performs a new PROD backup then restores it to DEV.

2. Refresh (reuse latest existing backup):
```
./tool.sh refresh-dev --dev
```
Uses the most recent folder under `backups/prod/`.

3. Restore specific PROD backup (interactive list):
```
./tool.sh restore-prod --dev
```
Rejecting the offered latest lists all available PROD timestamps.

Manual equivalents:
```
scripts/restore_db.sh --target dev --source prod --latest   # latest
scripts/restore_db.sh --target dev --source prod            # choose
```

Safety:
- Requires typing the DEV database name.
- Reads PROD artifacts only; never writes to PROD.
- Shows PROD metadata (size, checksums) before confirmation.

# 5. Restore Script (`scripts/restore_db.sh`)

Source/Target interface:
```
./restore_db.sh --target dev --source prod --latest     # Sync / refresh latest
./restore_db.sh --target dev --source prod              # Choose PROD backup
./restore_db.sh --target dev                            # Choose DEV backup
./restore_db.sh --target dev --latest                   # Latest DEV backup (not in menu)
./restore_db.sh --target prod --latest                  # PROD self-restore (manual only)
```

Flow:
1. Load target env file (`<target>.env`).
2. Use backups in `backups/<source>/`.
3. Select latest (or list/select).
4. Show metadata (source env) + confirm typing target DB name.
5. Execute `pg_restore --clean --verbose -F c` with progress.

Progress & ETA
```
Elapsed mm:ss | Items current/total | ETA mm:ss (or HH:MM:SS)
```
Details:
- Total from `pg_restore -l` (TOC entries). If unavailable ETA is `-`.
- ETA starts after 5s based on items/sec; suppressed if oversized (>12h) or unstable.
- `--no-progress` disables line; `--show-lines` adds last verbose line.

List-only mode:

```
./tool.sh list --dev
./tool.sh list --prod
```
Shows available backups and exits without restoring.

---

# 6. Drop Tables Script (`scripts/drop_all_tables.sh`)

```
./drop_all_tables.sh --dev
./drop_all_tables.sh --prod
```

Flow:

1. Loads env  
2. Prompts for confirmation  
3. **Runs backup.sh automatically before drop**  
4. Drops entire `public` schema and recreates it  

Optional but dangerous flags:

```
--yes
--skip-backup
```

---

# 7. Backup Storage Layout

```
backups/<env>/<timestamp>/
 ├── <env>.dump
 └── <env>.meta
```

---

# 8. CI/CD Usage

Backup:

```
CONFIG_FILE_PATH=prod.env ./backup.sh --prod
```

Drop + restore (rare):

```
./drop_all_tables.sh --dev --yes
./restore_db.sh --dev --yes
```

---

# 9. Security Notes

- Passwords never printed
- Dangerous operations require DB name confirmation
- `--skip-backup` should never be used in production

---

# 10. Troubleshooting

Missing binaries:

```
sudo ./backup_deps.sh --install
```

Permission issues:

```
sudo chown -R $USER:$USER backups/
chmod -R 755 backups/
```

---

# 11. Commands Summary

Backup:
```
./tool.sh backup --prod
./tool.sh backup --dev
```

Prod → Dev:
```
./tool.sh sync-dev --dev
./tool.sh refresh-dev --dev
./tool.sh restore-prod --dev
```

Dev Restore:
```
./tool.sh restore --dev
scripts/restore_db.sh --target dev --latest   # latest dev (not shown in menu)
```

Listing:
```
./tool.sh list --prod
./tool.sh list --dev
```

Drop (DEV only):
```
./tool.sh drop --dev
```

Manual PROD drop:
```
scripts/drop_all_tables.sh --prod
```

Manual PROD self-restore:
```
scripts/restore_db.sh --target prod --latest
```

Dependencies:
```
sudo ./tool.sh deps --install
./tool.sh deps --check
```
