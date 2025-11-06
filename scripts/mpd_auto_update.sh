#!/usr/bin/env bash
# ==========================================================
# 🔄 MPD AUTO-UPDATE - inotifywait para actualizar MPD al añadir música
# Se ejecuta como servicio systemd user
# ==========================================================

set -euo pipefail

MUSIC_DIR="${MUSIC_DIR:-$HOME/Musica}"
MPD_SOCKET="${MPD_SOCKET:-~/.config/mpd/socket}"
LOG_FILE="${LOG_FILE:-$HOME/.config/tdo/mpd_auto_update.log}"
PID_FILE="${PID_FILE:-$HOME/.config/tdo/mpd_auto_update.pid}"

# Crear directorio de logs
mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Verificar que MPD está corriendo
check_mpd() {
    if [[ -S "$MPD_SOCKET" ]]; then
        MPD_HOST="$MPD_SOCKET" mpc status &>/dev/null
    else
        mpc --host 127.0.0.1 --port 6601 status &>/dev/null
    fi
}

# Función para actualizar MPD
update_mpd() {
    log "Cambios detectados en $MUSIC_DIR, actualizando MPD..."
    
    if [[ -S "$MPD_SOCKET" ]]; then
        MPD_HOST="$MPD_SOCKET" mpc update &>/dev/null
    else
        mpc --host 127.0.0.1 --port 6601 update &>/dev/null
    fi
    
    if [[ $? -eq 0 ]]; then
        log "MPD actualizado correctamente"
    else
        log "ERROR: Falló la actualización de MPD"
    fi
}

# Manejo de señales
cleanup() {
    log "Recibida señal de terminación, limpiando..."
    rm -f "$PID_FILE"
    exit 0
}
trap cleanup SIGTERM SIGINT

# Verificar que ya no está corriendo
if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE" 2>/dev/null)" 2>/dev/null; then
    echo "Ya hay una instancia corriendo (PID: $(cat "$PID_FILE"))"
    exit 1
fi

# Guardar PID
echo $$ > "$PID_FILE"

# Verificar MPD al inicio
if ! check_mpd; then
    log "ERROR: MPD no está corriendo. Abortando."
    rm -f "$PID_FILE"
    exit 1
fi

log "Iniciando watcher en $MUSIC_DIR"

# Usar inotifywait para vigilar cambios
# -r: recursivo
# -m: monitor (no salir tras primer evento)
# -e: eventos a vigilar
# --format: formato de salida
# --exclude: excluir archivos temporales
inotifywait -r -m \
    -e create -e delete -e modify -e move \
    --format '%w%f %e' \
    --exclude '\.(tmp|temp|swp|swx|part|crdownload)$' \
    "$MUSIC_DIR" | while read -r file event; do
    
    # Filtrar solo archivos de audio
    if [[ "$file" =~ \.(mp3|ogg|flac|wav|m4a|mp4|opus|ape|wv)$ ]]; then
        log "Evento: $event en $file"
        update_mpd
    fi
done