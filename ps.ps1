# Configuration
$DevicePort = 22               # Port for SSH connection (default for iproxy)
$LocalPort = 2222              # Local port for iproxy forwarding
$IphoneIP = "127.0.0.1"        # Localhost for iproxy
$SshUser = "root"              # Default SSH user for jailbroken iPhones
$BackupDir = "./iPhoneBackup"  # Local directory to store backups
$LogFile = "./backup.log"      # Log file for the script

# Files and directories to backup
$FilesToBackup = @(
    "/var/root/Library/Lockdown" # Activation files
    "/var/root/SHSH"            # SHSH blobs (example path, adjust as needed)
)

# Ensure the backup directory exists
if (-not (Test-Path -Path $BackupDir)) {
    New-Item -ItemType Directory -Path $BackupDir | Out-Null
}

# Logging function
function Log {
    param (
        [string]$Message
    )
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "$Timestamp - $Message"
    Write-Host $LogMessage
    Add-Content -Path $LogFile -Value $LogMessage
}

# Function to start iproxy
function Start-IProxy {
    Log "Starting iproxy to forward port $LocalPort to $DevicePort..."
    Start-Process -FilePath "iproxy" -ArgumentList "$LocalPort $DevicePort" -NoNewWindow -PassThru | Out-Null
    Start-Sleep -Seconds 2
}

# Function to stop iproxy
function Stop-IProxy {
    Log "Stopping iproxy..."
    Stop-Process -Name "iproxy" -ErrorAction SilentlyContinue
}

# Function to check SSH connection
function Check-SshConnection {
    Log "Checking SSH connection to $IphoneIP on port $LocalPort..."
    $SshCommand = "ssh -o BatchMode=yes -o ConnectTimeout=5 -p $LocalPort $SshUser@$IphoneIP exit"
    $Result = Invoke-Expression -Command $SshCommand
    if ($LASTEXITCODE -eq 0) {
        Log "SSH connection successful."
    } else {
        Log "Error: Unable to connect to $IphoneIP via SSH on port $LocalPort."
        Stop-IProxy
        Exit 1
    }
}

# Function to backup files
function Backup-Files {
    Log "Starting backup process..."
    foreach ($File in $FilesToBackup) {
        Log "Backing up $File..."
        # Corrected SCP command with proper escaping
        $ScpCommand = "scp -P $LocalPort -r $SshUser@${IphoneIP}:`"$File`" $BackupDir"
        Invoke-Expression -Command $ScpCommand
        if ($LASTEXITCODE -eq 0) {
            Log "Successfully backed up $File."
        } else {
            Log "Error: Failed to backup $File."
        }
    }
    Log "Backup process completed."
}

# Main script execution
Log "Starting backup script..."
Start-IProxy
Check-SshConnection
Backup-Files
Stop-IProxy

Log "All tasks completed. Backups are stored in $BackupDir."