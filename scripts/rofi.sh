#!/usr/bin/env bash
# ==========================================================
# 🎯 ROFI HELPERS - Interfaces unificadas para rofi
# Elimina 15+ patrones inconsistentes en scripts
# ==========================================================

# No sourcear core.sh aquí - ya se carga desde core.sh
# HUB_ROOT debe estar disponible desde el script que carga rofi.sh

# =========== CONFIGURACIÓN TEMA ===========
_ROFI_THEME="${ROFI_THEME:-$HUB_ROOT/themes/hub.rasi}"
_ROFI_FALLBACK="${ROFI_THEME_FALLBACK:-~/.config/rofi/config.rasi}"

_rofi_theme_args() {
    local theme_file="$_ROFI_THEME"
    [[ -f "$theme_file" ]] || theme_file="$_ROFI_FALLBACK"
    [[ -f "$theme_file" ]] && echo "-config $theme_file" || echo ""
}

# =========== MENÚ BÁSICO ===========
# rofi_menu "Prompt" "Mensaje" [opciones_extra_rofi...]
rofi_menu() {
    local prompt="$1"
    local mesg="${2:-}"
    shift 2
    local theme_args=$(_rofi_theme_args)
    
    # shellcheck disable=SC2086
    rofi -dmenu -p "$prompt" -mesg "$mesg" $theme_args "$@"
}

# rofi_menu con keybindings personalizados
# rofi_menu_custom "Prompt" "Mensaje" -kb-custom-1 "Alt+c" ...
rofi_menu_custom() {
    local prompt="$1"
    local mesg="${2:-}"
    shift 2
    local theme_args=$(_rofi_theme_args)
    
    # shellcheck disable=SC2086
    rofi -dmenu -p "$prompt" -mesg "$mesg" $theme_args "$@"
}

# =========== ENTRADA DE TEXTO ===========
# rofi_input "Prompt" "Mensaje" [placeholder]
rofi_input() {
    local prompt="$1"
    local mesg="${2:-}"
    local placeholder="${3:-}"
    local theme_args=$(_rofi_theme_args)
    
    local args=(-dmenu -p "$prompt" -mesg "$mesg")
    [[ -n "$placeholder" ]] && args+=(-theme-str "entry { placeholder: \"$placeholder\"; }")
    
    # shellcheck disable=SC2086
    rofi "${args[@]}" $theme_args
}

# =========== SELECCIÓN MÚLTIPLE ===========
# rofi_multi_select "Prompt" "Mensaje" [opciones_extra_rofi...]
rofi_multi_select() {
    local prompt="$1"
    local mesg="${2:-}"
    shift 2
    local theme_args=$(_rofi_theme_args)
    
    # shellcheck disable=SC2086
    rofi -dmenu -multi-select -p "$prompt" -mesg "$mesg" $theme_args "$@"
}

# =========== CONFIRMACIÓN (Sí/No) ===========
# rofi_confirm "Mensaje" ["Título"]
# Retorna 0=sí, 1=no/cancel
rofi_confirm() {
    local mesg="$1"
    local prompt="${2:-Confirmar}"
    local theme_args=$(_rofi_theme_args)
    
    local choice=$(echo -e "✅ Sí\n❌ No" | rofi -dmenu -p "$prompt" -mesg "$mesg" $theme_args)
    [[ "$choice" == *"Sí"* ]]
}

# =========== SELECTOR DE FECHA ===========
# rofi_date_select "Prompt" "Mensaje"
# Retorna fecha en formato YYYY-MM-DD o vacío
rofi_date_select() {
    local prompt="$1"
    local mesg="${2:-}"
    local theme_args=$(_rofi_theme_args)
    
    local today=$(date +%Y-%m-%d)
    local tomorrow=$(date -d "+1 day" +%Y-%m-%d)
    local friday=$(date -d "friday" +%Y-%m-%d)
    local monday=$(date -d "monday" +%Y-%m-%d)
    local next_monday=$(date -d "next monday" +%Y-%m-%d)
    
    local choice=$(echo -e "📅 Hoy ($today)\n📅 Mañana ($tomorrow)\n📅 Viernes ($friday)\n📅 Lunes ($monday)\n📅 Próximo lunes ($next_monday)\n📅 Seleccionar fecha...\n📅 Sin fecha" | \
        rofi -dmenu -p "$prompt" -mesg "$mesg" $theme_args)
    
    case "$choice" in
        *"Hoy"*) echo "$today" ;;
        *"Mañana"*) echo "$tomorrow" ;;
        *"Viernes"*) echo "$friday" ;;
        *"Lunes"*) echo "$monday" ;;
        *"Próximo lunes"*) echo "$next_monday" ;;
        *"Seleccionar"*) 
            # Fallback a zenity si está disponible
            if command -v zenity &>/dev/null; then
                zenity --calendar --title="📅 Selecciona fecha" --text="$mesg" --date-format="%Y-%m-%d" 2>/dev/null
            else
                rofi_input "Fecha (YYYY-MM-DD)" "$mesg" "YYYY-MM-DD"
            fi
            ;;
        *"Sin fecha"*) echo "" ;;
        *) echo "" ;;
    esac
}

# =========== SELECTOR DE PRIORIDAD ===========
# rofi_priority_select "Prompt" "Mensaje"
# Retorna: "!!" (crítico), "!" (urgente), "" (normal), o vacío si cancel
rofi_priority_select() {
    local prompt="$1"
    local mesg="${2:-}"
    local theme_args=$(_rofi_theme_args)
    
    local choice=$(echo -e "🟢 Normal\n🟡 Urgente (!)\n🔴 Crítico (!!)\n❌ Cancelar" | \
        rofi -dmenu -p "$prompt" -mesg "$mesg" $theme_args)
    
    case "$choice" in
        *"Normal"*) echo "" ;;
        *"Urgente"*) echo "!" ;;
        *"Crítico"*) echo "!!" ;;
        *) echo "CANCEL" ;;
    esac
}

# =========== LISTA CON ICONOS ===========
# rofi_icon_list "Prompt" "Mensaje" "icon1|label1" "icon2|label2" ...
# Retorna el label seleccionado
rofi_icon_list() {
    local prompt="$1"
    local mesg="${2:-}"
    shift 2
    local theme_args=$(_rofi_theme_args)
    
    local items=()
    for item in "$@"; do
        IFS='|' read -r icon label <<< "$item"
        items+=("$icon $label")
    done
    
    printf '%s\n' "${items[@]}" | rofi -dmenu -p "$prompt" -mesg "$mesg" $theme_args | sed 's/^[^ ]* //'
}

# =========== VERIFICACIÓN ===========
# Verificar que rofi está disponible
rofi_check() {
    command -v rofi &>/dev/null || {
        log_err "ROFI" "rofi no instalado"
        return 1
    }
}