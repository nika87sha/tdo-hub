#!/usr/bin/env bash
# ==========================================================
# 🎙️ VOICE NOTE - Graba 5s, transcribe y guarda en brain dump
# Uso directo (SUPER+Alt+M) o desde hub.sh
# Grabación: pw-record (PipeWire) → parec → arecord.
# STT: whisper (tiny, rápido) si funciona; si no, guarda el
# audio y deja la nota con su ruta para transcribir después.
# ==========================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${0}}")" && pwd)"
source "$SCRIPT_DIR/../core.sh"

RECORD_SECS="${RECORD_SECS:-5}"
AUDIO_DIR="${AUDIO_DIR:-$INBOX_DIR/voice}"

pick_recorder() {
    if command -v pw-record &>/dev/null; then
        echo "pw-record --rate=16000 --channels=1"
    elif command -v parec &>/dev/null; then
        echo "parec --rate=16000 --channels=1 --format=s16le"
    elif command -v arecord &>/dev/null; then
        echo "arecord -r 16000 -c 1 -f S16_LE"
    else
        echo ""
    fi
}

transcribe_file() {
    local wav="$1"
    command -v whisper &>/dev/null || return 1
    # tiny = el más rápido; timeout por si el motor cuelga
    timeout 120 whisper "$wav" --model tiny --language Spanish \
        --output_format txt --output_dir "$(dirname "$wav")" \
        --fp16 False >/dev/null 2>&1 || return 1
    local txt="${wav%.wav}.txt"
    [[ -f "$txt" ]] && { cat "$txt"; rm -f "$txt"; return 0; }
    return 1
}

voice_append() {
    local texto="$1" wav_ref="$2"
    local today=$(date +%Y-%m-%d)
    local f="$INBOX_DIR/brain_dump/dump_$today.md"
    if [[ ! -f "$f" ]]; then
        mkdir -p "$(dirname "$f")"
        printf -- '---\ndate: %s\ntags: [brain_dump]\n---\n\n# Brain Dump %s\n' "$today" "$today" > "$f"
    fi
    if [[ -n "$texto" ]]; then
        printf -- '- %s 🎙️ %s\n' "$(date +%H:%M)" "$texto" >> "$f"
    else
        printf -- '- %s 🎙️ (audio sin transcribir: %s)\n' "$(date +%H:%M)" "$wav_ref" >> "$f"
    fi
    notify "🎙️ Nota de voz guardada" "${texto:-$wav_ref}"
    echo "$f"
}

main() {
    local rec
    rec=$(pick_recorder)
    [[ -z "$rec" ]] && notify "🎙️" "Sin grabadora (pw-record/parec/arecord)" && exit 1

    mkdir -p "$AUDIO_DIR"
    local wav="$AUDIO_DIR/voice_$(date +%Y-%m-%d_%H%M%S).wav"
    notify "🎙️ Grabando" "$RECORD_SECS segundos... habla ahora"

    # Grabar en background y matar a los N segundos
    # shellcheck disable=SC2086
    $rec "$wav" &>/dev/null &
    local rec_pid=$!
    sleep "$RECORD_SECS"
    kill "$rec_pid" 2>/dev/null
    wait "$rec_pid" 2>/dev/null

    [[ ! -s "$wav" ]] && notify "🎙️" "Grabación vacía" && rm -f "$wav" && exit 1

    local texto=""
    texto=$(transcribe_file "$wav" 2>/dev/null || true)
    if [[ -n "$texto" ]]; then
        rm -f "$wav"
        voice_append "$texto" ""
    else
        voice_append "" "$wav"
    fi
}

# Solo main si se ejecuta directo (permite testear funciones con source)
if [[ "${BASH_SOURCE[0]:-${0}}" == "$0" ]]; then
    main "$@"
fi
