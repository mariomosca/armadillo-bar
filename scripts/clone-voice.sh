#!/usr/bin/env bash
#
# clone-voice.sh — Crea un Instant Voice Clone su ElevenLabs (uso PERSONALE).
#
# ──────────────────────────────────────────────────────────────────────────
#  ⚠️  AVVISO LEGALE / ToS — LEGGI PRIMA DI USARE
#
#  Questo script NON contiene né distribuisce alcuna voce. Si limita a chiamare
#  l'API di ElevenLabs col TUO account e i campioni audio che fornisci TU.
#
#  Clonare la voce di una persona reale identificabile (es. un attore, un
#  doppiatore, una celebrità) SENZA il suo consenso VIOLA i Termini di
#  Servizio di ElevenLabs (Prohibited Use Policy) e può violare il diritto
#  alla voce/immagine (in Italia tutelato). Usa questo script ESCLUSIVAMENTE
#  con voci di cui hai il diritto di usare (la tua, o con consenso esplicito),
#  per uso strettamente personale, domestico e NON commerciale. Il voice clone
#  resta sul TUO account; non va distribuito né incluso nel repository.
#
#  Tu sei l'unico responsabile dell'uso che ne fai. Coerentemente con la
#  takedown policy del progetto, nessun contenuto di terzi è incluso qui.
# ──────────────────────────────────────────────────────────────────────────
#
#  Uso:
#    export ELEVENLABS_API_KEY=sk_...
#    ./scripts/clone-voice.sh "Nome Voce" sample1.wav [sample2.wav ...]
#
#  Output: stampa il VOICE_ID creato. Mettilo poi nelle impostazioni dell'app
#  (menu → "Impostazioni voce…") oppure in:
#    ~/Library/Application Support/ArmadilloBar/tts.json
#
#  Requisiti: bash, curl. (Nessuna dipendenza Python.)
#
set -euo pipefail

API="https://api.elevenlabs.io/v1"

err() { printf '\033[31m%s\033[0m\n' "$*" >&2; }
info() { printf '\033[36m%s\033[0m\n' "$*"; }

# --- Validazione input ---------------------------------------------------
if [[ -z "${ELEVENLABS_API_KEY:-}" ]]; then
  err "ELEVENLABS_API_KEY non impostata."
  err "  export ELEVENLABS_API_KEY=sk_..."
  exit 1
fi

if [[ $# -lt 2 ]]; then
  err "Uso: $0 \"Nome Voce\" <sample1.wav> [sample2.wav ...]"
  err "Esempio: $0 \"Armadillo\" assets/clips/*.wav"
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  err "curl non trovato."
  exit 1
fi

NAME="$1"; shift
SAMPLES=("$@")

# Verifica esistenza file
FORM_FILES=()
for f in "${SAMPLES[@]}"; do
  if [[ ! -f "$f" ]]; then
    err "File non trovato: $f"
    exit 1
  fi
  FORM_FILES+=(-F "files=@${f};type=audio/wav")
done

info "Creazione voice clone \"$NAME\" da ${#SAMPLES[@]} campione/i…"
echo "(ricorda: usa solo voci di cui hai diritto — vedi avviso in testa allo script)"

# --- Chiamata API: Add Voice (Instant Voice Clone) -----------------------
# https://elevenlabs.io/docs/api-reference/voices/add
RESP="$(curl -sS -X POST "${API}/voices/add" \
  -H "xi-api-key: ${ELEVENLABS_API_KEY}" \
  -F "name=${NAME}" \
  -F "description=Personal use only — created via armadillo-bar clone-voice.sh" \
  "${FORM_FILES[@]}")"

# --- Parsing voice_id (jq se c'è, altrimenti grep) -----------------------
if command -v jq >/dev/null 2>&1; then
  VOICE_ID="$(printf '%s' "$RESP" | jq -r '.voice_id // empty')"
  ERRMSG="$(printf '%s' "$RESP" | jq -r '.detail.message // .detail // empty')"
else
  VOICE_ID="$(printf '%s' "$RESP" | grep -o '"voice_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')"
  ERRMSG=""
fi

if [[ -z "$VOICE_ID" ]]; then
  err "Creazione fallita. Risposta API:"
  err "$RESP"
  [[ -n "$ERRMSG" ]] && err "→ $ERRMSG"
  exit 1
fi

info "✓ Voice clone creato."
echo ""
echo "  VOICE_ID: ${VOICE_ID}"
echo ""
echo "Configura l'app con uno di questi metodi:"
echo "  1) App → menu → \"Impostazioni voce…\" → incolla API key + VOICE_ID"
echo "  2) Scrivi ~/Library/Application Support/ArmadilloBar/tts.json:"
echo ""
cat <<EOF
     {
       "enabled": true,
       "api_key": "${ELEVENLABS_API_KEY}",
       "voice_id": "${VOICE_ID}",
       "model_id": "eleven_multilingual_v2"
     }
EOF
