#!/usr/bin/env bash
HUB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-${0}}")" && pwd)"
source "$HUB_ROOT/config.sh"

set -o pipefail

# =========== SANITIZE ===========
source "$HUB_ROOT/scripts/sanitize.sh"

# =========== ATOMIC FILE OPS ===========
# Reemplazo atómico usando archivo temporal + mv (evita corrupción)
atomic_sed_replace() {
    local file="$1"
    local sed_expr="$2"
    local tmp="${file}.tmp.$$"
    
    sed "$sed_expr" "$file" > "$tmp" && mv "$tmp" "$file"
}

# Lectura atómica con lock (evita race conditions)
atomic_read_tasks() {
    local file="$1"
    local tmp="${file}.read.$$"
    (
        flock -x 200
        cat "$file" > "$tmp"
        cat "$tmp"
    ) 200>"$file.lock"
    rm -f "$tmp" "$file.lock"
}

# Escritura atómica con lock
atomic_write_tasks() {
    local file="$1"
    local content="$2"
    local tmp="${file}.tmp.$$"
    printf '%s\n' "$content" > "$tmp" && mv "$tmp" "$file"
}

# =========== PRIVILEGED OPS ===========
# Operaciones que requieren sudo - usando reglas sudoers específicas
# Estas funciones fallan explícitamente si sudoers no está configurado

# Backup /etc/hosts
backup_hosts_file() {
    local backup_file="$1"
    sudo /usr/bin/cp /etc/hosts "$backup_file" 2>/dev/null || {
        log_err "PRIVOPS" "Failed to backup /etc/hosts (sudoers missing?)"
        return 1
    }
}

# Restaurar /etc/hosts desde backup
restore_hosts_file() {
    local backup_file="$1"
    sudo /usr/bin/cp "$backup_file" /etc/hosts 2>/dev/null || {
        log_err "PRIVOPS" "Failed to restore /etc/hosts (sudoers missing?)"
        return 1
    }
}

# Añadir líneas a /etc/hosts (para bloqueo)
append_to_hosts() {
    local content="$1"
    printf '%s\n' "$content" | sudo /usr/bin/tee -a /etc/hosts >/dev/null 2>&1 || {
        log_err "PRIVOPS" "Failed to append to /etc/hosts (sudoers missing?)"
        return 1
    }
}

# Reiniciar NetworkManager
restart_networkmanager() {
    sudo /usr/bin/systemctl restart NetworkManager 2>/dev/null || {
        log_err "PRIVOPS" "Failed to restart NetworkManager (sudoers missing?)"
        return 1
    }
}

# Limpiar cache DNS
flush_dns_cache() {
    sudo /usr/bin/resolvectl flush-caches 2>/dev/null || {
        log_warn "PRIVOPS" "Failed to flush DNS cache (non-critical)"
        return 1
    }
}

# Verificar que sudoers está configurado
check_sudoers_setup() {
    sudo -n /usr/bin/cp /etc/hosts /dev/null 2>/dev/null && \
    sudo -n /usr/bin/systemctl restart NetworkManager 2>/dev/null
}

# =========== LOGGER ===========
source "$HUB_ROOT/scripts/logger.sh"

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

