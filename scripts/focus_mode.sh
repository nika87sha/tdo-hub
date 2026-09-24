#!/usr/bin/env bash

HUB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$HUB_ROOT/core.sh"

HOSTS_FILE="/etc/hosts"
BLOCK_FILE="$HUB_ROOT/bloqueo_distraccion.txt"
BACKUP_FILE="$HUB_ROOT/hosts.bak"
PHRASES_FILE="$HUB_ROOT/phrases.txt"

# Validaciones
check_requirements() {
    [[ ! -f "$BLOCK_FILE" ]] && { echo "❌ Archivo de bloqueo no encontrado: $BLOCK_FILE"; exit 1; }
    [[ ! -f "$HOSTS_FILE" ]] && { echo "❌ /etc/hosts no encontrado"; exit 1; }
    command -v tmux &>/dev/null || { echo "❌ tmux no instalado"; exit 1; }
    [[ ! -d "$NOTES_DIR" ]] && mkdir -p "$NOTES_DIR"
    [[ ! -f "$TODO_ACTIVO" ]] && mkdir -p "$(dirname "$TODO_ACTIVO")" && echo "# Tareas" > "$TODO_ACTIVO"
    # sudoers se verifica solo cuando se va a modificar /etc/hosts (en activar_focus/desactivar_focus)
}

activar_focus() {
    # 0. Visual Hyprland (solo si hay Hyprland)
    focus_visual_on

    # 1. Música (antes de bloquear red, para que rofi funcione)
    local MUSIC_CHOICE=$(echo -e "🔀 Shuffle todo\n🎵 Miss Monique\n🎵 Electronica\n📂 Elegir carpeta...\n🔇 Sin música" | rofi_menu "🎵 ¿Música?")
    case "$MUSIC_CHOICE" in
        *"Shuffle todo")    bash "$SCRIPTS_DIR/focus_music.sh" play "/" "Todo" ;;
        *"Miss Monique")    bash "$SCRIPTS_DIR/focus_music.sh" play "Electronica/Miss Monique" "Miss Monique" ;;
        *"Electronica")     bash "$SCRIPTS_DIR/focus_music.sh" play "Electronica" "Electronica" ;;
        *"Elegir carpeta")  bash "$SCRIPTS_DIR/focus_music.sh" & ;;
        *"Sin música"*)     ;;
        *)                  ;;  # Canceló rofi
    esac

    # 2. Bloqueo de red (usa privileged ops con sudoers específico)
    backup_hosts_file "$BACKUP_FILE" || exit 1
    append_to_hosts "$(cat "$BLOCK_FILE"; echo -e "\n### FOCUS MODE ACTIVADO ###")" || exit 1
    restart_networkmanager || exit 1
    flush_dns_cache 

    # 3. Info de la Tarea
    local TAREA_LIMPIA=$(grep "🎯" "$TODO_ACTIVO" | sed 's/.*🎯 //; s/.*\[ \] //')
    [ -z "$TAREA_LIMPIA" ] && TAREA_LIMPIA="Foco"
    local FRASE=$(shuf -n 1 "$PHRASES_FILE" 2>/dev/null || echo "Dale.")

    # 4. TMUX - Ventana "Focus" por nombre (no por índice: el 5 puede ser otra cosa)
    tmux has-session -t "$SESSION" 2>/dev/null || tmux new-session -d -s "$SESSION"

    # Matar la ventana Focus si existe para recrearla limpia
    tmux kill-window -t "$SESSION:Focus" 2>/dev/null
    tmux new-window -t "$SESSION" -n "Focus"

    # 5. Crear la estructura PRIMERO
    # Dividimos la ventana Focus: Panel 0 (izq) y Panel 1 (der)
    tmux split-window -h -p 35 -t "$SESSION:Focus.0"

    # Esperamos un instante para que tmux asiente los paneles
    sleep 0.2

    # Crear panel inferior para pomodoro
    tmux split-window -v -p 20 -t "$SESSION:Focus.0"
    sleep 0.2

    # 6. Inyectar comandos en los paneles vacíos
    # Panel Izquierdo inferior (Pomodoro status)
    local pomo_emoji=$("${STREAK_SCRIPT:-$SCRIPTS_DIR/streak-tracker.sh}" 2>/dev/null || echo "🍅")
    local pomo_status="echo -e '\n🎯 FOCUS MODE\n$pomo_emoji Esperando inicio de pomodoro...'"
    tmux send-keys -t "$SESSION:Focus.2" C-u "$pomo_status" C-m

    # Panel Derecho (Banner)
    tmux send-keys -t "$SESSION:Focus.1" C-u "clear && echo -e '\n\e[1;33m--- FOCUS ---\e[0m\n\n\e[1;32m🎯 TAREA:\e[0m\n$TAREA_LIMPIA\n\n\e[1;34m💡 FRASE:\e[0m\n$FRASE'" C-m

    # Panel Izquierdo (nvim)
    tmux send-keys -t "$SESSION:Focus.0" C-u "nvim '$TODO_ACTIVO'" C-m

    # Asegurar foco en nvim
    tmux select-pane -t "$SESSION:Focus.0"
    
    # 7. Auto-iniciar pomodoro si no está activo
    if ! pgrep -f "pomodoro-daemon.sh" > /dev/null 2>&1; then
        bash "$SCRIPTS_DIR/pomodoro-daemon.sh" run &
    fi
    notify "🔒 MODO FOCO" "$TAREA_LIMPIA"
}

