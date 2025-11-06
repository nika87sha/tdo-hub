#!/usr/bin/env bash
# ==========================================================
# 🎵 REGENERAR PLAYLISTS desde estructura actual
# Soporta: carpetas directas y .m3u con rutas
# ==========================================================

MUSIC_DIR="$HOME/Musica"
PLAYLIST_DIR="$HOME/Musica/playlists"

echo "=== REGENERANDO PLAYLISTS ==="

# Playlists a regenerar (basadas en carpetas principales o .m3u existentes)
declare -A PLAYLISTS=(
    ["aitana"]="aitana"
    ["electronica"]="electronica"
    ["lafuga"]="la_fuga"
    ["magodeoz"]="mago_de_oz"
    ["mago_de_oz"]="mago_de_oz"
    ["pop_rock"]="pop_rock"
    ["malicia"]="malicia"
)

for playlist in "${!PLAYLISTS[@]}"; do
    source="${PLAYLISTS[$playlist]}"
    echo "Regenerando: $playlist.m3u ← $source"
    
    source_path="$MUSIC_DIR/$source"
    output="$PLAYLIST_DIR/${playlist}.m3u"
    
    if [[ -d "$source_path" ]]; then
        # Es una carpeta: buscar archivos recursivamente
        find "$source_path" -type f \( -iname "*.mp3" -o -iname "*.ogg" -o -iname "*.flac" -o -iname "*.wav" -o -iname "*.m4a" \) \
            -printf "%p\n" | sort > "$output"
    elif [[ -f "$PLAYLIST_DIR/${source}.m3u" ]]; then
        # Es un .m3u existente con rutas: leer y expandir
        temp_output=$(mktemp)
        > "$temp_output"
        while IFS= read -r line; do
            [[ -z "$line" || "$line" =~ ^# ]] && continue
            if [[ -d "$line" ]]; then
                find "$line" -type f \( -iname "*.mp3" -o -iname "*.ogg" -o -iname "*.flac" -o -iname "*.wav" -o -iname "*.m4a" \) \
                    -printf "%p\n" >> "$temp_output"
            elif [[ -f "$line" ]]; then
                echo "$line" >> "$temp_output"
            fi
        done < "$PLAYLIST_DIR/${source}.m3u"
        sort -o "$output" "$temp_output"
        rm -f "$temp_output"
    else
        echo "  ⚠️  Origen no encontrado: $source"
        continue
    fi
    
    count=$(wc -l < "$output")
    echo "  ✓ $playlist.m3u ($count canciones)"
done

echo
echo "=== LISTO ==="
echo "Ejemplo lafuga.m3u:"
head -5 "$PLAYLIST_DIR/lafuga.m3u"