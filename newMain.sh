#!/bin/bash
# activation_manager.sh
#
# Scopo:
#   Rilevare la modalità di accesso al filesystem (sshramdisk vs recovery)
#   impostare il corretto punto di mount e quindi eseguire il backup (e opzionalmente il ripristino)
#   dei file di attivazione da dispositivi iOS 12.4.8 in modalità pwnDFU (SSH Ramdisk).
#
# Fonti di ispirazione:
#   - SSHRD_Script (https://github.com/verygenericname/SSHRD_Script)
#   - iRevive (https://github.com/Hackt1vator/iRevive)
#   - Guide di LegacyJailbreak (es. r/LegacyJailbreak/wiki/guides/a9ios9activation)
#   - TheAppleWiki (modalità Normal, Recovery, DFU, SSH Ramdisk)
#
# Nota: questo script si concentra sul metodo pwnDFU/sshramdisk.
#
# Configurazione iniziale:
set -euo pipefail

#########################################
# PARAMETRI DI CONNESSIONE
#########################################
SSH_HOST="localhost"
SSH_PORT="2222"   # Porta usata dalla SSH ramdisk
SSH_USER="root"
BACKUP_DIR="$HOME/ios_backup"
REMOTE_MOUNT=""

#########################################
# FUNZIONE: RILEVA MODALITÀ DI ACCESSO AL FILESYSTEM
#########################################
function detect_mode() {
    echo "[*] Rilevamento modalità di accesso..."
    if ssh -p "$SSH_PORT" "$SSH_USER@$SSH_HOST" "test -d '/mnt1/private'" ; then
        MODE="sshramdisk"
        echo "[✓] Modalità rilevata: SSH Ramdisk (o pwnDFU)."
    elif ssh -p "$SSH_PORT" "$SSH_USER@$SSH_HOST" "test -d '/mnt2/private'" ; then
        MODE="recovery"
        echo "[✓] Modalità rilevata: Recovery Mode."
    else
        echo "❌ Impossibile rilevare il punto di mount. Assicurati che il dispositivo sia avviato in una modalità supportata."
        exit 1
    fi
}

#########################################
# FUNZIONE: IMPOSTA IL PUNTO DI MOUNT
#########################################
function set_mount_point() {
    if [ "$MODE" == "sshramdisk" ]; then
        REMOTE_MOUNT="/mnt1"
    elif [ "$MODE" == "recovery" ]; then
        REMOTE_MOUNT="/mnt2"
    fi
    echo "[*] Punto di mount impostato: $REMOTE_MOUNT"
}

#########################################
# FUNZIONE: MONTAGGIO DEL FILESYSTEM (legacy, come in SSHRD_Script)
#########################################
function mount_fs() {
    echo "[*] Tentativo di montare i filesystem sul dispositivo..."
    ssh -p "$SSH_PORT" "$SSH_USER@$SSH_HOST" "command -v mount_filesystems >/dev/null && mount_filesystems || echo 'mount_filesystems non trovato; continuazione...'" || true
}

#########################################
# DEFINIZIONE DEI PATH CANDIDATI
#########################################
declare -a CANDIDATES
declare -a LABELS

# Mappatura dei file di attivazione (iOS 12.4.8):
# 1. Lockdown (root) – percorso classico
CANDIDATES+=("${REMOTE_MOUNT}/private/var/root/Library/Lockdown")
LABELS+=("lockdown_root")

# 2. Lockdown (mobile) – alternativa per alcuni dispositivi
CANDIDATES+=("${REMOTE_MOUNT}/private/var/mobile/Library/Lockdown")
LABELS+=("lockdown_mobile")

# 3. Identity Services (container-based) – tipicamente contiene activation_record.plist
CANDIDATES+=("${REMOTE_MOUNT}/private/var/containers/Data/System/com.apple.identityservices.idstatuscache/Library/Caches")
LABELS+=("idstatuscache_caches")

# 4. Activation Records – ricerca ricorsiva nelle directory container
REMOTE_ACTIVATION_FOLDER=$(ssh -p "$SSH_PORT" "$SSH_USER@$SSH_HOST" "find '${REMOTE_MOUNT}/private/var/containers/Data/system' -iname '*activation_records*' -type d | head -n 1" || echo "")
if [[ -z "$REMOTE_ACTIVATION_FOLDER" ]]; then
    REMOTE_ACTIVATION_FOLDER=$(ssh -p "$SSH_PORT" "$SSH_USER@$SSH_HOST" "find '${REMOTE_MOUNT}/private/var/containers/data/system' -iname '*activation_records*' -type d | head -n 1" || echo "")
