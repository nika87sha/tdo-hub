#!/usr/bin/env bash
# ==========================================================
# 🔄 SINCRONIZACIÓN CON GIT
# Sincroniza automáticamente cambios en notas y tareas
# Usa pull --rebase antes de push para evitar conflictos
# ==========================================================

source "$(dirname "$0")/../../core.sh"

# Si viene de un atajo (sin terminal), mostrarse en tmux
ensure_tmux_window "sync" "$0" "$@"

# Validar que git esté disponible
require_command "git" "Git" || exit 1

detect_branch() {
    local target="$1"
    local b=$(git -C "$target" symbolic-ref --short HEAD 2>/dev/null)
    if [[ -z "$b" ]]; then
        b=$(git -C "$target" branch --show-current 2>/dev/null)
    fi
    echo "${b:-main}"
}

sync_with_git() {
    local target_dir="${1:-$NOTES_DIR}"
    
    if [ ! -d "$target_dir/.git" ]; then
        log_warn "GIT" "No es un repositorio git: $target_dir"
        echo -e "${YELLOW}⚠️ No es un repositorio git. Inicializando...${RESET}"
        
        cd "$target_dir" || return 1
        git init
        git config user.email "productivite-hub@local"
        git config user.name "Productivité Hub"
        git add .
        git commit -m "Initial commit from Productivité Hub"
        
        log_ok "GIT" "Repositorio inicializado: $target_dir"
        return 0
    fi
    
    cd "$target_dir" || return 1
    local branch=$(detect_branch "$target_dir")
    
    # 1. PULL REBASE para integrar cambios remotos limpiamente
    echo -e "${BLUE}📥 Intentando pullear cambios remotos (rama: $branch)...${RESET}"
    if git pull --rebase origin "$branch" 2>/dev/null; then
        log_ok "GIT" "Pull exitoso ($branch)"
    else
        # Si falló por rebase en conflicto, abortar para no dejar el repo sucio
        if [ -d "$target_dir/.git/rebase-merge" ] || [ -d "$target_dir/.git/rebase-apply" ]; then
            git rebase --abort 2>/dev/null || true
            log_error "GIT" "Conflicto en pull --rebase; rebase abortado para proteger datos"
            notify "Sync" "⚠️ Conflicto remoto al sincronizar — resuelve manualmente"
            return 1
        fi
        log_warn "GIT" "Sin remoto o pull falló (continuando con commit local)"
    fi
    
    # 2. Verificar cambios locales
    if git status --porcelain | grep -q .; then
        echo -e "${BLUE}📝 Cambios detectados en: $target_dir${RESET}"
        
        git add -A
        local commit_msg="Auto-sync: $(date +'%Y-%m-%d %H:%M:%S')"
        git commit -m "$commit_msg"
        
        log_ok "GIT" "Sincronizado: $commit_msg"
        echo -e "${GREEN}✓ Cambios locales commiteados${RESET}"
    else
        echo -e "${BLUE}ℹ️ Sin cambios pendientes${RESET}"
        log_info "GIT" "Sin cambios pendientes"
    fi
    
    # 3. PUSHEAR cambios
    echo -e "${BLUE}📤 Pusheando cambios a $branch...${RESET}"
    if git push origin "$branch" 2>/dev/null; then
        log_ok "GIT" "Push exitoso ($branch)"
        echo -e "${GREEN}✓ Sincronización completada${RESET}"
        notify "Sync" "✓ Repositorio sincronizado ($branch)"
        return 0
    else
        log_warn "GIT" "No se pudo pushear a origin/$branch (cambios locales guardados)"
        echo -e "${YELLOW}⚠️ Cambios locales guardados pero sin push remoto${RESET}"
        return 0
    fi
}

show_git_status() {
    local target_dir="${1:-$NOTES_DIR}"
    [ ! -d "$target_dir/.git" ] && echo "No es un repositorio git." && return 1
    cd "$target_dir" || return 1
    echo -e "\n${BLUE}📊 Estado del Repositorio:${RESET}\n"
    git status --short
    echo -e "\n${BLUE}📈 Historial Reciente:${RESET}\n"
    git log --oneline -10
}

show_git_log() {
    local target_dir="${1:-$NOTES_DIR}"
    local num_commits="${2:-20}"
    [ ! -d "$target_dir/.git" ] && echo "No es un repositorio git." && return 1
    cd "$target_dir" || return 1
    echo -e "\n${BLUE}📝 Últimos $num_commits commits:${RESET}\n"
    git log --oneline -n "$num_commits"
}

case "$1" in
    ""|"sync")
        sync_with_git "${2:-$NOTES_DIR}"
        ;;
    "--dry-run")
        echo -e "${YELLOW}[DRY-RUN] Operaciones a realizar:${RESET}"
        cd "${2:-$NOTES_DIR}" || exit 1
        b=$(detect_branch "${2:-$NOTES_DIR}")
        echo "1. Git pull --rebase origin $b"
        echo "2. Git add -A"
        echo "3. Git commit (si hay cambios)"
        echo "4. Git push origin $b"
        ;;
    "status") show_git_status "${2:-$NOTES_DIR}" ;;
    "log")    show_git_log "${2:-$NOTES_DIR}" "${3:-20}" ;;
    "--help"|"-h")
        echo "Sincronización con Git de TDO Hub"
        echo ""
        echo "Uso:"
        echo "  sync.sh                → Sincronizar cambios (pull --rebase + commit + push)"
        echo "  sync.sh --dry-run      → Simular sync sin ejecutar"
        echo "  sync.sh status         → Ver estado del repositorio"
        echo "  sync.sh log [n]        → Ver historial (default: 20 commits)"
        ;;
    *)
        echo "Opción desconocida: $1"
        echo "Usa: sync.sh --help para más información"
        exit 1
        ;;
esac