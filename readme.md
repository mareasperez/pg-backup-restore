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

Run everything via the central entry point (each operation now performs a pre-connection test `SELECT 1` before proceeding):

```
./tool.sh backup --dev   # shows live progress (size, speed, ETA if possible)
./tool.sh backup --prod

./tool.sh restore --dev
./tool.sh restore --prod
./tool.sh restore-latest --dev   # skip choose, still confirms DB name
./tool.sh restore-latest --prod

./tool.sh list --dev      # show backups without restoring
./tool.sh list --prod

./tool.sh drop --dev --yes
./tool.sh drop --prod --skip-backup   # dangerous

./tool.sh deps --check
sudo ./tool.sh deps --install
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

# 5. Restore Script (`scripts/restore_db.sh`)

```
./restore_db.sh --dev
./restore_db.sh --prod
```

Flow:

1. Finds the latest backup  
2. Shows metadata  
3. If rejected → lists all backups  
     4. Requires typing DB name to confirm restore  

Restores using `pg_restore --clean --verbose -F c`.

### Restore Progress & ETA

By default a dynamic progress line appears:

```
Elapsed mm:ss | Items current/total | ETA mm:ss (or HH:MM:SS)
```

Details:
- Total: counted from `pg_restore -l <dump>` (TOC entries). If count unavailable shows `Items x/0` and ETA is `-`.
- Items increment when a TOC entry is processed (creating, processing, restoring, setting).
- ETA is based on average items/sec after 5s; suppressed (`-`) if unstable or oversized (>12h).
- Use `--no-progress` to disable progress; `--show-lines` to also display the last verbose line inline.

Flags added:
- `--no-progress` disables the progress/ETA line.
- `--show-lines` shows the most recent pg_restore verbose line together with counters.

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
./tool.sh backup --dev
./tool.sh backup --prod
```

Restore:

```
./tool.sh restore --dev
./tool.sh restore --prod
./tool.sh list --dev
./tool.sh list --prod
```

Drop:

```
./tool.sh drop --dev
./tool.sh drop --prod
```

Dependencies:

```
sudo ./tool.sh deps --install
./tool.sh deps --check
```
