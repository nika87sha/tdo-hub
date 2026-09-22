#!/usr/bin/env bash
# ==========================================================
# 🔍 VALIDADOR DE DEPENDENCIAS Y CONFIGURACIÓN - TDO Hub
# Verifica dependencias, rutas, permisos y calidad de código
# ==========================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/core.sh"

# Contadores
TOTAL=0
PASSED=0
FAILED=0
WARNINGS=0

# =========== FUNCIONES ===========
log_check() {
    local status="$1"
    local message="$2"
    TOTAL=$((TOTAL + 1))
    
    case "$status" in
        "✓")
            echo -e "${GREEN}✓${RESET} $message"
            PASSED=$((PASSED + 1))
            ;;
        "✗")
            echo -e "${RED}✗${RESET} $message"
            FAILED=$((FAILED + 1))
            ;;
        "⚠")
            echo -e "${YELLOW}⚠${RESET} $message"
            WARNINGS=$((WARNINGS + 1))
            ;;
    esac
}

check_command() {
    local cmd="$1"
    local name="${2:-$cmd}"
    
    if command -v "$cmd" &>/dev/null; then
        log_check "✓" "Comando disponible: $name"
        return 0
    else
        log_check "✗" "Comando FALTA: $name"
        return 1
    fi
}

check_command_optional() {
    local cmd="$1"
    local name="${2:-$cmd}"
    
    if command -v "$cmd" &>/dev/null; then
        log_check "✓" "Comando disponible: $name"
        return 0
    else
        log_check "⚠" "Comando no disponible (opcional): $name"
        return 1
    fi
}

check_directory() {
    local dir="$1"
    local name="${2:-$dir}"
    
    if [ -d "$dir" ]; then
        log_check "✓" "Directorio existe: $name"
        return 0
    else
        log_check "⚠" "Directorio no existe: $name (se creará automáticamente)"
        return 1
    fi
}

check_file() {
    local file="$1"
    local name="${2:-$(basename "$file")}"
    
    if [ -f "$file" ]; then
        log_check "✓" "Archivo existe: $name"
        return 0
    else
        log_check "⚠" "Archivo no existe: $name"
        return 1
    fi
}

check_executable() {
    local file="$1"
    local name="${2:-$(basename "$file")}"
    
    if [ -x "$file" ]; then
        log_check "✓" "Ejecutable: $name"
        return 0
    else
        log_check "⚠" "Sin permisos de ejecución: $name (usar: chmod +x)"
        return 1
    fi
}

# =========== VALIDACIONES ===========
echo -e "\n${BLUE}╔════════════════════════════════════════════════╗${RESET}"
echo -e "${BLUE}║  🔍 VALIDADOR DE TDO-HUB                       ║${RESET}"
echo -e "${BLUE}╚════════════════════════════════════════════════╝${RESET}\n"

# 1. DEPENDENCIAS CRÍTICAS
echo -e "${BLUE}📦 Dependencias Críticas:${RESET}"
check_command "bash" "Bash"
check_command "rofi" "Rofi (UI Menus)"
check_command "tmux" "Tmux (Terminal Multiplexer)"
check_command "nvim" "Neovim"
check_command "git" "Git"

# 2. DEPENDENCIAS RECOMENDADAS
echo -e "\n${BLUE}🎁 Dependencias Recomendadas:${RESET}"
check_command "fzf" "FZF (Fuzzy Finder)"
check_command "rg" "Ripgrep (Fast Search)"
check_command "notify-send" "Libnotify (Desktop Notifications)"
check_command "mpc" "MPC (MPD Client)"
check_command "mpd" "MPD (Music Player Daemon)"
check_command "ncmpcpp" "NCMPCPP (MPD Client TUI)"
check_command "timew" "Timewarrior (Time Tracking)"
check_command "python3" "Python 3"

# 3. DEPENDENCIAS OPCIONALES
echo -e "\n${BLUE}✨ Dependencias Opcionales:${RESET}"
check_command_optional "dunstctl" "Dunst (Notification Manager)"
check_command_optional "shellcheck" "Shellcheck (Linter)"

# 4. MÚSICA
echo -e "\n${BLUE}🎵 Música (TDO):${RESET}"
if [[ -S ~/.config/mpd/socket ]]; then
    log_check "✓" "MPD Socket Unix activo"
elif mpc -p "${MPC_PORT:-6601}" status &>/dev/null; then
    log_check "✓" "MPD conecta por TCP (puerto ${MPC_PORT:-6601})"
else
    log_check "⚠" "MPD no detectado (focus mode sin música)"
fi

# 5. DIRECTORIOS
echo -e "\n${BLUE}📁 Estructura de Directorios:${RESET}"
check_directory "$NOTES_DIR" "Notas ($NOTES_DIR)"
check_directory "$PROJECTS_DIR" "Proyectos ($PROJECTS_DIR)"
check_directory "$INBOX_DIR" "Inbox ($INBOX_DIR)"
check_directory "$TEMPLATES_DIR" "Templates ($TEMPLATES_DIR)"
check_directory "$SCRIPT_DIR/scripts" "Scripts"
check_directory "$JOURNAL_DIR" "Journal ($JOURNAL_DIR)"
check_directory "$TODOS_DIR" "Todos ($TODOS_DIR)"

