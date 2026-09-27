#!/usr/bin/env bash
# ==========================================================
# 🚀 TDO-HUB INSTALLER
# Bootstrap: deps → dirs → sudoers → .env → doctor
# ==========================================================

set -euo pipefail

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${RESET} $*"; }
log_ok() { echo -e "${GREEN}[OK]${RESET} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${RESET} $*"; }
log_error() { echo -e "${RED}[ERROR]${RESET} $*" >&2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HUB_ROOT="$(dirname "$SCRIPT_DIR")"

# ==========================================================
# 1. DEPENDENCY CHECK
# ==========================================================
check_deps() {
    log_info "Verificando dependencias..."

    local critical=(bash tmux nvim)
    local recommended=(rofi fzf rg notify-send mpc timew)
    local optional=(dunstctl shellcheck bats)

    local missing_critical=0
    for cmd in "${critical[@]}"; do
        if command -v "$cmd" &>/dev/null; then
            log_ok "$cmd"
        else
            log_error "$cmd (CRÍTICO)"
            ((missing_critical++))
        fi
    done

    for cmd in "${recommended[@]}"; do
        if command -v "$cmd" &>/dev/null; then
            log_ok "$cmd"
        else
            log_warn "$cmd (recomendado)"
        fi
    done

    for cmd in "${optional[@]}"; do
        if command -v "$cmd" &>/dev/null; then
            log_ok "$cmd"
        else
            log_warn "$cmd (opcional)"
        fi
    done

    if [[ $missing_critical -gt 0 ]]; then
        log_error "Faltan $missing_critical dependencias críticas. Instálalas y re-ejecuta."
        return 1
    fi
    log_ok "Dependencias verificadas"
}

# ==========================================================
# 2. DIRECTORY STRUCTURE
# ==========================================================
create_dirs() {
    log_info "Creando estructura de directorios..."

    # Load config to get paths
    source "$HUB_ROOT/config.sh" 2>/dev/null

    local dirs=(
        "$NOTES_DIR"
        "$PROJECTS_DIR"
        "$TODOS_DIR"
        "$INBOX_DIR"
        "$TEMPLATES_DIR"
        "$JOURNAL_DIR"
        "$WORKLOG_DIR"
        "$ARCHIVE_DIR"
        "$LOG_DIR"
        "$HOME/.config/tdo"
        "$HOME/.local/share/tdo"
    )

    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            log_ok "Creado: $dir"
        else
            log_ok "Existe: $dir"
        fi
    done
}

# ==========================================================
# 3. SUDOERS SETUP
# ==========================================================
setup_sudoers() {
    log_info "Configurando sudoers para focus mode..."

    local sudoers_file="/etc/sudoers.d/tdo-hub"
    local sudoers_src="$HUB_ROOT/scripts/system/install-sudoers.sh"

    if [[ ! -f "$sudoers_src" ]]; then
        log_warn "No se encuentra $sudoers_src, saltando..."
        return 0
    fi

    if sudo -n /usr/bin/cp /etc/hosts /dev/null 2>/dev/null; then
        log_ok "Sudoers ya configurado"
        return 0
    fi

    log_warn "Sudoers no configurado. Instalando..."
    if sudo bash -c "cat '$sudoers_src' > '$sudoers_file'" && sudo visudo -c -f "$sudoers_file"; then
        log_ok "Sudoers instalado en $sudoers_file"
    else
        log_error "Error instalando sudoers. Ejecuta manualmente:"
        echo "  sudo bash -c 'cat $sudoers_src > $sudoers_file' && sudo visudo -c -f $sudoers_file"
        return 1
    fi
}

# ==========================================================
# 4. ENV TEMPLATE
# ==========================================================
setup_env() {
    log_info "Configurando .env..."

    local env_file="$HUB_ROOT/.env"
    local env_example="$HUB_ROOT/.env.example"

    if [[ -f "$env_file" ]]; then
        log_ok ".env ya existe"
        return 0
    fi

    if [[ ! -f "$env_example" ]]; then
        log_error "No se encuentra .env.example"
        return 1
    fi

    cp "$env_example" "$env_file"
    log_ok "Creado .env desde .env.example"
    log_warn "EDITA $env_file con tus rutas y configuración"
}

# ==========================================================
# 5. VALIDATE WITH DOCTOR
# ==========================================================
run_doctor() {
    log_info "Ejecutando doctor..."

    if bash "$HUB_ROOT/hub.sh" doctor; then
        log_ok "Doctor: sistema sano"
    else
        log_warn "Doctor reportó advertencias (ver arriba)"
    fi
}

# ==========================================================
# MAIN
# ==========================================================
main() {
    echo -e "${BLUE}╔════════════════════════════════════════════════╗${RESET}"
    echo -e "${BLUE}║${RESET}  🚀 TDO-HUB INSTALLER                          ${BLUE}║${RESET}"
    echo -e "${BLUE}╚════════════════════════════════════════════════╝${RESET}\n"

    check_deps || exit 1
    echo
    create_dirs
    echo
    setup_sudoers || exit 1
    echo
    setup_env || exit 1
    echo
    run_doctor
    echo

    log_ok "¡Instalación completada!"
    echo
    echo "Próximos pasos:"
    echo "  1. Edita ~/.local/bin/tdo-hub/.env con tus rutas"
    echo "  2. Ejecuta: bash ~/.local/bin/tdo-hub/hub.sh doctor"
    echo "  3. Añade keybinds a Hyprland (ver README.md)"
    echo "  4. ¡Disfruta!"
}

main "$@"