# =========== RUNTIME VALIDATION ===========
# Validación al inicio de cada script - llama automáticamente al sourcear core.sh
# Verifica: dependencias, paths, permisos, configuración
validate_runtime() {
    local script_name="${1:-${BASH_SOURCE[1]##*/}}"
    local errors=0
    
    # 1. Comandos críticos
    for cmd in bash tmux nvim; do
        command -v "$cmd" &>/dev/null || {
            log_error "VALIDATE" "[$script_name] Comando crítico faltante: $cmd"
            ((errors++))
        }
    done
    
    # 2. Comandos recomendados (warning only)
    for cmd in rofi fzf rg notify-send mpc timew; do
        command -v "$cmd" &>/dev/null || {
            log_warn "VALIDATE" "[$script_name] Comando recomendado faltante: $cmd"
        }
    done
    
    # 3. Directorios requeridos
    for dir in "$NOTES_DIR" "$INBOX_DIR" "$TEMPLATES_DIR" "$JOURNAL_DIR" "$TODOS_DIR"; do
        [[ -d "$dir" ]] || {
            log_warn "VALIDATE" "[$script_name] Directorio no existe (se creará): $dir"
            mkdir -p "$dir" 2>/dev/null || {
                log_error "VALIDATE" "[$script_name] No se puede crear: $dir"
                ((errors++))
            }
        }
    done
    
    # 4. Archivos requeridos
    [[ -f "$TODO_ACTIVO" ]] || {
        mkdir -p "$(dirname "$TODO_ACTIVO")"
        echo "# Tareas" > "$TODO_ACTIVO"
        log_info "VALIDATE" "[$script_name] Creado $TODO_ACTIVO"
    }
    
    [[ -f "$BLOCK_FILE" ]] || {
        log_warn "VALIDATE" "[$script_name] Archivo de bloqueo no encontrado: $BLOCK_FILE"
    }
    
    # 5. Permisos de escritura
    for file in "$TODO_ACTIVO" "$TODO_TRASH" "$SESSION_LOG"; do
        [[ -w "$(dirname "$file")" ]] || {
            log_error "VALIDATE" "[$script_name] Sin escritura en: $(dirname "$file")"
            ((errors++))
        }
    done
    
    # 6. Verificar /etc/hosts para focus mode
    [[ -w "/etc/hosts" ]] || check_sudoers_setup &>/dev/null || {
        log_warn "VALIDATE" "[$script_name] Focus mode requiere sudoers configurado"
    }
    
    return $errors
}

# Auto-validar al sourcear (solo si no está en modo test y es el script principal)
# Solo validar si BASH_SOURCE[1] es el script que se está ejecutando (no sourced)
[[ "${TD_VALIDATE:-auto}" != "never" ]] && [[ "${BASH_SOURCE[0]}" == "${BASH_SOURCE[1]}" ]] && validate_runtime "${BASH_SOURCE[1]##*/}" 2>/dev/null

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

# =========== ROFI HELPER ===========
source "$HUB_ROOT/scripts/rofi.sh"

# =========== TMUX MANAGER ===========
# Gestor centralizado de ventanas/paneles tmux
# Elimina duplicación en 7 scripts

# Estado interno
_TMUX_TERMINAL_CLASS="${TMUX_TERMINAL_CLASS:-Alacritty}"

# Inicializar sesión tmux (idempotente)
tmux_init_session() {
    tmux has-session -t "$SESSION" 2>/dev/null || tmux new-session -d -s "$SESSION" 2>/dev/null
}

# Obtener o crear ventana con nombre
# Uso: tmux_get_window "nombre" "comando_inicial"
tmux_get_window() {
    local name="$1"
    local init_cmd="${2:-}"
    
    tmux_init_session
    
    if tmux list-windows -t "$SESSION" -F '#{window_name}' 2>/dev/null | grep -q "^${name}$"; then
        # Ventana existe - verificar si hay nvim/vim corriendo
        local proc=$(tmux list-panes -t "$SESSION:$name" -F '#{pane_current_command}' 2>/dev/null | head -1)
        if [[ "$proc" == "nvim" || "$proc" == "vim" ]]; then
            tmux select-window -t "$SESSION:$name" 2>/dev/null
            tmux_focus_terminal
            return 0
        fi
        # No hay editor - enviar comando si se proporciona
        [[ -n "$init_cmd" ]] && tmux send-keys -t "$SESSION:$name" C-u "$init_cmd" C-m
        tmux select-window -t "$SESSION:$name" 2>/dev/null
        tmux_focus_terminal
        return 0
    fi
    
    # Crear nueva ventana
    tmux new-window -t "$SESSION" -n "$name" 2>/dev/null
    sleep 0.3
    [[ -n "$init_cmd" ]] && tmux send-keys -t "$SESSION:$name" "$init_cmd" C-m
    tmux select-window -t "$SESSION:$name" 2>/dev/null
    tmux_focus_terminal
}

