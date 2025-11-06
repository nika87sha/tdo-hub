#!/usr/bin/env bash
# ==========================================================
# 🎵 FOCUS MUSIC - Música para TDO Hub (2 niveles)
# Nivel 1: Categorías | Nivel 2: Items
# Usa mpc con socket Unix
# ==========================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HUB_ROOT="$(dirname "$SCRIPT_DIR")"
source "$HUB_ROOT/config.sh"

# Función mpc que usa socket si existe, sino TCP
mpc_cmd() {
    if [[ -S ~/.config/mpd/socket ]]; then
        MPD_HOST=~/.config/mpd/socket command mpc "$@" 2>/dev/null
    else
        command mpc --host 127.0.0.1 --port 6601 "$@" 2>/dev/null
    fi
}

# Verificar MPD
if ! mpc_cmd status | grep -q "volume"; then
    notify-send "🎵" "MPD no está corriendo"
    exit 1
fi

case "${1:-}" in
    stop)
        mpc_cmd stop > /dev/null
        mpc_cmd clear > /dev/null
        exit 0
        ;;
    play)
        # play <dir> [label]: lo usa focus_mode.sh con presets
        # (antes se ignoraba y siempre abría el menú interactivo)
        DIR="${2:-/}"
        LABEL="${3:-$DIR}"
        mpc_cmd clear > /dev/null
        mpc_cmd add "$DIR" > /dev/null
        mpc_cmd shuffle > /dev/null
        mpc_cmd play > /dev/null
        notify-send "🎵" "Sonando: $LABEL"
        exit 0
        ;;
esac

# ==========================================================
# NIVEL 1: CATEGORÍAS PRINCIPALES
# ==========================================================

CAT_SEL=$(echo -e "🔀 Shuffle todo\n📁 Playlists\n📂 Carpetas\n⏹️ Parar" | \
    rofi -dmenu -p "🎵 Música" -config ~/.config/rofi/config.rasi 2>/dev/null)

[[ -z "$CAT_SEL" ]] && exit 0

CAT_SEL=$(echo "$CAT_SEL" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')

# ==========================================================
# NIVEL 2: ITEMS SEGÚN CATEGORÍA
# ==========================================================

case "$CAT_SEL" in
    "🔀 Shuffle todo")
        mpc_cmd clear > /dev/null
        mpc_cmd add / > /dev/null
        mpc_cmd shuffle > /dev/null
        mpc_cmd play > /dev/null
        notify-send "🎵" "Shuffle: toda la música"
        exit 0
        ;;
    "⏹️ Parar")
        mpc_cmd stop > /dev/null
        mpc_cmd clear > /dev/null
        notify-send "🎵" "Música parada"
        exit 0
        ;;
"📁 Playlists")
        ITEM_SEL=$(echo -e "electronica (131)\naitana (99)\nmago_de_oz (739)\nlafuga (238)\npop_rock (154)\nmalicia (1270)" | \
            rofi -dmenu -p "📁 Playlists" -config ~/.config/rofi/config.rasi 2>/dev/null)
        [[ -z "$ITEM_SEL" ]] && exit 0
        PLAYLIST=$(echo "$ITEM_SEL" | sed 's/ (.*//' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
        mpc_cmd clear > /dev/null
        mpc_cmd load "$PLAYLIST" > /dev/null
        mpc_cmd shuffle > /dev/null
        mpc_cmd play > /dev/null
        notify-send "🎵" "Playlist: $PLAYLIST"
        ;;
    "📂 Carpetas")
        # Obtener carpetas que MPD indexa
        FOLDERS=$(mpc_cmd listall | grep -v '^/' | sed 's|/.*||' | sort -u | grep -v '^$' | head -50)
        ITEM_SEL=$(echo "$FOLDERS" | rofi -dmenu -p "📂 Carpetas" -config ~/.config/rofi/config.rasi 2>/dev/null)
        [[ -z "$ITEM_SEL" ]] && exit 0
        FOLDER=$(echo "$ITEM_SEL" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
        mpc_cmd clear > /dev/null
        mpc_cmd add "$FOLDER" > /dev/null
        mpc_cmd shuffle > /dev/null
        mpc_cmd play > /dev/null
        notify-send "🎵" "Carpeta: $FOLDER"
        ;;
esac