# Visual Hyprland: lo que antes hacía ~/.config/hypr/UserScripts/FocusMode.sh
focus_visual_on() {
    command -v hyprctl &>/dev/null || return 0
    hyprctl eval 'hl.config({
        decoration = { shadow = { enabled = false }, blur = { passes = 0 }, rounding = 0, active_opacity = 0.95, inactive_opacity = 0.3 },
        general = { gaps_in = 0, gaps_out = 0 },
        misc = { disable_autoreload = true }
    })' 2>/dev/null
    killall waybar 2>/dev/null
    swaync-client --mute 2>/dev/null
    notify-send -e -u critical "🧘 Focus Mode ON" "Distracciones silenciadas + red bloqueada" 2>/dev/null
}

focus_visual_off() {
    command -v hyprctl &>/dev/null || return 0
    hyprctl eval 'hl.config({
        decoration = { shadow = { enabled = true }, blur = { passes = 2 }, rounding = 10, active_opacity = 1.0, inactive_opacity = 0.9 },
        general = { gaps_in = 5, gaps_out = 10 },
        misc = { disable_autoreload = false }
    })' 2>/dev/null
    waybar & disown 2>/dev/null
    swaync-client --unmute 2>/dev/null
    pkill -f pomodoro-waybar 2>/dev/null
    notify-send -e -u low "🔇 Focus Mode OFF" 2>/dev/null
}

desactivar_focus() {
    if [ -f "$BACKUP_FILE" ]; then
        focus_visual_off
        # Parar música
        bash "$SCRIPTS_DIR/focus_music.sh" stop 2>/dev/null

        restore_hosts_file "$BACKUP_FILE" || exit 1
        restart_networkmanager || exit 1
        rm "$BACKUP_FILE"
        atomic_sed_replace "$TODO_ACTIVO" "s/🎯 //g"
        notify "✅ FOCUS MODE DESACTIVADO"
        
        # Hook: log proyecto en timew si hay tarea activa
        _focus_log_project
    fi
}

# Hook: preguntar proyecto y loguear en timew
_focus_log_project() {
    command -v timew &>/dev/null || return 0
    
    # Obtener tarea marcada con 🎯 (la que se estaba haciendo)
    local tarea=$(grep "🎯" "$TODO_ACTIVO" | head -1 | sed 's/.*🎯 //; s/ due:.*//; s/ @.*//; s/ repeat:.*//')
    [[ -z "$tarea" ]] && return 0
    
    # Preguntar proyecto (rofi o stdin si no hay display)
    local proyecto=""
    if [[ -n "$DISPLAY" || -n "$WAYLAND_DISPLAY" ]]; then
        proyecto=$(echo -e "JIRA\nGITHUB\nGITLAB\nSLACK\nTEAMS\nOUTLOOK\nCONFLUENCE\nDOCS\nTERMINAL\nDOCKER\nAWS\nAZURE\nMEET\nBROWSER\nOTROS\n❌ Saltar" | rofi_menu "📋 Proyecto para: $tarea")
    else
        read -rp "Proyecto para '$tarea' (Enter=skip): " proyecto < /dev/tty
    fi
    
    [[ -z "$proyecto" || "$proyecto" == *"Saltar"* ]] && return 0
    
    # Log en timew con tag #proyecto
    timew stop 2>/dev/null
    timew start "#${proyecto}" "$tarea" 2>/dev/null
    log_info "FOCUS_HOOK" "Logueado en timew: #${proyecto} - ${tarea}"
}

# stop/start explícitos (el hub y panic_button usan "stop").
# Sin args: toggle según el marcador en /etc/hosts.
case "${1:-toggle}" in
    stop)
        check_requirements
        desactivar_focus
        ;;
    start)
        check_requirements
        if grep -q "### FOCUS MODE ACTIVADO ###" "$HOSTS_FILE"; then
            echo "Focus ya está activo"
        else
            activar_focus
        fi
        ;;
    *)
        if grep -q "### FOCUS MODE ACTIVADO ###" "$HOSTS_FILE"; then
            check_requirements
            desactivar_focus
        else
            check_requirements
            activar_focus
        fi
        ;;
esac
