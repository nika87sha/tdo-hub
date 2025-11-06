#!/usr/bin/env bash
# ==========================================================
# 📝 QUICK CAPTURE - Captura interactiva de tareas
# Rofi + fechas visuales = 0 fricción TDAH
# ==========================================================

source "$(dirname "$0")/../core.sh"

# Colores
R='\033[0;31m'
G='\033[0;32m'
Y='\033[0;33m'
C='\033[0;36m'
N='\033[0m'

# Capturar tarea con rofi
capture_task() {
    local task=$(rofi -dmenu -p "📝 Nueva tarea:" \
        -mesg "Escribe la tarea (sin fecha aún)" \
        -theme-str 'window {width: 60%;}')
    
    [[ -z "$task" ]] && exit 0
    
    # Preguntar prioridad
    local priority=$(echo -e "🟡 Normal\n🔴 Urgente (!)\n🔴🔴 Crítico (!!) Cancelar" | \
        rofi -dmenu -p "⚡ Prioridad:" \
        -theme-str 'window {width: 40%;}')
    
    [[ "$priority" == *"Cancelar"* ]] && exit 0
    
    # Preguntar fecha con selector visual
    local date_choice=$(echo -e "📅 Hoy\n📅 Mañana\n📅 Esta semana\n📅 Próxima semana\n📅 Seleccionar fecha\n📅 Sin fecha (Backlog)" | \
        rofi -dmenu -p "📆 ¿Cuándo?" \
        -theme-str 'window {width: 40%;}')
    
    local due=""
    local today=$(date +%Y-%m-%d)
    
    case "$date_choice" in
        *"Hoy"*) due="$today" ;;
        *"Mañana"*) due=$(date -d "+1 day" +%Y-%m-%d) ;;
        *"Esta semana"*) 
            # Viernes de esta semana
            local dow=$(date +%u)
            local days_to_fri=$((5 - dow))
            [[ $days_to_fri -lt 0 ]] && days_to_fri=$((days_to_fri + 7))
            due=$(date -d "+${days_to_fri} days" +%Y-%m-%d)
            ;;
        *"Próxima semana"*)
            # Lunes que viene
            local dow=$(date +%u)
            local days_to_mon=$((8 - dow))
            due=$(date -d "+${days_to_mon} days" +%Y-%m-%d)
            ;;
        *"Seleccionar"*)
            # Calendario interactivo con zenity
            due=$(zenity --calendar --title="📅 Selecciona fecha" \
                --text="¿Cuándo vence?" \
                --date-format="%Y-%m-%d" 2>/dev/null)
            [[ -z "$due" ]] && exit 0
            ;;
        *"Sin fecha"*) due="" ;;
    esac
    
    # Construir tarea
    local full_task="$task"
    
    # Agregar prioridad
    if [[ "$priority" == *"Crítico"* ]]; then
        full_task="!! $full_task"
    elif [[ "$priority" == *"Urgente"* ]]; then
        full_task="! $full_task"
    fi
    
    # Agregar fecha
    if [[ -n "$due" ]]; then
        full_task="$full_task due:$due"
    fi
    
    # Guardar en archivo activo
    mkdir -p "$(dirname "$TODO_ACTIVO")"
    echo "- [ ] $full_task" >> "$TODO_ACTIVO"
    
    # Notificar
    notify-send "✅ Tarea guardada" "$full_task" -t 3000
    
    # Log
    echo "[$(date +%H:%M)] Capturada: $full_task" >> "$HOME/.config/tdo/capture.log"
    
    echo "$full_task"
}

# Main
main() {
    # Verificar que rofi está disponible
    if ! command -v rofi &>/dev/null; then
        echo "Error: rofi no instalado"
        exit 1
    fi
    
    capture_task
}

main "$@"
