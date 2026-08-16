# Herkunft und Lizenz

Dieser Skill ist gemischt. Das eine Teil ist eigener Text, das andere unverändert
übernommen — und für den übernommenen Teil gilt eine fremde Lizenz.

## Was von wem ist

| Teil | Herkunft | Lizenz |
|---|---|---|
| `SKILL.md` | eigener Text; übernommen sind die Feldnamen des Caption-Schemas und die Reihenfolge der Abschnitte | MIT, wie das übrige Repository |
| `references/` — Router und 18 Familienindizes | **unverändert** aus `MiniMax-AI/MiniMax-Music3`, Verzeichnis `skills/music-caption-rewriter/`, Stand 15.08.2026, Commit `9456550` | MiniMax-Music3 Community License, siehe `LICENSE` |
| `templates/` — 1000 Referenz-Captions | ebenda, **unverändert** | ebenda |
| `LICENSE` | ebenda | — |

Nicht übernommen wurde `agents/openai.yaml` aus dem Upstream: eine Agenten-Definition
für ein fremdes Werkzeug, die hier nichts tut.

Ebenfalls nicht übernommen wurde die `SKILL.md` des Upstreams. Ihr Verfahren steckt in
unserer — Router, Rollenverteilung, Vorrangregeln —, ihre Messwerte hat sie nicht: Die
harten Grenzen dieses Modells auf dieser Maschine stehen nur bei uns.

## Was die Lizenz verlangt

Die Community License erlaubt Weitergabe ausdrücklich („copy, modify, merge, publish,
distribute, sublicense"). Daran hängen drei Pflichten, die uns betreffen:

1. **Der Hinweis reist mit.** `LICENSE` bleibt in diesem Verzeichnis, bei jeder Kopie
   und jedem Fork.
2. **Acceptable Use Policy** (Exhibit A in `LICENSE`) gilt für die Nutzung.
3. **Kommerziell**: Wer ein Produkt oder einen Dienst darauf aufbaut, muss
   „MiniMax-Music3" sichtbar in der Oberfläche nennen. Ab 20 Mio. USD Jahresumsatz
   braucht es zusätzlich eine schriftliche Freigabe von MiniMax
   (`api@minimax.io`). Für dieses Repository — ein Machbarkeitsnachweis ohne
   Anmeldung und ohne Abrechnung — greift keine der beiden Auflagen; wer es
   weiterverwendet, prüft das für sich selbst.

Dieselbe Lizenz liegt ohnehin schon über dem Modell und seinen Ausgaben. Sie kommt
hier also nicht neu ins Haus, sondern wird sichtbar.

## Aktualisieren

`references/` und `templates/` **nicht hier editieren.** Neu aus dem Upstream kopieren
und den Commit in der Tabelle oben nachziehen. Wer eine eigene Vorlage braucht, legt
sie außerhalb dieser beiden Verzeichnisse ab — sonst ist beim nächsten Abgleich nicht
mehr zu trennen, was fremd ist und was nicht.
