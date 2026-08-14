"""Importwache fuer das Musik-Image.

Prueft in einem Rutsch, was sonst erst beim Modellstart auffaellt:
Torch mit CUDA, sglang, sglang_omni, und vor allem, ob MiniMax-Music3
ueberhaupt in der Pipeline-Registry steht. Genau daran ist der erste
Startversuch am 2026-08-14 gescheitert:
    ValueError: Config for MiniMaxMusic3ForConditionalGeneration not found
    in the pipeline config registry
Die Registry wird per Introspektion gesucht, nicht ueber einen fest
verdrahteten Klassennamen — der aendert sich zwischen Versionen.
"""

import sys

import sglang

# Der Submodul-Import laedt sglang_omni mit — ein zusaetzliches
# "import sglang_omni" waere redundant (ruff F401).
import sglang_omni.models.registry as reg
import torch

print("torch", torch.__version__, "cuda", torch.version.cuda)
if not torch.version.cuda:
    sys.exit("FEHLER: Torch ohne CUDA-Unterstuetzung")
print("sglang", sglang.__version__)

archs: set[str] = set()
for name in dir(reg):
    obj = getattr(reg, name)
    configs = getattr(obj, "configs", None)
    if isinstance(configs, dict):
        archs |= set(configs)

if not archs:
    sys.exit("FEHLER: keine Registry mit Architekturen gefunden")

treffer = sorted(a for a in archs if "MiniMaxMusic3" in a)
if not treffer:
    sys.exit(
        "FEHLER: MiniMaxMusic3 fehlt in der Registry.\n"
        f"  bekannt sind {len(archs)} Architekturen, u.a.: {sorted(archs)[:8]}"
    )
print("MiniMaxMusic3 in der Registry:", treffer)
print(f"Registry kennt {len(archs)} Architekturen")
