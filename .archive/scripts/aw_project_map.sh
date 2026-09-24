#!/usr/bin/env bash
# ==========================================================
# 📋 AW_PROJECT_MAP - Mapeo título ventana → código proyecto
# Permite clasificar eventos ActivityWatch a proyectos facturables
# ==========================================================

source "$(dirname "$0")/../core.sh"

MAP_FILE="${AW_PROJECT_MAP_FILE:-$HUB_ROOT/project_map.json}"

# =========== MAPA POR DEFECTO ===========
default_map() {
    cat <<'EOF'
{
  "JIRA": ["JIRA", "jira.atlassian", "jira.", "browse/"],
  "GITHUB": ["github.com", "github.", "pull request", "pull-request"],
  "GITLAB": ["gitlab.com", "gitlab.", "merge request"],
  "SLACK": ["slack.com", "slack.", "Slack"],
  "TEAMS": ["teams.microsoft", "teams.", "Teams"],
  "OUTLOOK": ["outlook.", "mail.google", "gmail.", "correo"],
  "CONFLUENCE": ["confluence", "wiki."],
  "DOCS": ["docs.google", "notion.so", "notion.", "office.com"],
  "TERMINAL": ["Alacritty", "kitty", "tmux", "ssh ", "vim ", "nvim ", "code "],
  "DOCKER": ["docker", "container", "k8s", "kubernetes", "kubectl"],
  "AWS": ["aws.amazon", "console.aws", "cloudformation"],
  "AZURE": ["portal.azure", "dev.azure", "azure.com"],
  "MEET": ["meet.google", "zoom.us", "teams.microsoft.com/meet"],
  "BROWSER": ["firefox", "chrome", "brave", "edge", "chromium"]
}
EOF
}

# =========== FUNCIONES ===========

# Cargar mapa (crea default si no existe)
load_map() {
    if [[ ! -f "$MAP_FILE" ]]; then
        default_map > "$MAP_FILE"
        log_info "PROJECT_MAP" "Creado mapa por defecto: $MAP_FILE"
    fi
    cat "$MAP_FILE"
}

# Clasificar un evento AW (app + title) → código proyecto
classify_event() {
    local app="$1"
    local title="$2"
    local map_json=$(load_map)
    
    # Combinar app + title para matching
    local haystack="${app} ${title}"
    haystack=$(echo "$haystack" | tr '[:upper:]' '[:lower:]')
    
    echo "$map_json" | python3 -c "
import sys, json, re
data = json.load(sys.stdin)
haystack = '$haystack'
for project, patterns in data.items():
    for pat in patterns:
        if re.search(pat.lower(), haystack):
            print(project)
            sys.exit(0)
print('OTROS')
"
}

# Clasificar múltiples eventos desde stdin (JSON AW)
# Input: eventos AW en stdin
# Output: líneas "proyecto|duración|app|title"
classify_events() {
    python3 -c "
import sys, json, re
events = json.load(sys.stdin)
map_file = '$MAP_FILE'
with open(map_file) as f:
    pmap = json.load(f)

for e in events:
    data = e.get('data', {})
    app = data.get('app', 'unknown')
    title = data.get('title', '')
    dur = e.get('duration', 0)
    haystack = f'{app} {title}'.lower()
    
    project = 'OTROS'
    for proj, patterns in pmap.items():
        for pat in patterns:
            if re.search(pat.lower(), haystack):
                project = proj
                break
        if project != 'OTROS':
            break
    print(f'{project}|{dur}|{app}|{title}')
"
}

# Resumen por proyecto para un rango de fechas
# Uso: project_summary "2024-01-15" "2024-01-15"
project_summary() {
    local start="$1"
    local end="$2"
    local bucket="${3:-$AW_BUCKET_WINDOW}"
    
    local api_base=$(_aw_resolve_api 2>/dev/null) || return 1
    local events=$(curl -sL --connect-timeout 5 "${api_base}/api/0/buckets/${bucket}/events" \
        -G -d "start=${start}T00:00:00Z" -d "end=${end}T23:59:59Z" -d "limit=10000" 2>/dev/null)
    
    [[ -z "$events" || "$events" == "[]" ]] && return 1
    
    echo "$events" | classify_events | awk -F'|' '
    {
        proj[$1] += $2
        total += $2
    }
    END {
        for (p in proj) {
            hours = proj[p] / 3600
            pct = (proj[p] / total) * 100
            printf \"%-15s %6.2fh (%5.1f%%)\n\", p, hours, pct
        }
        printf \"%-15s %6.2fh (100.0%%)\n\", \"TOTAL\", total/3600
    }' | sort -k2 -nr
}

# Editar mapa interactivamente
edit_map() {
    ${EDITOR:-nvim} "$MAP_FILE"
}

# Ver mapa actual
show_map() {
    load_map | python3 -m json.tool
}

# Añadir/actualizar patrón
add_pattern() {
    local project="$1"
    local pattern="$2"
    [[ -z "$project" || -z "$pattern" ]] && { echo "Uso: add_pattern PROYECTO patrón_regex"; return 1; }
    
    local map_json=$(load_map)
    echo "$map_json" | python3 -c "
import sys, json
data = json.load(sys.stdin)
proj = '$project'
pat = '$pattern'
if proj not in data:
    data[proj] = []
if pat not in data[proj]:
    data[proj].append(pat)
json.dump(data, sys.stdout, indent=2)
" > "$MAP_FILE"
    log_info "PROJECT_MAP" "Añadido patrón '$pattern' a proyecto '$project'"
}

# =========== MAIN (solo si se ejecuta directamente) ===========
aw_project_map_main() {
    case "${1:-}" in
        classify)
            classify_event "$2" "$3"
            ;;
        summary)
            project_summary "$2" "${3:-$2}" "$4"
            ;;
        events)
            classify_events
            ;;
        edit)
            edit_map
            ;;
        show)
            show_map
            ;;
        add)
            add_pattern "$2" "$3"
            ;;
        *)
            echo "Uso: $0 {classify|summary|events|edit|show|add}"
            echo ""
            echo "  classify \"app\" \"title\"     -> imprime código proyecto"
            echo "  summary \"YYYY-MM-DD\" [end]  -> resumen horas por proyecto"
            echo "  events                       -> clasifica eventos AW desde stdin"
            echo "  edit                         -> editar $MAP_FILE en \$EDITOR"
            echo "  show                         -> ver mapa actual"
            echo "  add PROYECTO patrón          -> añadir patrón regex"
            return 1
            ;;
    esac
}

# Solo ejecutar main si no se está sourceando
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && aw_project_map_main "$@"