# Crear/reusar ventana para script de salida (stats, sync, etc)
# Uso: tmux_run_script "nombre_ventana" "script_path" [args...]
tmux_run_script() {
    local name="$1"
    local script="$2"
    shift 2
    
    tmux_init_session
    
    if tmux list-windows -t "$SESSION" -F '#{window_name}' 2>/dev/null | grep -q "^${name}$"; then
        local proc=$(tmux list-panes -t "$SESSION:$name" -F '#{pane_current_command}' 2>/dev/null | head -1)
        if [[ "$proc" == "nvim" || "$proc" == "vim" ]]; then
            tmux select-window -t "$SESSION:$name" 2>/dev/null
            tmux_focus_terminal
            return 0
        fi
    else
        tmux new-window -t "$SESSION" -n "$name" 2>/dev/null
        sleep 0.3
    fi
    
    local cmd="clear && bash '$script' $* && echo '--- [Enter para cerrar] ---' && read _"
    tmux send-keys -t "$SESSION:$name" C-u "$cmd" C-m
    tmux select-window -t "$SESSION:$name" 2>/dev/null
    tmux_focus_terminal
}

# Enfocar terminal (Hyprland)
tmux_focus_terminal() {
    command -v hyprctl &>/dev/null && [[ -n "$HYPRLAND_INSTANCE_SIGNATURE" ]] && \
        hyprctl dispatch focuswindow "class:${_TMUX_TERMINAL_CLASS}" 2>/dev/null
}

# Enviar comando a ventana existente
# Uso: tmux_send "nombre_ventana" "comando"
tmux_send() {
    local name="$1"
    local cmd="$2"
    tmux_init_session
    
    if tmux list-windows -t "$SESSION" -F '#{window_name}' 2>/dev/null | grep -q "^${name}$"; then
        tmux send-keys -t "$SESSION:$name" C-u "$cmd" C-m
        tmux select-window -t "$SESSION:$name" 2>/dev/null
        tmux_focus_terminal
        return 0
    fi
    return 1
}

# Matar ventana por nombre
tmux_kill_window() {
    local name="$1"
    tmux kill-window -t "$SESSION:$name" 2>/dev/null
}

# Dividir ventana (horizontal/vertical)
# Uso: tmux_split "nombre_ventana" "h|v" [porcentaje]
tmux_split() {
    local name="$1"
    local direction="$2"
    local percent="${3:-50}"
    local target_pane="${4:-0}"
    
    tmux_init_session
    if [[ "$direction" == "h" ]]; then
        tmux split-window -h -p "$percent" -t "$SESSION:$name.$target_pane" 2>/dev/null
    else
        tmux split-window -v -p "$percent" -t "$SESSION:$name.$target_pane" 2>/dev/null
    fi
    sleep 0.2
}

# Seleccionar panel específico
tmux_select_pane() {
    local name="$1"
    local pane="$2"
    tmux select-pane -t "$SESSION:$name.$pane" 2>/dev/null
}

# Enviar comando a panel específico
tmux_send_pane() {
    local name="$1"
    local pane="$2"
    local cmd="$3"
    tmux send-keys -t "$SESSION:$name.$pane" C-u "$cmd" C-m
}

# Compatibilidad: ensure_tmux_window (deprecated, use tmux_get_window)
ensure_tmux_window() {
    local win="$1"; shift
    tmux_run_script "$win" "$@"
}

# Compatibilidad: run_in_tmux (deprecated, use tmux_get_window/tmux_send)
run_in_tmux() {
    local cmd="$1"
    local win="${2:-zsh}"
    tmux_get_window "$win" "$cmd"
}

# =========== ACTIVITYWATCH ===========

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
    local task_esc=$(sanitize_for_sed "$task_base")
    atomic_sed_replace "$TODO_ACTIVO" "s/- \[ \] $task_esc/- [x] $task_esc/"
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
