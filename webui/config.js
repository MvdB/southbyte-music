// Betreiber-Konfiguration der Oberflaeche.
//
// Diese Datei ist der EINZIGE Ort, an dem der Endpunkt gesetzt wird. In der
// Oberflaeche selbst gibt es dafuer bewusst kein Eingabefeld: welcher Server
// die Musik erzeugt, ist eine Frage des Betriebs und nicht des Anwenders.
//
// endpunkt leer lassen — dann leitet die Seite ihn aus ihrer eigenen Adresse ab
// (gleicher Host, Port 8011). Das ist der Normalfall, wenn Oberflaeche und
// Server auf derselben Maschine laufen.
//
// Nur setzen, wenn der Musik-Server woanders steht, zum Beispiel:
//   endpunkt: "http://musik.intern:8011"
// version und revision fuellt der Container beim Start aus den Bauwerten
// des Image. Bleiben sie leer — etwa beim Ausliefern von der Platte —,
// zeigt die Fusszeile "unversioniert" statt einer Zahl, die niemand pflegt.
window.SOUTHBYTE_MUSIC = {
  endpunkt: "",
  version: "",
  revision: "",
};
