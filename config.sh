#!/usr/bin/env zsh
# ==========================================================
# ⚙️ CONFIGURACIÓN CENTRAL DE TDO-HUB
# ==========================================================

# --- Cargar .env si existe ---
ENV_FILE="${HUB_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]:-${0}}")" && pwd)}/.env"
if [[ -f "$ENV_FILE" ]]; then
    set -a
    source "$ENV_FILE"
    set +a
fi

# --- MODO DEBUG ---
export DEBUG="${DEBUG:-false}"

# --- COLORES ---
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export GREY='\033[0;90m'
export RESET='\033[0m'

# =========== RUTAS ===========
export HUB_ROOT="${HUB_ROOT:-$HOME/.local/bin/tdo-hub}"
export SCRIPTS_DIR="${SCRIPTS_DIR:-$HUB_ROOT/scripts}"
export PHRASES_FILE="${PHRASES_FILE:-$HUB_ROOT/phrases.txt}"
export DISTRACTION_FILE="${DISTRACTION_FILE:-$HUB_ROOT/bloqueo_distraccion.txt}"
export LOG_DIR="${LOG_DIR:-$HOME/.config/focus}"
export LOG_FILE="${LOG_FILE:-$LOG_DIR/$(date +%Y-%m-%d).log}"

# =========== NOTAS ===========
# Genéricos a propósito: TU layout vive en .env (ver .env.example).
# Aquí solo defaults planos para que funcione sin .env.
export NOTES_DIR="${NOTES_DIR:-$HOME/notes}"
export PROJECTS_DIR="${PROJECTS_DIR:-$NOTES_DIR/projects}"
export TODOS_DIR="${TODOS_DIR:-$NOTES_DIR/todos}"
export TODO_ACTIVO="${TODO_ACTIVO:-$TODOS_DIR/todo_ACTIVO.md}"
export JOURNAL_DIR="${JOURNAL_DIR:-$NOTES_DIR/journal}"
export TEMPLATES_DIR="${TEMPLATES_DIR:-$NOTES_DIR/templates}"
export INBOX_DIR="${INBOX_DIR:-$NOTES_DIR/inbox}"
export WORKLOG_DIR="${WORKLOG_DIR:-$NOTES_DIR/worklog}"
export ARCHIVE_DIR="${ARCHIVE_DIR:-$NOTES_DIR/archivo}"

# =========== SCRIPTS ===========
export FOCUS_SCRIPT="${FOCUS_SCRIPT:-$SCRIPTS_DIR/focus_mode.sh}"
export PANIC_SCRIPT="${PANIC_SCRIPT:-$SCRIPTS_DIR/panic_button.sh}"
export TRIAGE_SCRIPT="${TRIAGE_SCRIPT:-$SCRIPTS_DIR/auto-triage.sh}"
export BACKUP_SCRIPT="${BACKUP_SCRIPT:-$SCRIPTS_DIR/backup.sh}"
export SYNC_SCRIPT="${SYNC_SCRIPT:-$SCRIPTS_DIR/sync.sh}"
export STREAK_SCRIPT="${STREAK_SCRIPT:-$SCRIPTS_DIR/streak-tracker.sh}"

# =========== TMUX ===========
export SESSION="${SESSION:-work}"

# =========== PRODUCTIVIDAD ===========
export FOCUS_TRACK="${FOCUS_TRACK:-$HOME/.config/tdo/focus}"
export TODO_TRASH="${TODO_TRASH:-$HUB_ROOT/trash.md}"
export SESSION_LOG="${SESSION_LOG:-$HUB_ROOT/last-session.txt}"

# =========== ACTIVITYWATCH ===========
# Genérico: sin IPs personales. TU servidor vive en .env
# (AW_DEFAULT_SERVER). Orden: SERVER_URL → DEFAULT → FALLBACK_URL
# → FALLBACK_SERVER → localhost. Ver resolve_aw_api() en core.sh.
export AW_BUCKET_WINDOW="${AW_BUCKET_WINDOW:-aw-watcher-window_$(hostname)}"
export AW_BUCKET_VIM="${AW_BUCKET_VIM:-aw-watcher-vim_$(hostname)}"
export AW_DEFAULT_SERVER="${AW_DEFAULT_SERVER:-}"
export AW_FALLBACK_SERVER="${AW_FALLBACK_SERVER:-http://localhost:5600}"

# Nombres de buckets adicionales para otros scripts
export AW_BUCKET_OTRO="${AW_BUCKET_OTRO:-aw-watcher-window_$(hostname)}"

# =========== APLICACIONES ===========
export EDITOR="${EDITOR:-nvim}"

# =========== FUNCIONES ===========
log_msg() {
    local level="$1" message="$2"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    if [ "$DEBUG" = "true" ] || [ "$level" = "ERROR" ]; then
        case "$level" in
            "INFO")  echo -e "${BLUE}[INFO]${RESET} $message" >&2 ;;
            "WARN")  echo -e "${YELLOW}[WARN]${RESET} $message" >&2 ;;
            "ERROR") echo -e "${RED}[ERROR]${RESET} $message" >&2 ;;
            "OK")    echo -e "${GREEN}[OK]${RESET} $message" >&2 ;;
        esac
    fi
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE" 2>/dev/null || true
}

require_command() {
    command -v "$1" &>/dev/null || { log_msg "ERROR" "No encontrado: ${2:-$1}"; return 1; }
}

validate_paths() {
    mkdir -p "$PROJECTS_DIR" "$TODOS_DIR" "$INBOX_DIR" "$WORKLOG_DIR" "$ARCHIVE_DIR"
    mkdir -p "$JOURNAL_DIR" "$LOG_DIR" "$TEMPLATES_DIR"
}

# Parsear tareas con fecha (usado por auto-calendar, calendar-notify, calendar-sync)
parse_tasks() {
    [[ ! -f "$TODO_ACTIVO" ]] && return
    grep -E "^\s*-\s*\[.\].*due:" "$TODO_ACTIVO" | while IFS= read -r line; do
        local task=$(echo "$line" | sed 's/^[[:space:]]*- \[.\] //')
        local due=$(echo "$task" | grep -oE 'due:[0-9]{4}-[0-9]{2}-[0-9]{2}' | cut -d: -f2)
        local desc=$(echo "$task" | sed 's/due:[0-9-]*//; s/!!//; s/!//; s/@[a-zA-Z0-9_-]*//g; s/repeat:[a-z]*//; s/  */ /g; s/^ *//; s/ *$//')
        local done=$(echo "$line" | grep -q "\[x\]" && echo "true" || echo "false")
        local priority="normal"
        echo "$task" | grep -qE '^!!' && priority="high"
        echo "$task" | grep -qE '^!' && [[ "$priority" != "high" ]] && priority="medium"
        local uid=$(echo "$task" | md5sum | cut -d' ' -f1)
        echo "$uid|$due|$desc|$priority|$done"
    done
}

# =========== INICIALIZACIÓN ===========
validate_paths
if [ "$DEBUG" = "true" ]; then
    log_msg "INFO" "TDO-Hub configurado"
fi
true
