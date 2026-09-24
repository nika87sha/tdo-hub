#!/usr/bin/env bash
# ==========================================================
# 🎙️ VOICE NOTE - Graba 5s, transcribe y guarda en brain dump
# Uso directo (SUPER+Alt+M) o desde hub.sh
# Grabación: pw-record (PipeWire) → parec → arecord.
# STT: webhook HTTP (STT_URL) si está definido;
# si no, whisper-cli local (ggml-base). Si ambos fallan,
# guarda el audio y deja la nota con su ruta.
# Silencio digital (peak < -50 dB) se descarta sin ensuciar
# el brain dump.
# ==========================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${0}}")" && pwd)"
source "$SCRIPT_DIR/../../core.sh"

RECORD_SECS="${RECORD_SECS:-5}"
AUDIO_DIR="${AUDIO_DIR:-$INBOX_DIR/voice}"
WHISPER_MODEL="${WHISPER_MODEL:-$HOME/.local/share/whisper.cpp/ggml-base.bin}"
# dBFS: habla ≈ -3, silencio digital ≈ -91. Umbral conservador.
SILENCE_DB="${SILENCE_DB:--50}"

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

# ¿El wav es silencio digital (micrófono no capturó nada)?
# Devuelve 0 (true) si es silencio. Si no hay ffmpeg, no puede
# determinarlo → devuelve 1 (no silencio) y deja pasar.
audio_is_silent() {
    local wav="$1"
    command -v ffmpeg &>/dev/null || return 1
    local max_vol
    max_vol=$(ffmpeg -hide_banner -i "$wav" -af volumedetect -f null - 2>&1 \
        | awk -F': ' '/max_volume/ {print $2; exit}')
    [[ -z "$max_vol" ]] && return 1
    awk -v m="$max_vol" -v t="$SILENCE_DB" 'BEGIN { exit !(m+0 < t+0) }'
}

# ¿El texto es solo relleno/alucinación de whisper en silencio?
is_hallucination() {
    local raw="$1"
    local cleaned
    cleaned=$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alpha:]áéíóúñü' ' ')
    cleaned=$(printf '%s' "$cleaned" | sed 's/^ *//; s/ *$//')
    [[ -z "$cleaned" ]] && return 0
    # si casi todo son tokens de relleno → alucinación
    local total=0 filler=0 tok
    for tok in $cleaned; do
        total=$((total + 1))
        case "$tok" in
            no|uh|um|ah|eh|mmm|mm|silencio|música|musica|susurro) filler=$((filler + 1)) ;;
        esac
    done
    [[ "$total" -eq 0 ]] && return 0
    # >80% relleno → basura
    [[ $((filler * 100 / total)) -ge 80 ]]
}

clean_text() {
    local raw="$1"
    local cleaned
    cleaned=$(printf '%s' "$raw" | tr -s '[:space:]' ' ' | sed 's/^ *//; s/ *$//')
    if is_hallucination "$cleaned"; then
        printf ''
    else
        printf '%s' "$cleaned"
    fi
}

transcribe_webhook() {
    local wav="$1"
    [[ -z "${STT_URL:-}" ]] && return 1
    command -v curl &>/dev/null || return 1
    local resp
    resp=$(timeout 60 curl -sS -F "file=@$wav" "$STT_URL" 2>/dev/null) || resp=""
    [[ -z "$resp" ]] && return 1
    local texto
    texto=$(printf '%s' "$resp" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("text",""))' 2>/dev/null) || texto=""
    texto=$(clean_text "$texto")
    [[ -n "$texto" ]] && { printf '%s' "$texto"; return 0; }
    return 1
}

transcribe_local() {
    local wav="$1"
    command -v whisper-cli &>/dev/null || return 1
    [[ -f "$WHISPER_MODEL" ]] || return 1
    local out
    out=$(timeout 120 whisper-cli -m "$WHISPER_MODEL" -l es -f "$wav" -nt 2>/dev/null) || return 1
    out=$(clean_text "$out")
    [[ -n "$out" ]] && { printf '%s' "$out"; return 0; }
    return 1
}

transcribe_file() {
    local wav="$1"
    transcribe_webhook "$wav" && return 0
    transcribe_local "$wav" && return 0
    return 1
}

voice_append() {
    local texto="$1" wav_ref="$2"
    local today
    today=$(date +%Y-%m-%d)
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
    local wav
    wav="$AUDIO_DIR/voice_$(date +%Y-%m-%d_%H%M%S).wav"
    notify "🎙️ Grabando" "$RECORD_SECS segundos... habla ahora"

    # shellcheck disable=SC2086
    $rec "$wav" &>/dev/null &
    local rec_pid=$!
    sleep "$RECORD_SECS"
    kill "$rec_pid" 2>/dev/null
    wait "$rec_pid" 2>/dev/null

    if [[ ! -s "$wav" ]]; then
        notify "🎙️" "Grabación vacía"
        rm -f "$wav"
        exit 1
    fi

    # Silencio digital → no ensuciar el brain dump, avisar y salir
    if audio_is_silent "$wav"; then
        notify "🎙️ Sin audio" "No detecté voz (silencio). Borré el wav."
        rm -f "$wav"
        exit 0
    fi

    local texto=""
    texto=$(transcribe_file "$wav" 2>/dev/null || true)
    texto=$(clean_text "$texto")

    if [[ -n "$texto" ]]; then
        rm -f "$wav"
        voice_append "$texto" ""
    else
        # No se transcribió: conservar wav para reintento manual
        voice_append "" "$wav"
    fi
}

# Solo main si se ejecuta directo (permite testear funciones con source)
if [[ "${BASH_SOURCE[0]:-${0}}" == "$0" ]]; then
    main "$@"
fi
