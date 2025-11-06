#!/usr/bin/env bash
HUB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-${0}}")" && pwd)"
source "$HUB_ROOT/config.sh"

set -o pipefail

# =========== NOTIFICACIONES ===========
notify() {
    local msg="${2:-$1}"
    command -v notify-send &>/dev/null && notify-send "TDO Hub" "$msg" --icon=task-accepted
    echo "[$(date +%H:%M:%S)] $msg" >> "$HUB_ROOT/.tdo.log"
}

# Error a log SIN ensuciar stdout: los scripts redirigen aquí su
# stderr en vez de a 2>/dev/null (que escondía bugs reales).
log_err() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $*" >> "${HUB_ROOT:-$HOME/.local/bin/tdo-hub}/.tdo.log"
}

log_msg() {
    local level="${1:-INFO}" msg="${2:-}"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $msg" >> "$HUB_ROOT/.tdo.log"
}

log_ok() {
    local label="$1" msg="${2:-$1}"
    echo -e "${GREEN}✓ [$label] $msg${RESET}"
    log_msg "OK" "[$label] $msg"
}

log_error() {
    local label="$1" msg="${2:-$1}"
    echo -e "${RED}✗ [$label] $msg${RESET}" >&2
    log_msg "ERROR" "[$label] $msg"
}

log_warn() {
    local label="$1" msg="${2:-$1}"
    echo -e "${YELLOW}⚠ [$label] $msg${RESET}"
    log_msg "WARN" "[$label] $msg"
}

log_info() {
    local label="$1" msg="${2:-$1}"
    log_msg "INFO" "[$label] $msg"
}

require_command() {
    local cmd="$1" name="${2:-$1}"
    if ! command -v "$cmd" &>/dev/null; then
        log_error "$name" "Comando no encontrado: $cmd"
        return 1
    fi
}

error_exit() {
    echo "❌ Error: $1" >&2
    notify "Error: $1"
    return 1
}

# =========== TMUX ===========
# Si un script de solo-salida (stats, yesterday, sync) se lanza sin
# terminal (bind de Hyprland, rofi, cron), se re-ejecuta a sí mismo
# en una ventana tmux y enfoca el terminal. Dentro de tmux o con
# tty no hace nada.
# ¿Lo lanzó Hyprland/rofi (sin terminal) en vez de un shell manual?
_started_by_gui() {
    local p=$PPID
    for _ in 1 2 3 4 5; do
        [[ -z "$p" || "$p" == "1" ]] && break
        local c=$(ps -o comm= -p "$p" 2>/dev/null)
        case "$c" in Hyprland|hyprland|rofi) return 0 ;; esac
        p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
    done
    return 1
}

ensure_tmux_window() {
    local win="$1"; shift
    [[ -n "${TMUX:-}" ]] && return 0
    [[ -t 1 ]] && return 0
    _started_by_gui || return 0
    local script="$1"; shift || true
    [[ -z "$script" ]] && return 0
    tmux has-session -t "$SESSION" 2>/dev/null || tmux new-session -d -s "$SESSION"
    if ! tmux list-windows -t "$SESSION" -F '#{window_name}' 2>/dev/null | grep -q "^${win}$"; then
        tmux new-window -t "$SESSION" -n "$win"
        sleep 0.5
    fi
    tmux send-keys -t "$SESSION:$win" C-u "clear && bash '$script' $* && echo '--- [Enter para cerrar] ---' && read _" C-m
    tmux select-window -t "$SESSION:$win" 2>/dev/null
    hyprctl dispatch focuswindow "class:Alacritty" 2>/dev/null
    exit 0
}

run_in_tmux() {
    local CMD="$1"
    local WIN="${2:-$(tmux display-message -t "$SESSION" -p '#{window_name}' 2>/dev/null || echo 'zsh')}"
    tmux has-session -t "$SESSION" 2>/dev/null || tmux new-session -d -s "$SESSION"
    if tmux list-windows -t "$SESSION" -F '#{window_name}' 2>/dev/null | grep -q "^${WIN}$"; then
        tmux send-keys -t "$SESSION:$WIN" C-u "clear && $CMD" C-m
        tmux select-window -t "$SESSION:$WIN" 2>/dev/null
    else
        tmux new-window -t "$SESSION" -n "$WIN"
        sleep 0.3
        tmux send-keys -t "$SESSION:$WIN" "$CMD" Enter
        tmux select-window -t "$SESSION:$WIN" 2>/dev/null
    fi
    hyprctl dispatch focuswindow "class:Alacritty" 2>/dev/null
}

