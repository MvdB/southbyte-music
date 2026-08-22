#!/bin/sh
# Erzeugt config.js beim Start aus SOUTHBYTE_ENDPUNKT.
#
# Warum ueberhaupt: die im Image mitgelieferte config.js setzt den Endpunkt auf
# "" — das heisst "aus der Seitenadresse ableiten, Port 8011". Fuer eine Seite,
# die neben dem Musik-Server auf derselben Maschine liegt, stimmt das. Im
# Container stimmt es fast nie: dort steht der Reverse-Proxy davor, und der
# Browser soll /v1/ auf derselben Herkunft anfragen statt einen zweiten Port auf
# dem WebUI-Host, wo nichts horcht. Vorgabe ist deshalb "/".
#
# Bei readOnlyRootFilesystem ist das Ziel nicht beschreibbar — dann kommt die
# Datei aus einer ConfigMap und ist bereits richtig. Kein Fehler, nur ein Hinweis.
set -eu

ZIEL=/usr/share/nginx/html/config.js
ENDPUNKT="${SOUTHBYTE_ENDPUNKT:-/}"
VERSION="${SOUTHBYTE_VERSION:-}"
REVISION="${SOUTHBYTE_REVISION:-}"

# Schreibbarkeit wird PROBIERT, nicht erfragt. Ein Test mit -w prueft nur die
# Rechte-Bits: die Datei gehoert nginx, also meldet -w "ja" — auch auf einem
# read-only eingebundenen Dateisystem. Der erste Entwurf ist genau daran
# vorbeigelaufen und hat den Container beim Start umgebracht:
#   can't create /usr/share/nginx/html/config.js: Read-only file system
# und weil das Skript mit set -e laeuft, brach der nginx-Einstiegspunkt ab.
# Die Probe laeuft in einer Subshell. ':' ist ein POSIX-Sonderbuiltin, und bei
# einem fehlgeschlagenen Redirect auf ein Sonderbuiltin beendet sich die Shell —
# auch innerhalb von 'if !'. Genau daran ist der zweite Versuch gestorben: der
# Container brach beim Start ab, statt den Fall abzufangen.
if ! ( : > "${ZIEL}" ) 2>/dev/null; then
  echo "config.js ist nicht beschreibbar — bleibt wie eingebunden (erwartet bei readOnlyRootFilesystem)."
  exit 0
fi

cat > "${ZIEL}" <<EOF
// Beim Start aus SOUTHBYTE_ENDPUNKT erzeugt. Nicht von Hand aendern —
// die Datei wird bei jedem Neustart des Containers ueberschrieben.
window.SOUTHBYTE_MUSIC = {
  endpunkt: "${ENDPUNKT}",
  version: "${VERSION}",
  revision: "${REVISION}",
};
EOF
echo "config.js gesetzt: endpunkt=\"${ENDPUNKT}\" version=\"${VERSION}\""
