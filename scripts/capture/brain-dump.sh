#!/usr/bin/env bash
# ==========================================================
# 🧠 BRAIN DUMP - Captura en 3 segundos (rofi → .md del día)
# Uso directo (SUPER+Alt+B) o desde hub.sh
# Formato compatible con daily-routine (cuenta "^- ").
# ==========================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${0}}")" && pwd)"
source "$SCRIPT_DIR/../../core.sh"

brain_file_today() {
    local today=$(date +%Y-%m-%d)
    local f="$INBOX_DIR/brain_dump/dump_$today.md"
    if [[ ! -f "$f" ]]; then
        mkdir -p "$(dirname "$f")"
        printf -- '---\ndate: %s\ntags: [brain_dump]\n---\n\n# Brain Dump %s\n' "$today" "$today" > "$f"
    fi
    echo "$f"
}

# Palabras clave que marcan automáticamente con ★
AUTO_STAR_KEYWORDS="idea|aprendizaje|importante|clave|nota|recordar|insight|descubrir|problema|solución|bug|feature|deploy|reunión|meeting|llamada|email|pendiente|urgente|importante|deadline|fecha|task|todo"

auto_star() {
    local texto="$1"
    if echo "$texto" | grep -qiE "$AUTO_STAR_KEYWORDS"; then
        echo "★ $texto"
    else
        echo "$texto"
    fi
}

brain_append() {
    local texto="$1"
    [[ -z "$texto" ]] && return 1
    local f=$(brain_file_today)
    texto=$(auto_star "$texto")
    printf -- '- %s %s\n' "$(date +%H:%M)" "$texto" >> "$f"
    notify "🧠 Guardado" "$texto"
    echo "$f"
}

main() {
    require_command "rofi" "Rofi" || exit 1
    local texto=$(rofi_menu "🧠 Brain dump" "3 palabras bastan (Esc cancela)" 2>/dev/null)
    [[ -z "$texto" ]] && exit 0
    brain_append "$texto"
}

# Solo main si se ejecuta directo (permite testear funciones con source)
if [[ "${BASH_SOURCE[0]:-${0}}" == "$0" ]]; then
    main "$@"
fi
