#!/usr/bin/env bash
# Moved to scripts/; original behavior preserved.
set -euo pipefail

SCRIPT_NAME=$(basename "$0")

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [--check | --install]

Options:
  --check     Only check if required commands are available.
  --install   Attempt to install missing packages using apt-get (Debian/Ubuntu/WSL).

Commands required by backup.sh:
  - pg_dump   (package: postgresql-client)
  - stat      (package: coreutils)
  - md5sum    (package: coreutils)
  - crc32     (optional, package: libarchive-zip-perl)

Examples:
  $SCRIPT_NAME --check
  sudo $SCRIPT_NAME --install

EOF
}

ensure_apt() {
    if ! command -v apt-get >/dev/null 2>&1; then
        echo "ERROR: apt-get not found. This script only supports Debian/Ubuntu/WSL."
        exit 1
    fi
}

check_cmd() {
    local cmd="$1"
    local pkg="$2"

    if command -v "$cmd" >/dev/null 2>&1; then
        echo "[OK]      $cmd (from package '$pkg' or similar)"
        return 0
    else
        echo "[MISSING] $cmd (recommended package: '$pkg')"
        return 1
    fi
}

install_pkg() {
    local pkg="$1"
    echo "Installing package '$pkg' via apt-get..."
    apt-get update
    apt-get install -y "$pkg"
}

main() {
    if (( $# != 1 )); then
        usage
        exit 1
    fi

    local mode="$1"

    case "$mode" in
        --check)
            echo "Checking required commands..."
            check_cmd "pg_dump" "postgresql-client" || true
            check_cmd "stat" "coreutils" || true
            check_cmd "md5sum" "coreutils" || true
            check_cmd "crc32" "libarchive-zip-perl" || true
            ;;
        --install)
            ensure_apt
            echo "Installing required packages for backup.sh..."
            install_pkg "postgresql-client"
            install_pkg "coreutils"
            echo "Installing optional package for 'crc32' (libarchive-zip-perl)..."
            install_pkg "libarchive-zip-perl" || {
                echo "WARN: could not install 'libarchive-zip-perl'. 'crc32' will remain unavailable."
            }
            echo "Done. You can now run ./tool.sh backup --dev or --prod"
            ;;
        *)
            usage
            exit 1
            ;;
    esac
}

main "$@"
