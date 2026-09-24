#!/usr/bin/env bash
# ==========================================================
# 📦 INSTALADOR DE PRODUCTIVITÉ-HUB
# Instalación automática y configuración inicial
# ==========================================================

set -e
RESET='\033[0m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OS_TYPE=$(uname -s)

# =========== FUNCIONES ===========
print_header() {
    echo -e "\n${BLUE}╔════════════════════════════════════════════════╗${RESET}"
    echo -e "${BLUE}║  📦 PRODUCTIVITÉ-HUB INSTALLER                 ║${RESET}"
    echo -e "${BLUE}╚════════════════════════════════════════════════╝${RESET}\n"
}

print_step() {
    echo -e "\n${BOLD}${BLUE}→ $1${RESET}"
}

print_success() {
    echo -e "${GREEN}✓ $1${RESET}"
}

print_error() {
    echo -e "${RED}✗ $1${RESET}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${RESET}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${RESET}"
}

confirm() {
    local prompt="$1"
    local response
    read -p "$(echo -e "${YELLOW}$prompt (s/n): ${RESET}")" response
    [[ "$response" =~ ^[Ss]$ ]]
}

# =========== DETECTAR GESTOR DE PAQUETES ===========
detect_package_manager() {
    if command -v apt-get &>/dev/null; then
        PACKAGE_MANAGER="apt-get"
        INSTALL_CMD="sudo apt-get install -y"
    elif command -v pacman &>/dev/null; then
        PACKAGE_MANAGER="pacman"
        INSTALL_CMD="sudo pacman -S --noconfirm"
    elif command -v brew &>/dev/null; then
        PACKAGE_MANAGER="brew"
        INSTALL_CMD="brew install"
    else
        print_error "No se detectó gestor de paquetes. Instala manualmente: apt-get, pacman o brew"
        return 1
    fi
    return 0
}

# =========== INSTALACIÓN DE DEPENDENCIAS ===========
install_dependencies() {
    print_step "Verificando e instalando dependencias"
    
    detect_package_manager || return 1
    
    print_info "Gestor detectado: $PACKAGE_MANAGER"
    
    # Dependencias críticas
    local critical_deps=("zsh" "bash" "rofi" "tmux" "neovim" "git")
    local missing_deps=()
    
    for dep in "${critical_deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            missing_deps+=("$dep")
        else
            print_success "Ya instalado: $dep"
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        print_warning "Dependencias faltantes: ${missing_deps[*]}"
        if confirm "¿Instalarlas ahora?"; then
            $INSTALL_CMD "${missing_deps[@]}"
            print_success "Dependencias instaladas"
        fi
    fi
    
    # Dependencias recomendadas
    local recommended_deps=("fzf" "ripgrep" "python" "libnotify" "mpc" "mpd" "ncmpcpp" "timewarrior")
    # en apt el paquete se llama python3, en pacman python
    [ "$PACKAGE_MANAGER" = "apt-get" ] && recommended_deps=("fzf" "ripgrep" "python3" "libnotify-bin" "mpc" "mpd" "ncmpcpp" "timewarrior")
    for dep in "${recommended_deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            if confirm "¿Instalar $dep (recomendado)?"; then
                $INSTALL_CMD "$dep"
            fi
        fi
    done
}

