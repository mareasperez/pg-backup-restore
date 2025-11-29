# Database Backup & Restore Toolkit

This repository contains a safe and consistent set of scripts for:

- **Backing up** PostgreSQL databases (`backup.sh`)
- **Restoring** a chosen backup (`restore_db.sh`)
- **Dropping all tables** (with automatic pre-drop backup) (`drop_all_tables.sh`)
- **Installing/checking dependencies** (`backup_deps.sh`)

The scripts are designed for Linux/WSL environments and use **dev/prod** flags for environment isolation.

---

## 📌 Folder Structure

```
project/
 ├── backup.sh
 ├── restore_db.sh
 ├── drop_all_tables.sh
 ├── backup_deps.sh
 ├── dev.env
 ├── prod.env
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

# 3. Backup Script (`backup.sh`)

```
./backup.sh --dev
./backup.sh --prod
```

Creates:

- `<env>.dump`
- `<env>.meta`
- `transfer.dump`
- Timestamped backup folders

---

# 4. Restore Script (`restore_db.sh`)

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

---

# 5. Drop Tables Script (`drop_all_tables.sh`)

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

# 6. Backup Storage Layout

```
backups/<env>/<timestamp>/
 ├── <env>.dump
 └── <env>.meta
```

---

# 7. CI/CD Usage

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

# 8. Security Notes

- Passwords never printed
- Dangerous operations require DB name confirmation
- `--skip-backup` should never be used in production

---

# 9. Troubleshooting

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

# 10. Commands Summary

Backup:

```
./backup.sh --dev
./backup.sh --prod
```

Restore:

```
./restore_db.sh --dev
./restore_db.sh --prod
```

Drop:

```
./drop_all_tables.sh --dev
./drop_all_tables.sh --prod
```

Dependencies:

```
sudo ./backup_deps.sh --install
./backup_deps.sh --check
```
