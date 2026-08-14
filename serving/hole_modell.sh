#!/usr/bin/env bash
# Holt MiniMax-Music3 in ein Volume — idempotent, fuer den initContainer.
#
# Das Modell gehoert NICHT ins Image. Es sind rund 54 GB; ein Image dieser
# Groesse zieht sich kein Cluster mehr sinnvoll auf einen Knoten, und bei jedem
# Neubau des Images waere es wieder dabei. In Kubernetes ist das Modell Daten,
# kein Code: es liegt in einem PersistentVolume, und dieses Skript fuellt es.
#
# Idempotent heisst hier zweistufig:
#   1. Liegt die Fertig-Marke, passiert gar nichts — kein Netzverkehr, der Pod
#      startet in Sekunden statt in Stunden. Das ist der Normalfall bei jedem
#      Neustart, jeder Skalierung, jedem Knotenwechsel.
#   2. Fehlt sie, laedt 'hf download' nach. Das ist selbst wiederaufnehmbar:
#      vorhandene Dateien werden anhand ihres Hashes uebersprungen, ein
#      abgebrochener Download setzt fort statt neu zu beginnen.
#
# Ausserdem wird hier die Backbone-Config normalisiert. Das macht sglang-omni
# sonst beim Start selbst — und scheitert daran, sobald das Modell read-only
# eingebunden ist. Im initContainer ist das Volume beschreibbar, hier ist also
# der richtige Ort dafuer, und der Server bleibt anschliessend ohne Schreibrecht.
set -euo pipefail

MODEL_REPO="${MODEL_REPO:-MiniMaxAI/MiniMax-Music3}"
MODEL_ROOT="${MODEL_ROOT:-/modelle}"
# Namenskonvention der ganzen Familie: <owner>--<model>, also die HF-Kennung
# mit '/' zu '--'. Damit passt derselbe Speicher zu allen anderen Stacks.
MODEL_DIR="${MODEL_DIR:-${MODEL_REPO//\//--}}"
ZIEL="${MODEL_ROOT}/${MODEL_DIR}"
MARKE="${ZIEL}/.southbyte-vollstaendig"

if [[ -f "${MARKE}" ]]; then
  echo "Modell bereits vollstaendig: ${ZIEL}"
  echo "  (Marke vom $(cat "${MARKE}"))"
  exit 0
fi

echo "Hole ${MODEL_REPO} nach ${ZIEL}"
echo "  Das sind rund 54 GB. Beim ersten Mal dauert das entsprechend;"
echo "  jeder weitere Start ueberspringt diesen Schritt."
mkdir -p "${ZIEL}"

# --max-workers gedeckelt: die Vorgabe oeffnet so viele parallele Verbindungen,
# dass kleine Cluster-Netze und NAS-Backends darunter einbrechen. Acht ist ein
# Kompromiss, der die Leitung fuellt, ohne sie zu verstopfen.
hf download "${MODEL_REPO}" \
  --local-dir "${ZIEL}" \
  --max-workers "${DOWNLOAD_WORKERS:-8}"

# ── Backbone-Config normalisieren ────────────────────────────────────────
# sglang-omni setzt model_type von "mixtral" auf "qwen3", damit HuggingFace
# eine Qwen3-Config aufloest. Die eingebaute Routine schreibt dafuer eine .bak
# und die Datei neu; die Funktion kehrt sofort zurueck, wenn der Wert schon
# stimmt. Genau das stellen wir hier her.
BACKBONE="${ZIEL}/qwen_7B/qwen_7B/config.json"
if [[ -f "${BACKBONE}" ]]; then
  python3 - "${BACKBONE}" <<'PY'
import json
import pathlib
import sys

pfad = pathlib.Path(sys.argv[1])
konfig = json.loads(pfad.read_text(encoding="utf-8"))
if konfig.get("model_type") == "qwen3":
    print(f"Backbone-Config bereits normalisiert: {pfad}")
else:
    vorher = konfig.get("model_type")
    konfig["model_type"] = "qwen3"
    pfad.write_text(json.dumps(konfig, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Backbone-Config normalisiert: model_type {vorher!r} -> 'qwen3'")
PY
else
  echo "WARNUNG: ${BACKBONE} nicht gefunden — Aufbau des Repos geaendert?" >&2
fi

# Marke ganz zum Schluss. Bricht der Download vorher ab, fehlt sie, und der
# naechste Start nimmt den Faden wieder auf, statt ein halbes Modell fuer
# vollstaendig zu halten.
date -u +"%Y-%m-%dT%H:%M:%SZ" > "${MARKE}"
echo "Fertig. $(du -sh "${ZIEL}" 2>/dev/null | cut -f1) in ${ZIEL}"
