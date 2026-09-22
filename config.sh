#!/usr/bin/env bash
# ==========================================================
# ⚙️ CONFIGURACIÓN CENTRAL DE TDO-HUB
# ==========================================================

# --- Cargar .env si existe ---
# Compatible bash/zsh: BASH_SOURCE no existe en zsh
if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
    ENV_FILE="${HUB_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}/.env"
elif [[ -n "${(%):-%N}" ]]; then
    ENV_FILE="${HUB_ROOT:-$(cd "$(dirname "${(%):-%N}")" && pwd)}/.env"
else
    ENV_FILE="${HUB_ROOT:-$(pwd)}/.env"
fi
if [[ -f "$ENV_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
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
export BLOCK_FILE="${BLOCK_FILE:-$HUB_ROOT/bloqueo_distraccion.txt}"
export LOG_DIR="${LOG_DIR:-$HOME/.config/focus}"
export LOG_FILE="${LOG_FILE:-$LOG_DIR/$(date +%Y-%m-%d).log}"

# =========== NOTAS ===========
# Genéricos a propósito: TU layout vive en .env (ver .env.example).
# Aquí solo defaults planos para que funcione sin .env.
export NOTES_DIR="${NOTES_DIR:-$HOME/notes}"
export PROJECTS_DIR="${PROJECTS_DIR:-$NOTES_DIR/01_projects}"
export TODOS_DIR="${TODOS_DIR:-$NOTES_DIR/01_projects/General/todos}"
export TODO_ACTIVO="${TODO_ACTIVO:-$TODOS_DIR/todo_ACTIVO.md}"
export JOURNAL_DIR="${JOURNAL_DIR:-$NOTES_DIR/02_areas/personal/journal}"
export TEMPLATES_DIR="${TEMPLATES_DIR:-$NOTES_DIR/templates}"
export INBOX_DIR="${INBOX_DIR:-$NOTES_DIR/00_inbox}"
export WORKLOG_DIR="${WORKLOG_DIR:-$NOTES_DIR/worklog}"
export ARCHIVE_DIR="${ARCHIVE_DIR:-$NOTES_DIR/04_archivo}"

# =========== SCRIPTS ===========
export FOCUS_SCRIPT="${FOCUS_SCRIPT:-$SCRIPTS_DIR/focus_mode.sh}"
export PANIC_SCRIPT="${PANIC_SCRIPT:-$SCRIPTS_DIR/panic_button.sh}"
export TRIAGE_SCRIPT="${TRIAGE_SCRIPT:-$SCRIPTS_DIR/triage-local.sh}"
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
export AW_BUCKET_SHELL="${AW_BUCKET_SHELL:-aw-shell-zsh_$(hostname)}"
export AW_DEFAULT_SERVER="${AW_DEFAULT_SERVER:-}"
export AW_FALLBACK_SERVER="${AW_FALLBACK_SERVER:-http://localhost:5600}"

# Nombres de buckets adicionales para otros scripts
export AW_BUCKET_OTRO="${AW_BUCKET_OTRO:-aw-watcher-window_$(hostname)}"

# =========== APLICACIONES ===========
export EDITOR="${EDITOR:-nvim}"

# =========== ROFI TEMA ===========
export ROFI_THEME="${ROFI_THEME:-$HUB_ROOT/themes/hub.rasi}"
export ROFI_THEME_FALLBACK="${ROFI_THEME_FALLBACK:-~/.config/rofi/config.rasi}"

# =========== VALIDACIÓN DE CONFIGURACIÓN ===========
# Verificar que la configuración es coherente al cargar
_config_validate() {
    local errors=0
    
    # 1. HUB_ROOT debe existir
    [[ -d "$HUB_ROOT" ]] || {
        echo "[CONFIG] ERROR: HUB_ROOT no existe: $HUB_ROOT" >&2
        ((errors++))
    }
    
    # 2. Directorios base deben ser writable
    for var in NOTES_DIR INBOX_DIR TEMPLATES_DIR JOURNAL_DIR TODOS_DIR; do
        local dir="${!var}"
        [[ -w "$(dirname "$dir")" ]] || {
            echo "[CONFIG] WARN: $var parent no escribible: $(dirname "$dir")" >&2
        }
    done
    
    # 3. Archivos críticos
    [[ -f "$PHRASES_FILE" ]] || echo "[CONFIG] WARN: PHRASES_FILE no existe: $PHRASES_FILE" >&2
    [[ -f "$DISTRACTION_FILE" ]] || echo "[CONFIG] WARN: DISTRACTION_FILE no existe: $DISTRACTION_FILE" >&2
    [[ -f "$TODO_ACTIVO" ]] || echo "[CONFIG] INFO: TODO_ACTIVO se creará: $TODO_ACTIVO" >&2
    
    # 4. ROFI theme
    [[ -f "$ROFI_THEME" ]] || [[ -f "$ROFI_THEME_FALLBACK" ]] || echo "[CONFIG] WARN: Ningún tema rofi encontrado" >&2
    
    return $errors
}

# =========== FUNCIONES ===========
# Funciones de logging movidas a logger.sh (core.sh lo carga)
# require_command() movido a core.sh
# validate_paths() integrado en validate_runtime() de core.sh

# parse_tasks() se mantiene aquí por compatibilidad
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
# Crear directorios base
mkdir -p "$PROJECTS_DIR" "$TODOS_DIR" "$INBOX_DIR" "$WORKLOG_DIR" "$ARCHIVE_DIR" "$JOURNAL_DIR" "$LOG_DIR" "$TEMPLATES_DIR" 2>/dev/null

# Validar configuración
_config_validate

# Debug
if [[ "$DEBUG" == "true" ]]; then
    echo "[CONFIG] TDO-Hub configurado" >&2
fi

true