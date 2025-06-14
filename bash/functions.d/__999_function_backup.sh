#!/usr/bin/env bash
# backup_system.sh - Advanced Backup Script
# Usage: ./backup_system.sh

set -euo pipefail

# Configuration file path
CONFIG_FILE="$HOME/.config/backup_config"
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
LOG_FILE="/tmp/backup_$(date +%Y%m%d_%H%M%S).log"

# Default configuration
DEFAULT_TARGET_DIR="/backup/daily"
DEFAULT_FALLBACK_DIR="$HOME/backup_fallback"
DEFAULT_EMAIL="admin@localhost"

# Error handling
error_exit() {
    log_error "$1"
    send_notification "Backup FAILED: $1" "error"
    exit 1
}

# Load configuration
load_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Configuration file not found. Creating default configuration at $CONFIG_FILE"
        create_default_config
    fi

    source "$CONFIG_FILE"

    # Validate required variables
    TARGET_DIR="${TARGET_DIR:-$DEFAULT_TARGET_DIR}"
    FALLBACK_DIR="${FALLBACK_DIR:-$DEFAULT_FALLBACK_DIR}"
    EMAIL="${EMAIL:-$DEFAULT_EMAIL}"
    BACKUP_DIRS_FILE="${BACKUP_DIRS_FILE:-$HOME/.config/backup_dirs.txt}"
}

# Create default configuration
create_default_config() {
    mkdir -p "$(dirname "$CONFIG_FILE")"
    cat > "$CONFIG_FILE" << EOF
# Backup Configuration
TARGET_DIR="$DEFAULT_TARGET_DIR"
FALLBACK_DIR="$DEFAULT_FALLBACK_DIR"
EMAIL="$DEFAULT_EMAIL"
BACKUP_DIRS_FILE="$HOME/.config/backup_dirs.txt"
EOF

    # Create default backup directories list
    mkdir -p "$HOME/.config"
    cat > "$HOME/.config/backup_dirs.txt" << EOF
/etc
/home
/var/log
/opt
EOF

    log "Default configuration created. Please edit $CONFIG_FILE and $HOME/.config/backup_dirs.txt"
}

# Check if directory is accessible
check_directory_access() {
    local dir="$1"
    if [[ -d "$dir" ]] && [[ -w "$dir" ]]; then
        return 0
    else
        return 1
    fi
}

