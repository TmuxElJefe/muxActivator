#!/bin/bash

# Configuration
DEVICE_PORT=22               # Port for SSH connection (default for iproxy)
LOCAL_PORT=2222              # Local port for iproxy forwarding
IPHONE_IP="127.0.0.1"        # Localhost for iproxy
SSH_USER="root"              # Default SSH user for jailbroken iPhones
BACKUP_DIR="./iPhoneBackup"  # Local directory to store backups
LOG_FILE="./backup.log"      # Log file for the script

# Files and directories to backup
FILES_TO_BACKUP=(
    "/var/root/Library/Lockdown" # Activation files
    "/var/root/SHSH"            # SHSH blobs (example path, adjust as needed)
)

# Ensure the backup directory exists
mkdir -p "$BACKUP_DIR"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Function to start iproxy
start_iproxy() {
    log "Starting iproxy to forward port $LOCAL_PORT to $DEVICE_PORT..."
    iproxy "$LOCAL_PORT" "$DEVICE_PORT" &
    IPROXY_PID=$!
    sleep 2
}

# Function to stop iproxy
stop_iproxy() {
    log "Stopping iproxy..."
    kill "$IPROXY_PID" 2>/dev/null
}

# Function to check SSH connection
check_ssh_connection() {
    log "Checking SSH connection to $IPHONE_IP on port $LOCAL_PORT..."
    if ssh -o BatchMode=yes -o ConnectTimeout=5 -p "$LOCAL_PORT" "$SSH_USER@$IPHONE_IP" "exit" 2>/dev/null; then
        log "SSH connection successful."
    else
        log "Error: Unable to connect to $IPHONE_IP via SSH on port $LOCAL_PORT."
        stop_iproxy
        exit 1
    fi
}

# Function to backup files
backup_files() {
    log "Starting backup process..."
    for FILE in "${FILES_TO_BACKUP[@]}"; do
        log "Backing up $FILE..."
        if scp -P "$LOCAL_PORT" -r "$SSH_USER@$IPHONE_IP:$FILE" "$BACKUP_DIR"; then
            log "Successfully backed up $FILE."
        else
            log "Error: Failed to backup $FILE."
        fi
    done
    log "Backup process completed."
}

# Main script execution
log "Starting backup script..."
start_iproxy
check_ssh_connection
backup_files
stop_iproxy

log "All tasks completed. Backups are stored in $BACKUP_DIR."