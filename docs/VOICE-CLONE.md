# 🎙️ Voce dinamica (TTS) — guida al voice clone

Questa è una **feature opzionale e disattivata di default**. Se attivata, le frasi
dell'Armadillo Clippy non vengono lette da clip audio statici ma **sintetizzate
dinamicamente** con una voce clonata sul *tuo* account [ElevenLabs](https://elevenlabs.io).
Vantaggio: puoi aggiungere frasi infinite senza avere il relativo file audio.

Senza configurazione, l'app resta **offline** e usa i clip statici come sempre.

---

## ⚠️ Avviso legale (leggi prima di tutto)

- Questo repository **non contiene né distribuisce alcuna voce, API key o `voice_id`.**
  Contiene solo lo *script* e l'*infrastruttura* per generarla.
- Clonare la voce di una **persona reale identificabile** (un attore, un doppiatore,
  una celebrità) **senza il suo consenso viola i Termini di Servizio di ElevenLabs**
  (Prohibited Use Policy) e può violare il diritto alla voce/immagine.
- Usa questa procedura **esclusivamente** con voci di cui hai diritto (la tua, o con
  consenso esplicito), per uso **strettamente personale, domestico e non commerciale**.
- Il voice clone risultante vive **solo sul tuo account ElevenLabs**. Non va
  distribuito né incluso nel repository.
- Vale la stessa [takedown policy](../README.md#-licenza-e-disclaimer) del progetto.

**Sei l'unico responsabile dell'uso che ne fai.**

---

## Prerequisiti

- Un account [ElevenLabs](https://elevenlabs.io) (anche free) con una **API key**.
- `bash` e `curl` (preinstallati su macOS). `jq` opzionale (parsing più robusto).
- Alcuni campioni audio della voce che vuoi clonare (vedi sotto).

---

## Passo 1 — Prepara i campioni audio

L'Instant Voice Clone (IVC) di ElevenLabs fa la **media** dei campioni che gli dai:
**pochi campioni puliti battono tanti campioni sporchi.** Linee guida:

- **Solo voce**: niente musica, niente effetti, niente altri parlanti nello stesso clip.
- **Una sola persona**: se un clip contiene anche un altro personaggio, scartalo —
  contamina il clone.
- **Volume uniforme** e **buon rapporto segnale/rumore**.
- **30–60 secondi totali** sono sufficienti per un buon IVC.

### Pulizia rapida con ffmpeg (opzionale ma consigliata)

Se i tuoi campioni hanno silenzi, code o volumi disomogenei, normalizzali:

```bash
# trim silenzi inizio/fine + loudness uniforme (-16 LUFS) + mono 44.1 kHz
ffmpeg -y -i "input.wav" \
  -af "silenceremove=start_periods=1:start_threshold=-40dB:start_silence=0.1:stop_periods=-1:stop_threshold=-40dB:stop_silence=0.3,loudnorm=I=-16:TP=-1.5:LRA=11,aresample=44100" \
  -ac 1 "cleaned/input.wav"
```

Per ispezionare la qualità prima di scegliere (durata, volume, rumore di fondo):

```bash
# volume medio/picco
ffmpeg -i clip.wav -af volumedetect -f null /dev/null 2>&1 | grep volume
# noise floor (più è basso/negativo, più è pulito tra i suoni)
ffmpeg -i clip.wav -af astats=metadata=1 -f null /dev/null 2>&1 | grep "Noise floor"
```

> **Nota**: i clip audio della serie sono ritagli da una sorgente compressa con
> sottofondo. Il clone catturerà bene il *timbro*, ma la resa "identica" ha un tetto
> con questo materiale. Per il massimo servirebbe audio pulito da studio.

---

## Passo 2 — Crea il clone

```bash
export ELEVENLABS_API_KEY=sk_...
./scripts/clone-voice.sh "Nome Voce" cleaned/*.wav
```

Lo script chiama `POST /v1/voices/add`, crea un Instant Voice Clone sul tuo account e
stampa il **`VOICE_ID`** generato. Annotalo.

---

## Passo 3 — Configura l'app

Due modi.

### A) Dal menu dell'app (consigliato)

Clicca l'armadillo nella menu bar → **"Impostazioni voce…"** → spunta *Abilita voce
dinamica (TTS)*, incolla **API key** e **`voice_id`**, salva.

### B) Scrivendo il file di configurazione

Crea `~/Library/Application Support/ArmadilloBar/tts.json`:

```json
{
  "enabled": true,
  "api_key": "sk_...",
  "voice_id": "IL_TUO_VOICE_ID",
  "model_id": "eleven_multilingual_v2",
  "stability": 0.3,
  "similarity_boost": 0.9,
  "style": 0.3
}
```

I campi `stability`, `similarity_boost`, `style` sono opzionali (default mostrati sopra).

---

## Tuning della voce (`voice_settings`)

Sono la leva più forte sulla somiglianza, più del modello stesso:

| Parametro          | Effetto                                                        | Consigliato |
|--------------------|----------------------------------------------------------------|-------------|
| `similarity_boost` | quanto aderisce ai campioni. Alto = più simile (ma più rumore) | `0.85–0.90` |
| `stability`        | basso = più espressivo/variabile, alto = più monotono          | `0.30–0.50` |
| `style`            | esagerazione dello stile del parlato                           | `0.0–0.3`   |

`model_id`: `eleven_multilingual_v2` è la scelta solida per l'italiano. Esistono anche
`eleven_turbo_v2_5` (più veloce) ed `eleven_v3` (più espressivo, alpha) — provali se
vuoi, cambiando il campo `model_id`.

---

## Come funziona a runtime

1. Quando l'Armadillo Clippy mostra una frase, l'app controlla `tts.json`.
2. Se TTS è attivo, genera l'audio via ElevenLabs e lo riproduce, sincronizzando
   l'animazione "parlante" dell'armadillo.
3. Ogni frase generata è messa in **cache su disco**
   (`~/Library/Application Support/ArmadilloBar/tts-cache/`): viene generata una sola
   volta, poi è riprodotta **offline**.
4. Se TTS è disattivo o la rete fallisce, l'app fa **fallback silenzioso** al solo
   balloon (e ai clip statici per gli shortcut).

La cache usa un hash di `voice_id + model_id + voice_settings + testo`: cambiando voce
o impostazioni, le frasi si rigenerano automaticamente.