# =========== ACTIVITYWATCH ===========
# Resuelve la URL base de ActivityWatch (sin /api/0) probando hasta la primera que responda:
# Acepta tanto los nombres de config.sh (.env) como los legacy:
#   AW_SERVER_URL → AW_DEFAULT_SERVER → AW_FALLBACK_URL → AW_FALLBACK_SERVER → localhost
resolve_aw_api() {
    local candidates=(
        "${AW_SERVER_URL:-}"
        "${AW_DEFAULT_SERVER:-}"
        "${AW_FALLBACK_URL:-}"
        "${AW_FALLBACK_SERVER:-http://localhost:5600}"
        "http://localhost:5600"
    )
    local url
    for url in "${candidates[@]}"; do
        [ -n "$url" ] || continue
        if curl -sL --connect-timeout 2 -o /dev/null "$url/api/0/buckets" 2>/dev/null; then
            echo "$url"
            return 0
        fi
    done
    return 1
}

# =========== TEMPLATES ===========
apply_template() {
    local template="$1" target="$2" title="$3"
    local today
    today=$(date +'%Y-%m-%d')
    mkdir -p "$(dirname "$target")"
    if [[ -f "$template" ]]; then
        cp "$template" "$target"
    else
        echo "# $title" > "$target"
    fi
    sed -i -e "s|{{date}}|$today|g" \
           -e "s|{{title}}|$title|g" \
           -e "s|{ { AAAA-MM-DD } }|$today|g" \
           -e "s|{{AAAA-MM-DD}}|$today|g" \
           "$target"
}

# =========== NOTAS ===========
open_note() {
    local file="$1"
    [[ ! -f "$file" ]] && return
    run_in_tmux "nvim '$file'"
}

new_journal_entry() {
    local ARCHIVO="$JOURNAL_DIR/$(date +%Y)/$(date +%m)/$(date +%Y-%m-%d).md"
    [[ ! -f "$ARCHIVO" ]] && apply_template "$TEMPLATES_DIR/entry.md" "$ARCHIVO" "Diario $(date +%F)"
    open_note "$ARCHIVO"
}

extract_title_from_note() {
    local note="$1"
    [[ ! -f "$note" ]] && return
    local title=$(head -20 "$note" | rg -oP '^#\s+\K.+' | head -1)
    [[ -z "$title" ]] && title=$(basename "$note" .md | tr '_' ' ')
    echo "$title"
}

get_note_metadata() {
    local note="$1"
    [[ ! -f "$note" ]] && return
    local date=$(rg -oP '^date:\s*\K.+' "$note" | head -1)
    local tags=$(rg -oP '^tags:\s*\K\[[^\]]+\]' "$note" | head -1)
    echo "date:$date|tags:$tags"
}

# =========== TAREAS ===========
parse_task_date() {
    echo "$1" | grep -oE 'due:[0-9]{4}-[0-9]{2}-[0-9]{2}' | cut -d: -f2
}

is_task_overdue() {
    local due_date=$(parse_task_date "$1")
    [[ -z "$due_date" ]] && return 2
    [[ "$due_date" < "$(date +%Y-%m-%d)" ]] && return 0
    return 1
}

get_task_priority() {
    if echo "$1" | grep -qE '^!!'; then echo "high"
    elif echo "$1" | grep -qE '^!'; then echo "medium"
    else echo "normal"
    fi
}

get_task_categories() {
    echo "$1" | grep -oE '@[a-zA-Z0-9_-]+' | tr -d '@' | sort -u
}

sort_by_priority() {
    echo "$1" | awk '/^!!/{p=1} /^!/{p=2} /^[^!]/{p=3} {print p"|"$0}' | sort -t'|' -n -k1 | cut -d'|' -f2-
}

filter_tasks_by_date() {
    local filter="$1" tasks="$2"
    local today=$(date +%Y-%m-%d) today_sec=$(date +%s) week_end_sec=$((today_sec + 604800))
    while IFS= read -r task; do
        [[ -z "$task" ]] && continue
        local due_date=$(parse_task_date "$task")
        local due_sec=$(date -d "$due_date" +%s 2>/dev/null)
        case "$filter" in
            "overdue")  [[ -n "$due_date" && -n "$due_sec" && "$due_sec" -lt "$today_sec" ]] && echo "$task" ;;
            "today")    [[ "$due_date" == "$today" ]] && echo "$task" ;;
            "week")     [[ -n "$due_date" && -n "$due_sec" && "$due_sec" -ge "$today_sec" && "$due_sec" -le "$week_end_sec" ]] && echo "$task" ;;
            "no-date")  [[ -z "$due_date" ]] && echo "$task" ;;
        esac
    done <<< "$tasks"
}

