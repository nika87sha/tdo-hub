#!/usr/bin/env bash
# Tests de voice-note: silencio, alucinación, limpieza, append.
# No usa red ni graba: solo funciones puras + fixtures wav.

H="$TDO_HUB"
V="$TDO_TMP/vault"
fail=0

check() {
    local desc="$1" cond="$2"
    if eval "$cond"; then
        echo "  ✓ $desc"
    else
        echo "  ✗ $desc"
        fail=$((fail + 1))
    fi
}

mkdir -p "$V/00_inbox/brain_dump" "$V/00_inbox/voice"
cat > "$H/.env" <<EOF
HUB_ROOT="$H"
NOTES_DIR="$V"
INBOX_DIR="\$NOTES_DIR/00_inbox"
TODOS_DIR="\$NOTES_DIR/01_projects/General/todos"
STT_URL=""
EOF

# Fixture: wav de 1s silencio digital (ffmpeg si está; si no, skip)
SIL="$TDO_TMP/sil.wav"
SPEECH="$TDO_TMP/speech.wav"
HAVE_FF=0
if command -v ffmpeg &>/dev/null; then
    HAVE_FF=1
    ffmpeg -hide_banner -loglevel error -f lavfi -i anullsrc=r=16000:cl=mono -t 1 "$SIL" -y
    # 0.5s de tono como "habla" (no es voz real, pero peak > umbral)
    ffmpeg -hide_banner -loglevel error -f lavfi -i "sine=frequency=440:duration=0.5" -ar 16000 -ac 1 "$SPEECH" -y
fi

# shellcheck source=/dev/null
source "$H/scripts/capture/voice-note.sh"

# --- is_hallucination / clean_text ---
check "vacío es alucinación" 'is_hallucination ""'
check "solo 'no no no' es alucinación" 'is_hallucination "no no no no no"'
check "frase real NO es alucinación" '! is_hallucination "Preparar mochila para el salado"'
check "texto con relleno mixto se conserva" 'clean_text "no voy a ir al cajero" = "no voy a ir al cajero"'
check "alucinación limpia a vacío" 'clean_text "no no no" = ""'
check "espacios extra se colapsan" 'clean_text "  hola   mundo  " = "hola mundo"'

# --- audio_is_silent ---
if [[ "$HAVE_FF" -eq 1 ]]; then
    check "silencio digital detectado" 'audio_is_silent "$SIL"'
    check "audio con señal NO es silencio" '! audio_is_silent "$SPEECH"'
else
    echo "  - skip audio_is_silent (sin ffmpeg)"
fi

# --- voice_append ---
OUT=$(voice_append "Compra pan" "" 2>/dev/null)
TD=$(date +%Y-%m-%d)
BF="$V/00_inbox/brain_dump/dump_$TD.md"
check "brain dump creado" '[[ -f "$BF" ]]'
check "línea de texto agregada" 'grep -q "Compra pan" "$BF"'
check "wav_ref vacío no deja ruta" '! grep -q "audio sin transcribir" "$BF"'

OUT2=$(voice_append "" "$V/00_inbox/voice/x.wav" 2>/dev/null)
check "wav_ref presente cuando no hay texto" 'grep -q "audio sin transcribir" "$BF"'

# --- transcribe_file sin STT_URL y sin modelo local → falla limpio ---
export WHISPER_MODEL="$TDO_TMP/no_such_model.bin"
if [[ "$HAVE_FF" -eq 1 ]]; then
    if transcribe_file "$SPEECH" >/dev/null 2>&1; then
        echo "  ✗ transcribe_file debería fallar sin webhook ni modelo"
        fail=$((fail + 1))
    else
        echo "  ✓ transcribe_file falla limpio sin backend"
    fi
fi

echo "RESULT fail=$fail"
exit $((fail > 0))
