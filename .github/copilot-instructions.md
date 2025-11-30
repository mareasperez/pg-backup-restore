# AI Coding Agent Instructions for `pg-backup-restore`

These instructions capture project-specific patterns so an AI agent can work safely and productively. Keep changes tightly scoped and follow existing script conventions.

## Core Purpose & Flow
- Toolkit of Bash scripts to safely backup, restore, and reset PostgreSQL databases across `dev` and `prod` environments.
- Runtime support: Linux or Windows Subsystem for Linux (WSL) only. Do not attempt to run in Windows PowerShell or non-WSL terminals.
- Primary scripts: `backup.sh`, `restore_db.sh`, `drop_all_tables.sh`, `backup_deps.sh`. Older/legacy helpers (`pg_dump.sh`, `pg_restore.sh`, `restore_on_dev.sh`) exist but new work should extend the primary scripts.
- Backup artifacts live under `backups/<env>/<timestamp>/` with `<env>.dump` and `<env>.meta` plus a top-level `transfer.dump` copy for convenience.

## Script Conventions
- Always start new scripts with: `#!/usr/bin/env bash` and `set -euo pipefail`.
- All commands and examples assume a POSIX Bash shell. On Windows, use WSL.
- Provide a `usage()` function and validate args early; exit with helpful error messages via a centralized `error()` or `log()` pattern.
- Use environment selection flags: `--dev` / `--prod` (short forms `-d` / `-p`); do NOT invent new environment flag names.
- Load env files using `set -a; source file; set +a` and validate required vars `DB_HOST DB_USERNAME DB_PASSWORD DB_DATABASE` before destructive or external operations.
- Never echo raw passwords; follow masking pattern from `restore_db.sh` (`DB_PASSWORD` displayed as `********`).

## Logging & Safety
- `backup.sh` implements file logging: reuse `LOG_FILE` and append instead of creating bespoke logs.
- Destructive operations (drop / restore) must require explicit confirmation by typing the database name (see `restore_db.sh` and `drop_all_tables.sh`). Maintain this safety affordance if extending behavior.
- Preserve pre-drop automatic backup in `drop_all_tables.sh`; only bypass with `--skip-backup` (already flagged as dangerous). Do NOT add shortcuts that weaken safety without an equally explicit flag.

## Dependency Handling
- Dependency checks abstracted in `backup_deps.sh`. If adding new required binaries, append them there with both `--check` and `--install` logic (Debian/Ubuntu/WSL only).
- Current required commands: `pg_dump`, `pg_restore`, `psql`, `stat`, `md5sum`. Optional: `crc32`.

## Backup Metadata Pattern
- Metadata file `<env>.meta` contains: date, environment, DB identifiers, file size, MD5, CRC32 (or `N/A`). Match the key naming style exactly (see `backup.sh`). If you add metadata keys, append lines; do not reorder existing ones.
- Elapsed time tracking uses `$SECONDS` and `show_elapsed_time` for progress. Reuse helper rather than re-implementing timers.

## Configuration Overrides
- Respect existing override env vars: `CONFIG_FILE_PATH`, `BACKUP_ROOT`, `LOG_FILE`. When adding features, allow these to continue working; do not hardcode paths.
- Use `CONFIG_FILE_PATH` if supplied; fall back to `<scriptpath>/<env>.env`.

## Environment Files & Secrets
- `dev.env` / `prod.env` contain live credentials—treat as sensitive. Never print, commit modifications with real secrets, or include them in examples. Use `example_env` for new variable templates.
- If suggesting improvements, propose using an `example_env` pattern, not editing real secrets.

## Restore & Drop Patterns
- Restores use `pg_restore --clean --verbose -F c <dump>` optionally with port (`-p`) if `DB_PORT` set. Keep this invocation form for consistency.
- Schema reset uses: `DROP SCHEMA public CASCADE; CREATE SCHEMA public;` (not individual table drops). Follow this if expanding reset logic.

## Adding New Functionality (Examples)
- Example: Add compression of dump after creation: run `pg_dump` as now → compress (`gzip -9 <file>`) → update metadata with `Original size` and `Compressed size` while keeping MD5 of compressed artifact separate (`Compressed MD5`). Place compressed file alongside dump or behind a flag `--compress`.
- Example: Add `--list` flag to `restore_db.sh` to show backups without performing restore: reuse listing logic in `list_backups_and_select`; ensure no confirmation prompt triggers actual restore.

## Style & Structure
- Keep functions grouped under commented section headers (`################################` blocks) matching existing scripts.
- Use snake_case for function names and uppercase for exported configuration variables.
- Avoid subshell complexity unless needed (pattern in `backup.sh` for `pg_dump` with `PGPASSWORD`).

## Legacy Scripts
- `pg_dump.sh`, `pg_restore.sh`, `restore_on_dev.sh` are simpler and partially duplicate functionality. Prefer enhancing `backup.sh` / `restore_db.sh` instead of touching legacy files; if deprecating, add a top comment: `# DEPRECATED: use backup.sh / restore_db.sh`.

## Testing & Verification
- Quick manual test (dev) from Linux/WSL: `CONFIG_FILE_PATH=dev.env ./backup.sh --dev` then `./restore_db.sh --dev` and confirm DB name. Check new timestamp directory and metadata integrity.
- To validate dependency changes: `./backup_deps.sh --check` before and after modification.

## Do Not
- Do not remove confirmation prompts in destructive paths.
- Do not output passwords or secrets in logs/metadata.
- Do not change existing file naming (`dev.dump`, `prod.dump`, `transfer.dump`).
- Do not introduce interactive UI requiring tools beyond POSIX/Bash.
- Do not run or validate commands in Windows PowerShell; use WSL or native Linux.

---
If any area seems ambiguous (e.g., adding encryption, retention policies, or container usage), ask for clarification before implementing. Please review and indicate sections needing adjustment or expansion.