# =========== CREAR ESTRUCTURA DE DIRECTORIOS ===========
setup_directories() {
    print_step "Configurando estructura de directorios"
    
    local notes_dir="${NOTES_DIR:-$HOME/notes}"
    local templates_dir="${TEMPLATES_DIR:-$notes_dir/templates}"
    local journal_dir="${JOURNAL_DIR:-$notes_dir/journal}"
    
    mkdir -p "$notes_dir"
    mkdir -p "$templates_dir"
    mkdir -p "$journal_dir"

    # Templates por defecto (no sobrescriben los existentes del usuario)
    if [ -d "$SCRIPT_DIR/templates" ]; then
        print_info "Copiando templates por defecto"
        cp -n "$SCRIPT_DIR"/templates/* "$templates_dir/" 2>/dev/null || true
    fi
    mkdir -p "$HOME/.config/focus"
    mkdir -p "$HOME/.local/bin"
    mkdir -p "$HOME/Musica/playlists"
    mkdir -p "$HOME/.mpd"
    
    print_success "Directorios creados en: $notes_dir"
}

# =========== CREAR ARCHIVOS DE CONFIGURACIÓN ===========
setup_config_files() {
    print_step "Creando archivos de configuración"
    
    # .zshrc configuration
    local zshrc="$HOME/.zshrc"
    if [ -f "$zshrc" ]; then
        if ! grep -q "export NOTES_DIR" "$zshrc"; then
            print_info "Agregando configuración a .zshrc"
            cat >> "$zshrc" <<'EOF'

# ===== PRODUCTIVITÉ-HUB =====
export NOTES_DIR="$HOME/notes"
export HUB_ROOT="$HOME/.local/bin/tdo-hub"
source "$HUB_ROOT/config.sh"

# Alias para acceso rápido
alias tdo="bash $HUB_ROOT/hub.sh"
alias tdo-focus="bash $HUB_ROOT/scripts/focus/focus_mode.sh"
alias tdo-panic="bash $HUB_ROOT/scripts/focus/panic_button.sh"
alias tdo-validate="bash $HUB_ROOT/validate.sh"
EOF
            print_success "Configuración agregada a .zshrc"
        else
            print_info "Ya configurado en .zshrc"
        fi
    fi
    
    # MPD configuration
    local mpd_conf="$HOME/.config/mpd/mpd.conf"
    if [ ! -f "$mpd_conf" ] && [ -f "$HOME/.mpd/mpd.conf" ]; then
        print_info "Creando symlink para MPD config"
        mkdir -p "$HOME/.config/mpd"
        ln -sf "$HOME/.mpd/mpd.conf" "$mpd_conf"
        print_success "MPD config linkeado"
    elif [ ! -f "$mpd_conf" ]; then
        print_info "Creando configuración MPD básica"
        mkdir -p "$HOME/.config/mpd"
        cat > "$mpd_conf" <<'EOF'
music_directory "$HOME/Musica"
playlist_directory "$HOME/Musica/playlists"
db_file "$HOME/.mpd/mpd.db"
log_file "$HOME/.mpd/mpd.log"
pid_file "$HOME/.mpd/mpd.pid"
state_file "$HOME/.mpd/mpdstate"
audio_output {
    type "pulse"
    name "pulse audio"
}
bind_to_address "127.0.0.1"
port "6601"
EOF
        print_success "MPD config creado en $mpd_conf"
    fi
}

# =========== PERMISOS DE EJECUCIÓN ===========
set_permissions() {
    print_step "Configurando permisos de ejecución"
    
    chmod +x "$SCRIPT_DIR/hub.sh" 2>/dev/null && print_success "hub.sh"
    chmod +x "$SCRIPT_DIR/core.sh" 2>/dev/null && print_success "core.sh"
    chmod +x "$SCRIPT_DIR/config.sh" 2>/dev/null && print_success "config.sh"
    chmod +x "$SCRIPT_DIR/validate.sh" 2>/dev/null && print_success "validate.sh"
    
    chmod +x "$SCRIPT_DIR"/scripts/*/*.sh 2>/dev/null && print_success "scripts/ (subcarpetas)"
    chmod +x "$SCRIPT_DIR"/scripts/*.sh 2>/dev/null && print_success "scripts/"
}

# =========== VALIDACIÓN ===========
run_validation() {
    print_step "Ejecutando validación del sistema"
    
    if [ -x "$SCRIPT_DIR/validate.sh" ]; then
        bash "$SCRIPT_DIR/validate.sh"
    else
        print_warning "No se pudo ejecutar validate.sh"
    fi
}

# =========== CRON JOBS ===========
setup_cron() {
    print_step "Configurando cron jobs"
    
    local cron_marker="# TDO Hub"
    local cron_entries="$cron_marker
0 9 * * * bash $SCRIPT_DIR/scripts/notes/daily-routine.sh --quiet --sync
0 21 * * * notify-send '📓 Journal' '¿Qué aprendiste hoy?' -u normal"
    
    # Verificar si ya existen los cron jobs de TDO
    if crontab -l 2>/dev/null | grep -q "$cron_marker"; then
        print_info "Cron jobs de TDO ya configurados"
    else
        if confirm "¿Configurar cron jobs automáticamente? (daily-routine, recordatorio journal)"; then
            (crontab -l 2>/dev/null; echo "$cron_entries") | crontab -
            print_success "Cron jobs configurados"
        else
            print_info "Cron jobs no configurados. Puedes agregarlos manualmente después."
        fi
    fi
}

# =========== MENÚ INTERACTIVO ===========
print_header

print_info "Este script instalará Productivité-Hub y sus dependencias."
print_info "Se requieren permisos de sudo para algunas operaciones.\n"

if ! confirm "¿Deseas continuar con la instalación?"; then
    print_info "Instalación cancelada."
    exit 0
fi

# Ejecutar instalación
install_dependencies || {
    print_warning "Algunos paquetes no se pudieron instalar automáticamente."
    print_info "Puedes intentar instalarlos manualmente después."
}

setup_directories
setup_config_files
set_permissions
setup_cron
run_validation

# =========== CONCLUSIÓN ===========
echo -e "\n${BLUE}╔════════════════════════════════════════════════╗${RESET}"
echo -e "${GREEN}✅ INSTALACIÓN COMPLETADA${RESET}"
echo -e "${BLUE}╚════════════════════════════════════════════════╝${RESET}\n"

echo -e "${BOLD}Próximos pasos:${RESET}"
echo -e "1. Recarga tu terminal: ${YELLOW}source ~/.zshrc${RESET}"
echo -e "2. Valida la instalación: ${YELLOW}bash validate.sh${RESET}"
echo -e "3. Inicia el hub: ${YELLOW}tdo${RESET} (o ${YELLOW}bash hub.sh${RESET})"
echo -e "\n${BOLD}Documentación:${RESET}"
echo -e "• README: ${BLUE}README.md${RESET}"
echo -e "• Configuración: ${BLUE}.env.example${RESET}\n"
