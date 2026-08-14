#!/usr/bin/env bash
# Einstiegspunkt des Serving-Images.
#
# Zweck ist nicht Bequemlichkeit, sondern zwei Dinge, die in Kubernetes zaehlen:
#
# 1. PID 1 und SIGTERM. Am Ende steht ein 'exec', damit sgl-omni selbst PID 1
#    wird und das SIGTERM des Kubelet direkt bekommt. Laeuft stattdessen eine
#    Shell als PID 1, verschluckt sie das Signal, der Pod laeuft in die
#    terminationGracePeriod und wird hart abgeschossen — mitten in einem Stueck,
#    an dem der Server unter Umstaenden schon zehn Minuten rechnet.
#
# 2. Konfiguration ueber Umgebungsvariablen statt ueber die Kommandozeile. Ein
#    Deployment setzt env, kein argv. Wer trotzdem argumentieren will, kann das:
#    ein Aufruf mit eigenem Kommando (z.B. 'bash') wird unveraendert
#    durchgereicht.
set -euo pipefail

MODEL_PATH="${MODEL_PATH:-/modelle/MiniMaxAI--MiniMax-Music3}"
SERVE_HOST="${SERVE_HOST:-0.0.0.0}"
SERVE_PORT="${SERVE_PORT:-8000}"

# Faellt ein eigenes Kommando rein, gilt das und sonst nichts. Erlaubt
# 'docker run … bash' zum Nachsehen, ohne den Regelbetrieb zu beruehren.
if [[ $# -gt 0 && "${1}" != --* ]]; then
  exec "$@"
fi

if [[ ! -d "${MODEL_PATH}" ]]; then
  echo "FEHLER: Modellverzeichnis fehlt: ${MODEL_PATH}" >&2
  echo "        In Kubernetes fuellt der initContainer es per hole_modell.sh." >&2
  echo "        Lokal muss der Modellspeicher eingebunden sein." >&2
  exit 1
fi

# Die Normalisierung der Backbone-Config macht sonst sglang-omni beim Start —
# und scheitert daran, wenn das Modell read-only eingebunden ist. Hier nur
# pruefen und deutlich sagen, was fehlt: reparieren gehoert in den
# initContainer, wo das Volume beschreibbar ist.
BACKBONE="${MODEL_PATH}/qwen_7B/qwen_7B/config.json"
if [[ -f "${BACKBONE}" ]] && ! grep -q '"model_type"[[:space:]]*:[[:space:]]*"qwen3"' "${BACKBONE}"; then
  echo "WARNUNG: ${BACKBONE} ist nicht normalisiert (model_type != qwen3)." >&2
  echo "         sglang-omni versucht das beim Start selbst und scheitert," >&2
  echo "         wenn das Volume read-only ist. hole_modell.sh erledigt es." >&2
fi

echo "Starte sgl-omni serve"
echo "  Modell : ${MODEL_PATH}"
echo "  Adresse: ${SERVE_HOST}:${SERVE_PORT}"
[[ -n "${EXTRA_ARGS:-}" ]] && echo "  Extra  : ${EXTRA_ARGS}"

# EXTRA_ARGS bewusst ungequotet: der Inhalt SOLL in einzelne Argumente
# zerfallen. Wer Werte mit Leerzeichen braucht, nimmt ein eigenes Kommando.
# shellcheck disable=SC2086
exec sgl-omni serve \
  --model-path "${MODEL_PATH}" \
  --host "${SERVE_HOST}" \
  --port "${SERVE_PORT}" \
  ${EXTRA_ARGS:-} "$@"