# Create backup archive
create_backup() {
    local backup_dirs=()
    local backup_filename="backup_$(hostname)_$(date +%Y%m%d_%H%M%S).tar.gz"

    # Read directories to backup
    if [[ ! -f "$BACKUP_DIRS_FILE" ]]; then
        error_exit "Backup directories file not found: $BACKUP_DIRS_FILE"
    fi

    while IFS= read -r line; do
        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        if [[ -d "$line" ]]; then
            backup_dirs+=("$line")
        else
            log_warn "Directory not found: $line"
        fi
    done < "$BACKUP_DIRS_FILE"

    if [[ ${#backup_dirs[@]} -eq 0 ]]; then
        error_exit "No valid directories found to backup"
    fi

    log_info "Creating backup archive: $backup_filename"
    log_info "Directories to backup: ${backup_dirs[*]}"

    # Create temporary archive
    local temp_archive="/tmp/$backup_filename"

    # Use sudo for reading root-owned files, but handle permissions carefully
    if command -v sudo >/dev/null 2>&1; then
        sudo tar -czf "$temp_archive" "${backup_dirs[@]}" 2>/dev/null || {
            log_error "Failed to create archive with sudo, trying without sudo"
            tar -czf "$temp_archive" "${backup_dirs[@]}" 2>/dev/null || \
                error_exit "Failed to create backup archive"
        }
    else
        tar -czf "$temp_archive" "${backup_dirs[@]}" 2>/dev/null || \
            error_exit "Failed to create backup archive"
    fi

    echo "$temp_archive"
}

# Move backup to destination
move_backup() {
    local archive_path="$1"
    local destination_dir=""
    local used_fallback=false

    # Try target directory first
    if check_directory_access "$TARGET_DIR"; then
        destination_dir="$TARGET_DIR"
        log_info "Using target directory: $TARGET_DIR"
    else
        # Create fallback directory if it doesn't exist
        mkdir -p "$FALLBACK_DIR"
        if check_directory_access "$FALLBACK_DIR"; then
            destination_dir="$FALLBACK_DIR"
            used_fallback=true
            log_info "Target directory not accessible, using fallback: $FALLBACK_DIR"
        else
            error_exit "Neither target nor fallback directory is accessible"
        fi
    fi

    # Move archive to destination
    local final_path="$destination_dir/$(basename "$archive_path")"
    mv "$archive_path" "$final_path" || error_exit "Failed to move backup to destination"

    log_info "Backup successfully moved to: $final_path"
    echo "$destination_dir:$used_fallback"
}

# Clean old backups
clean_old_backups() {
    local backup_dir="$1"
    local days=7

    log_info "Cleaning backups older than $days days in $backup_dir"

    find "$backup_dir" -name "backup_$(hostname)_*.tar.gz" -type f -mtime +$days -exec rm -f {} \; 2>/dev/null || true

    local remaining_count=$(find "$backup_dir" -name "backup_$(hostname)_*.tar.gz" -type f | wc -l)
    log_info "Remaining backups in $backup_dir: $remaining_count"
}

# Send email notification
send_email() {
    local subject="$1"
    local body="$2"

    if command -v mail >/dev/null 2>&1; then
        echo "$body" | mail -s "$subject" "$EMAIL"
        log_info "Email sent to $EMAIL"
    elif command -v sendmail >/dev/null 2>&1; then
        {
            echo "To: $EMAIL"
            echo "Subject: $subject"
            echo ""
            echo "$body"
        } | sendmail "$EMAIL"
        log_info "Email sent via sendmail to $EMAIL"
    else
        log_warn "No mail command available, email not sent"
    fi
}

# Send desktop notification
send_desktop_notification() {
    local message="$1"
    local type="${2:-info}"

    if command -v notify-send >/dev/null 2>&1; then
        case $type in
            "error")
                notify-send -u critical "Backup Error" "$message"
                ;;
            "success")
                notify-send -u normal "Backup Success" "$message"
                ;;
            *)
                notify-send "Backup Info" "$message"
                ;;
        esac
        log_info "Desktop notification sent: $message"
    else
        log_warn "notify-send not available, desktop notification not sent"
    fi
}

# Combined notification function
send_notification() {
    local message="$1"
    local type="${2:-info}"

    # Email notification
    local subject="Backup Report - $(hostname) - $(date)"
    local email_body="$message

Backup completed at: $(date)
Hostname: $(hostname)
Log file: $LOG_FILE

---
Automated Backup System"

    send_email "$subject" "$email_body"
    send_desktop_notification "$message" "$type"
}

# Main backup function
function backup_env() {
    log "Starting backup process"

    # Load configuration
    load_config

    # Create backup
    local archive_path
    archive_path=$(create_backup)

    # Move to destination and get info
    local destination_info
    destination_info=$(move_backup "$archive_path")

    local destination_dir="${destination_info%%:*}"
    local used_fallback="${destination_info##*:}"

    # Clean old backups only if not using fallback
    if [[ "$used_fallback" == "false" ]]; then
        clean_old_backups "$destination_dir"
    else
        log_info "Using fallback directory, skipping cleanup"
    fi

    # Send success notification
    local backup_location
    if [[ "$used_fallback" == "true" ]]; then
        backup_location="fallback directory ($destination_dir)"
    else
        backup_location="target directory ($destination_dir)"
    fi

    local success_message="Backup completed successfully!
Location: $backup_location
Archive: $(basename "$archive_path")"

    send_notification "$success_message" "success"
    log_info "Backup process completed successfully"
}

# Trap for cleanup
cleanup() {
    if [[ -f "$LOG_FILE" ]]; then
        log_info "Backup script finished"
    fi
}

trap cleanup EXIT

