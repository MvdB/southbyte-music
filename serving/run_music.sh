#!/usr/bin/env bash
# Startet MiniMax-Music3 ueber SGLang-Omni auf dem DGX Spark.
#
# Muster wie southbyte-tts/serving/run_*.sh und southbyte-image/serving/run_image.sh:
# env-ueberschreibbar, Modell read-only aus ~/hf_models, vorhandenen Container
# entfernen, dann detached starten, fester Host-Port.
#
# Warum SGLang statt eines eigenen Adapters: MiniMax-Music3 wird vom Hersteller
# ueber SGLang-Omni bedient und bringt dort /v1/audio/speech nativ mit — dieselbe
# OpenAI-kompatible Schnittstelle, die auch die TTS-Adapter der Familie sprechen.
# Damit braucht die Evaluation nur eine andere URL. Gleiche Konstellation wie bei
# Voxtral-TTS, das ueber vLLM-Omni nativ bedient wird.
#
# Das Image muss vorher gebaut werden (serving/Dockerfile.music):
#   docker build -t southbyte-music:lokal -f serving/Dockerfile.music serving/
# Alternativ das veroeffentlichte nehmen:
#   IMAGE=ghcr.io/mvdb/southbyte-music:main ./run_music.sh
# Grund: sgl-omni steckt NICHT im Standard-Image. Geprueft am 2026-08-14 in
# lmsysorg/sglang:dev — dort gibt es nur sglang, sglang-kernel und
# sglang-router, weder das Kommando sgl-omni noch das Modul sgl_omni.
# SGLang-Omni ist ein eigenes Projekt (sgl-project/sglang-omni, PyPI
# sglang-omni), genau wie vllm-omni neben vllm steht.
#
# WICHTIG — Versionskopplung: sglang-omni v0.1.3 pinnt exakt sglang==0.5.16
# und torch==2.11.0. Deshalb ist die Basis lmsysorg/sglang:v0.5.16 (arm64
# vorhanden) und NICHT :dev, das sglang 0.0.0.dev1 mitbringt. Ein pip install
# in :dev wuerde sglang herunterstufen und die im Image gebauten Kernel
# zerschiessen. Dieselbe Falle wie bei vllm/vllm-omni in southbyte-tts, wo
# die Minor-Versionen zusammenpassen muessen.
#
# Fuer Kubernetes gibt es diesen Weg nicht — dort uebernimmt das Helm-Chart
# unter charts/southbyte-music, und das Modell holt ein initContainer in ein
# PersistentVolume statt es einzubinden. Dieses Skript bleibt der kurze Weg
# fuer eine einzelne Maschine.
set -euo pipefail

HF_MODELS_DIR="${HF_MODELS_DIR:-$HOME/hf_models}"
CONTAINER_NAME="${CONTAINER_NAME:-southbyte-music}"
HOST_PORT="${HOST_PORT:-8011}"
IMAGE="${IMAGE:-southbyte-music:lokal}"
MODEL_DIR="${MODEL_DIR:-MiniMaxAI--MiniMax-Music3}"
SPARK_PROFILES_DIR="${SPARK_PROFILES_DIR:-$HOME/southbyte/southbyte-spark-profiles}"
# Ueberschriebene Backbone-Config, eingeblendet ueber die read-only-Einbindung.
# Grund: sglang-omni normalisiert beim Start qwen_7B/qwen_7B/config.json und
# setzt model_type von "mixtral" auf "qwen3", damit HuggingFace eine
# Qwen3-Config aufloest. Dafuer schreibt es eine .bak und die Datei neu — im
# read-only eingebundenen Modellspeicher scheitert das mit
#   OSError: [Errno 30] Read-only file system
# Die Funktion kehrt aber sofort zurueck, wenn model_type bereits "qwen3" ist.
# Deshalb blenden wir eine bereits normalisierte Kopie ueber die eine Datei;
# der Modellspeicher bleibt unangetastet und weiterhin read-only. Die
# Alternative waere gewesen, ~/hf_models beschreibbar einzubinden — das
# widerspraeche der Konvention der ganzen Familie und liesse ein Werkzeug in
# den vom Sync verwalteten Speicher schreiben.
OVERRIDE_CONFIG="${OVERRIDE_CONFIG:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/overrides/qwen_7B_config.json}"

# Profil (Sampling, Laenge, Speicher) fuer dieses Modell laden, falls vorhanden.
PROFILE="${SPARK_PROFILES_DIR}/music/${MODEL_DIR}/music_profile.conf"
if [[ -f "${PROFILE}" ]]; then
  # shellcheck disable=SC1090
  source "${PROFILE}"
  echo "Profil geladen: ${PROFILE}"
else
  echo "Kein Profil unter ${PROFILE} — Standardwerte werden genutzt."
fi

if [[ ! -d "${HF_MODELS_DIR}/${MODEL_DIR}" ]]; then
  echo "FEHLER: Modellverzeichnis fehlt: ${HF_MODELS_DIR}/${MODEL_DIR}" >&2
  echo "        Der Sync holt es aus der LocalCache-Collection (~47 GB)." >&2
  exit 1
fi

if docker ps -a --format '{{.Names}}' | grep -qx "${CONTAINER_NAME}"; then
  echo "Container '${CONTAINER_NAME}' existiert -> wird entfernt."
  docker rm -f "${CONTAINER_NAME}" >/dev/null
fi

# Kein Kommando hinter dem Imagenamen: der Einstiegspunkt baut den Aufruf aus
# MODEL_PATH/SERVE_PORT/EXTRA_ARGS und wird dabei selbst PID 1 — nur so kommt
# ein SIGTERM beim Server an, statt in einer Shell zu versanden.
echo "Starte ${MODEL_DIR} auf Port ${HOST_PORT} (Image ${IMAGE}) ..."
docker run -d --name "${CONTAINER_NAME}" \
  --gpus all \
  --ipc=host \
  -p "${HOST_PORT}:8000" \
  -v "${HF_MODELS_DIR}:/hf_models:ro" \
  -v "${OVERRIDE_CONFIG}:/hf_models/${MODEL_DIR}/qwen_7B/qwen_7B/config.json:ro" \
  -e MODEL_PATH="/hf_models/${MODEL_DIR}" \
  -e EXTRA_ARGS="${PROFILE_EXTRA_ARGS:-}" \
  -e TRANSFORMERS_OFFLINE=1 \
  -e HF_HUB_OFFLINE=1 \
  ${PROFILE_DOCKER_ENV:+$(for kv in ${PROFILE_DOCKER_ENV}; do printf -- '-e %s ' "$kv"; done)} \
  "${IMAGE}"

cat <<EOF

Gestartet. Naechste Schritte:
  Logs  : docker logs -f ${CONTAINER_NAME}
  Test  : curl http://127.0.0.1:${HOST_PORT}/v1/models
  Musik : curl http://127.0.0.1:${HOST_PORT}/v1/audio/speech \\
            -H 'Content-Type: application/json' \\
            -d '{"model":"${MODEL_DIR}","input":"[Verse]\\nZeile eins\\n[Chorus]\\nRefrain","instructions":"Ruhiger Akustik-Pop, 90 BPM, warm","response_format":"wav","max_new_tokens":750}' \\
            -o lied.wav
EOF