fi
CANDIDATES+=("$REMOTE_ACTIVATION_FOLDER")
LABELS+=("activation_records_folder")

# 5. FairPlay – contenente file come data_ark.plist, commcenter.plist, ecc.
CANDIDATES+=("${REMOTE_MOUNT}/private/var/mobile/Library/FairPlay")
LABELS+=("fairplay")

#########################################
# FUNZIONI DI SUPPORTO PER IL BACKUP
#########################################
# Controlla se un percorso remoto esiste
function remote_exists() {
    local path="$1"
    ssh -p "$SSH_PORT" "$SSH_USER@$SSH_HOST" "test -e '$path'" && return 0 || return 1
}

# Esegue il backup scaricando ricorsivamente il contenuto di ogni percorso candidato
function backup_activation() {
    echo "[+] Avvio del backup dei file di attivazione..."
    mkdir -p "$BACKUP_DIR"
    
    local candidate label
    for ((i=0; i<${#CANDIDATES[@]}; i++)); do
        candidate="${CANDIDATES[$i]}"
        label="${LABELS[$i]}"
        if [[ -z "$candidate" ]]; then
            echo "[-] $label: Valore vuoto, salto questo candidato."
            continue
        fi
        echo "[*] Verifica per $label: $candidate"
        if remote_exists "$candidate"; then
            echo "[✓] $label trovato. Inizio download..."
            local target="$BACKUP_DIR/${label}"
            mkdir -p "$target"
            sftp -P "$SSH_PORT" "$SSH_USER@$SSH_HOST" <<EOF
cd "$(dirname "$candidate")"
lcd "$target"
get -r "$(basename "$candidate")"
bye
EOF
            echo "[✓] $label: Backup completato. Salvato in ${target}/$(basename "$candidate")"
        else
            echo "[-] $label: Percorso non trovato sul dispositivo."
        fi
    done
    echo "[✓] Backup terminato. File salvati in $BACKUP_DIR"
}

#########################################
# FUNZIONE DI SUPPORTO PER IL RIPRISTINO (OPZIONALE)
#########################################
function restore_activation() {
    echo "[+] Avvio ripristino dei file di attivazione..."
    if [ ! -d "$BACKUP_DIR" ]; then
        echo "[-] Errore: Nessun backup trovato in $BACKUP_DIR!"
        exit 1
    fi

    # Esempio di ripristino per i file di Lockdown
    sshpass -p "alpine" scp -P "$SSH_PORT" -r "$BACKUP_DIR/lockdown_root/" "$SSH_USER@$SSH_HOST:${REMOTE_MOUNT}/private/var/root/Library/Lockdown/"
    sshpass -p "alpine" scp -P "$SSH_PORT" "$BACKUP_DIR/data_ark.plist" "$SSH_USER@$SSH_HOST:${REMOTE_MOUNT}/private/var/db/lockdown/"
    sshpass -p "alpine" scp -P "$SSH_PORT" "$BACKUP_DIR/com.apple.commcenter.plist" "$SSH_USER@$SSH_HOST:${REMOTE_MOUNT}/private/var/root/Library/Preferences/"
    sshpass -p "alpine" scp -P "$SSH_PORT" "$BACKUP_DIR/com.apple.wifi.plist" "$SSH_USER@$SSH_HOST:${REMOTE_MOUNT}/private/var/wireless/Library/Preferences/"
    echo "[✓] Ripristino completato! Riavvia il dispositivo..."
    ssh -p "$SSH_PORT" "$SSH_USER@$SSH_HOST" "reboot"
}

#########################################
# MENU PRINCIPALE
#########################################
function main() {
    echo "==================================="
    echo "        iOS Activation Manager"
    echo "==================================="
    echo ""
    detect_mode
    set_mount_point
    mount_fs

    echo ""
    echo "Modalità rilevata: $MODE"
    echo "Punto di mount: $REMOTE_MOUNT"
    echo ""
    echo "Seleziona un'operazione:"
    echo "1) Backup file di attivazione (pwnDFU / sshramdisk)"
    echo "2) Ripristino file di attivazione"
    echo "3) Esci"
    read -p "Opzione: " OP

    case "$OP" in
        1) backup_activation ;;
        2) restore_activation ;;
        3) exit 0 ;;
        *) echo "❌ Opzione non valida"; exit 1 ;;
    esac
}

main