parse_recurrence() {
    echo "$1" | grep -oE 'repeat:(daily|weekly|monthly)' | cut -d: -f2
}

expand_recurring_task() {
    local recurrence=$(parse_recurrence "$1")
    [[ -z "$recurrence" ]] && return 1
    local new_due=""
    case "$recurrence" in
        "daily")   new_due=$(date -d "+1 day" +%Y-%m-%d) ;;
        "weekly")  new_due=$(date -d "+1 week" +%Y-%m-%d) ;;
        "monthly") new_due=$(date -d "+1 month" +%Y-%m-%d) ;;
    esac
    echo "$1" | sed "s/due:[0-9-]*/due:$new_due/"
}

complete_task_with_recurrence() {
    local task="$1"
    local task_base=$(get_task_base "$task")
    local recurrence=$(parse_recurrence "$task")
    timew stop 2>/dev/null
    echo "- [x] $(date +%Y-%m-%d) $task" >> "$TODO_TRASH"
    local task_esc=$(printf '%s\n' "$task_base" | sed 's/[.[\*^$()\/]/\\&/g')
    sed -i "s/- \[ \] $task_esc/- [x] $task_esc/" "$TODO_ACTIVO"
    notify "¡Hecho!"
    if [[ -n "$recurrence" ]]; then
        local new_task=$(expand_recurring_task "$task")
        echo "- [ ] $new_task" >> "$TODO_ACTIVO"
        notify "Tarea recurrente" "Nueva: $new_task"
    fi
}

# Extrae la descripción base de la tarea (sin due: ni @tags ni repeat:) para matching
get_task_base() {
    local task="$1"
    # Quita due:... repeat:... y @tags finales
    echo "$task" | sed -E 's/[[:space:]]*due:[^[:space:]]*//g' | sed -E 's/[[:space:]]*repeat:[^[:space:]]*//g' | sed -E 's/[[:space:]]*@[^[:space:]]*//g' | sed 's/[[:space:]]*$//'
}

get_all_tasks() {
    [[ ! -f "$TODO_ACTIVO" ]] && return
    # Captura tareas multilínea: la línea principal + líneas de continuación (due:/@tags)
    awk '
        /^[[:space:]]*-[[:space:]]*\[[ x]\]/ {
            if (task != "") print task
            task = $0
            next
        }
        /^[[:space:]]/ && task != "" {
            task = task " " $0
            next
        }
        { if (task != "") { print task; task = "" } }
        END { if (task != "") print task }
    ' "$TODO_ACTIVO" | sed 's/^[[:space:]]*-[[:space:]]*\[[ x]\] //'
}

# =========== MÚSICA (MPD) ===========
# Control via cliente mpc

MPD_HOST="${MPD_HOST:-127.0.0.1}"
MPD_PORT="${MPC_PORT:-6601}"

stop_music() {
    mpc --host "$MPD_HOST" --port "$MPD_PORT" stop > /dev/null
    mpc --host "$MPD_HOST" --port "$MPD_PORT" clear > /dev/null
    notify "🎵" "Música parada"
}

shuffle_dir() {
    local dir="${1:-/}" label="${2:-$(basename "$dir")}"
    mpc --host "$MPD_HOST" --port "$MPD_PORT" clear > /dev/null
    mpc --host "$MPD_HOST" --port "$MPD_PORT" add "$dir" > /dev/null
    mpc --host "$MPD_HOST" --port "$MPD_PORT" shuffle > /dev/null
    mpc --host "$MPD_HOST" --port "$MPD_PORT" play > /dev/null
    notify "🎵" "Sonando: $label"
}

load_playlist() {
    local pl="$1"
    mpc --host "$MPD_HOST" --port "$MPD_PORT" clear > /dev/null
    mpc --host "$MPD_HOST" --port "$MPD_PORT" load "$pl" > /dev/null
    mpc --host "$MPD_HOST" --port "$MPD_PORT" play > /dev/null
    notify "🎵" "Playlist: $pl"
}