# 6. ARCHIVOS CONFIGURACIÓN
echo -e "\n${BLUE}⚙️ Archivos de Configuración:${RESET}"
check_file "$SCRIPT_DIR/config.sh" "config.sh"
check_file "$SCRIPT_DIR/core.sh" "core.sh"
check_file "$SCRIPT_DIR/.env" ".env (personal)"
check_file "$SCRIPT_DIR/.env.example" ".env.example"
check_file "$SCRIPT_DIR/bloqueo_distraccion.txt" "bloqueo_distraccion.txt"
check_file "$SCRIPT_DIR/phrases.txt" "phrases.txt"
check_file "$SCRIPT_DIR/templates/entry.md" "entry.md (journal)"
check_file "$SCRIPT_DIR/templates/note.md" "note.md (notas)"

# 7. SCRIPTS
echo -e "\n${BLUE}🔧 Scripts:${RESET}"
SCRIPT_COUNT=0
for s in "$SCRIPT_DIR"/scripts/*.sh; do
    [ -f "$s" ] || continue
    SCRIPT_COUNT=$((SCRIPT_COUNT + 1))
    check_executable "$s" "$(basename "$s")" || true
done
log_check "✓" "$SCRIPT_COUNT scripts encontrados"

# 8. PERMISOS
echo -e "\n${BLUE}🔐 Permisos:${RESET}"
check_executable "$SCRIPT_DIR/hub.sh" "hub.sh"
check_executable "$SCRIPT_DIR/validate.sh" "validate.sh"

# 9. TAREAS
echo -e "\n${BLUE}📋 Sistema de Tareas:${RESET}"
if [ -f "$TODO_ACTIVO" ]; then
    PENDING=$(grep -c '^\- \[ \]' "$TODO_ACTIVO" 2>/dev/null || echo 0)
    DONE=$(grep -c '^\- \[x\]' "$TODO_ACTIVO" 2>/dev/null || echo 0)
    log_check "✓" "todo_ACTIVO: $PENDING pendientes, $DONE completadas"
else
    log_check "⚠" "todo_ACTIVO no existe (se creará al primer uso)"
fi

# 10. /etc/hosts (focus mode)
echo -e "\n${BLUE}🛡️ Focus Mode:${RESET}"
if [ -w "/etc/hosts" ]; then
    log_check "✓" "Escritura en /etc/hosts (focus mode habilitado)"
else
    log_check "⚠" "Sin escritura en /etc/hosts (focus requiere sudo)"
fi

# 11. SHELLCHECK
echo -e "\n${BLUE}🔍 Shellcheck:${RESET}"
if command -v shellcheck &>/dev/null; then
    SHELLCHECK_ERRORS=0
    SHELLCHECK_CHECKED=0
    for script in "$SCRIPT_DIR"/scripts/*.sh "$SCRIPT_DIR"/hub.sh "$SCRIPT_DIR"/core.sh "$SCRIPT_DIR"/validate.sh; do
        [ -f "$script" ] || continue
        SHELLCHECK_CHECKED=$((SHELLCHECK_CHECKED + 1))
        if shellcheck -x -e SC1091 -e SC2034 "$script" >/dev/null 2>&1; then
            log_check "✓" "shellcheck: $(basename "$script")"
        else
            ERRORS=$(shellcheck -x -e SC1091 -e SC2034 "$script" 2>&1 | grep -c "error:" || true)
            log_check "⚠" "shellcheck: $(basename "$script") ($ERRORS issues)"
            SHELLCHECK_ERRORS=$((SHELLCHECK_ERRORS + ERRORS))
        fi
    done
    if [ "$SHELLCHECK_ERRORS" -gt 0 ]; then
        log_check "⚠" "$SHELLCHECK_ERRORS problemas shellcheck (no críticos)"
    else
        log_check "✓" "shellcheck: $SHELLCHECK_CHECKED scripts limpios"
    fi
else
    log_check "⚠" "shellcheck no disponible (instalar: pacman -S shellcheck)"
fi

# 12. ACTIVITYWATCH
echo -e "\n${BLUE}📊 ActivityWatch:${RESET}"
if curl -sL --connect-timeout 2 "${AW_FALLBACK_SERVER:-http://localhost:5600}/api/0/buckets" >/dev/null 2>&1; then
    log_check "✓" "ActivityWatch detectado en ${AW_FALLBACK_SERVER:-localhost:5600}"
else
    log_check "⚠" "ActivityWatch no detectado (stats no funcionarán)"
fi

# 13. TMUX
echo -e "\n${BLUE}🖥️ Tmux:${RESET}"
if tmux list-sessions 2>/dev/null | head -1 | grep -q .; then
    SESSION_COUNT=$(tmux list-sessions 2>/dev/null | wc -l)
    log_check "✓" "$SESSION_COUNT sesiones tmux activas"
else
    log_check "⚠" "Sin sesiones tmux (se crearán al usar hub)"
fi

# =========== RESUMEN ===========
echo -e "\n${BLUE}╔════════════════════════════════════════════════╗${RESET}"
echo -e "${BLUE}║ 📊 RESUMEN                                    ║${RESET}"
echo -e "${BLUE}╚════════════════════════════════════════════════╝${RESET}"
echo -e "  Total:        $TOTAL"
echo -e "  ${GREEN}Pasadas:      $PASSED${RESET}"
echo -e "  ${YELLOW}Advertencias: $WARNINGS${RESET}"
echo -e "  ${RED}Fallos:       $FAILED${RESET}\n"

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✅ Sistema listo para usar!${RESET}"
    echo -e "  Ejecuta: ${YELLOW}bash hub.sh${RESET} o pulsa ${YELLOW}SUPER+N${RESET}\n"
    exit 0
else
    echo -e "${RED}❌ $FAILED problemas críticos. Instala las dependencias faltantes.${RESET}\n"
    exit 1
fi
