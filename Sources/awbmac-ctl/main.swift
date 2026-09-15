// awbmac-ctl -- Kommandozeilen-Gegenstueck zum Steuerkanal der Mac-App, nach
// dem Vorbild von app/bin/awb-ctl. Spricht den Unix-Socket an und gibt die
// Antwort als JSON aus.
//
//   awbmac-ctl [--socket <pfad>] <befehl> [argument]
//     ping                  Lebenszeichen (pid, kopflos, terminal-Bauart)
//     ui                    Zustand der Ansicht
//     klick <ziel>          sitzung:<id> | worker:<pane> | menue:<id>:<punkt> | beendete |
//                           sortierung:recent|folder|name | umschalter:orchestrator|worker |
//                           zahnrad | seitenleiste | maschine:<name> | maschine-laden:<name> | hinweis |
//                           zahnrad | seitenleiste | kachel:<pane> | kachel-doppel:<pane> |
//                           zoom:<pane> | fokus:<pane> | tab:<n> | chat:<id>
//     taste escape          Escape an die Kachelflaeche (aus dem Zoom zurueck)
//     menue                 die Menueleiste als Baum (Menues, Punkte, Kuerzel, aktiv/grau)
//     menue <id>            die Punkte des Kontextmenues einer Sitzung
//     hauptmenue <Menue> <Punkt>  einen Punkt der Menueleiste ausloesen (auch in Untermenues)
//     teiler seitenleiste|inspektor <breite>  einen Teiler ziehen; die Breite geht an den Kern
//     umbenennen <id> <name>  das offene Namensfeld (nach menue:<id>:umbenennen) beantworten
//     schuss <pfad>         Belegbild des Fensters als PNG
//     schirm [pane]         Text des Terminals mit der Tastatur, oder einer Kachel
//     latenz [n]            Tastendruck -> Zeichen, n Runden (Vorgabe 20)
//     auswahl               alles auswaehlen, Text der Auswahl
//     kopieren              Auswahl kopieren (kopflos: Merker statt Zwischenablage)
//     zoom                  Pane zoomen, Zeit bis zum Neuzeichnen
//     fenster <b>x<h>       Fenstergroesse setzen
//     einstellungen [seite]                 Einstellungsfenster bauen (nie zeigen), Seite waehlen, Auskunft
//     einstellungen-klick <kennung>         ein Bedienelement darin ausloesen (kein Mensch)
//     einstellungen-eingabe <kennung> <wert>  in ein Feld schreiben, wie getippt und verlassen
//     einstellungen-zustand <kennung>       ein Bedienelement lesen, ohne es anzufassen
//     einstellungen-schuss <seite|-> <pfad> Belegbild des Einstellungsfensters
//     einstellungen-fenster <b>x<h>         Groesse des Einstellungsfensters setzen; Antwort nennt
//                                           die Rahmen von Seitenleiste und Inhalt und jeden Ueberstand
//     sitzung                               Sitzungsfenster bauen (nie zeigen), Auskunft (2.7)
//     sitzung-klick <kennung>               ein Bedienelement darin ausloesen (kein Mensch)
//     sitzung-eingabe <kennung> <wert>      in ein Feld schreiben
//     sitzung-zustand <kennung>             ein Bedienelement lesen, ohne es anzufassen
//     sitzung-schuss <pfad> [rueckfrage]    Belegbild des Sitzungsfensters, mit `rueckfrage` samt letzter Rueckfrage
//     chat-tippen <text>    in das Feld der Chat-Buehne schreiben und abschicken (3.2)
//     chat-feld <text>      das Feld setzen (Marke ans Ende), Vervollstaendigung pruefen
//     chat-taste <name>     Enter | Shift+Enter | Escape | ArrowDown | ArrowUp | Tab an das Feld
//     chat-klick <knopf>    freigabe-ja | freigabe-nein | werkzeug:<id> | denken:<id> | modus | halt | neustart | senden | worker:<pane>
//     chat-text             der Verlauf der Buehne als Text
//     chat-zeiten [leeren]  die gemessenen Zeichenzeiten in ms
//     ordner [was] [wert]   Ordner-Blatt: Auskunft | klick <pfad> | zeigen <pfad> | suche <text> | jetzt (3.5/3.6)
//     aktivitaet [was] [pfad]  Aktivitaets-Blatt: Auskunft | lesen | klick <pfad> (3.5)
//     protokolle [was] [pfad]  Protokoll-Blatt: Auskunft | lesen | oeffnen <pfad> (3.6)
//     pfad [was] [...]      anklickbare Pfade (3.6): Auskunft | oeffnen <pfad[:zeile[:spalte]]>
//                           | chat <nr> | terminal <pane> <zeile> <spalte>
//     erscheinung hell|dunkel  Erscheinungsbild setzen (fuer Belegbilder)
//     barrierefreiheit [haupt]
//                           der Baum, den VoiceOver liest: jedes bedienbare Element mit
//                           Beschriftung. Ohne Angabe ueber JEDES stehende Fenster
//     editor-oeffnen <pfad> [text]          den Editor-Baustein bauen (nie zeigen) und eine Datei laden (3.3)
//     editor-cursor <zeile> [spalte]        Cursor setzen; Antwort nennt die gelesene Stelle
//     editor-suche <text>                   Treffer zaehlen, den ersten waehlen
//     editor-tippen [n]                     n Anschlaege, Zeit je Anschlag bis zum Layout
//     editor-kopieren <von> <bis>           Zeilen auswaehlen und kopieren (kopflos: Merker)
//     editor-schrift <groesse>              Schriftgroesse setzen
//     editor-schuss <pfad>                  Belegbild des Editorfensters
//     editor-messung <fassung> <pfad> [n] [wort]  der ganze Messlauf einer Fassung an einer Datei
//     quit                  App beenden
//     socket-path           aufgeloesten Socketpfad ausgeben
//
// Ohne --socket und ohne AWBMAC_CONTROL_SOCKET/XDG_RUNTIME_DIR verweigert das
// Werkzeug den Zugriff -- derselbe Grund wie bei awb-ctl (03.09.2026): ein
// Aufruf aus einem Worktree darf nicht still an eine laufende Fassung gehen.
import Foundation
import WerkbankProtokoll

func fehler(_ text: String) -> Never {
    FileHandle.standardError.write(Data((text + "\n").utf8))
    exit(2)
}

var args = Array(CommandLine.arguments.dropFirst())
var socket: String? = nil
if let i = args.firstIndex(of: "--socket"), i + 1 < args.count {
    socket = args[i + 1]
    args.removeSubrange(i...(i + 1))
} else if let i = args.firstIndex(where: { $0.hasPrefix("--socket=") }) {
    socket = String(args[i].dropFirst(9))
    args.remove(at: i)
}
let env = ProcessInfo.processInfo.environment
if socket == nil, env["AWBMAC_CONTROL_SOCKET"] == nil, env["XDG_RUNTIME_DIR"] == nil {
    fehler("awbmac-ctl: keine Adresse fuer den Steuerkanal. Setze AWBMAC_CONTROL_SOCKET oder gib --socket <pfad> an.")
}
let pfad = socket ?? vorgabeMacSteuerpfad(env)

guard let cmd = args.first else {
    fehler("Aufruf: awbmac-ctl [--socket <pfad>] <befehl> [argument]")
}
if cmd == "socket-path" {
    print(pfad)
    exit(0)
}
guard let anfrage = MacSteuerbefehl.ausArgumenten(args) else { fehler("kein Befehl") }

if pfad.utf8.count > 103 { fehler("awbmac-ctl: Socketpfad laenger als 103 Bytes (sun_path): \(pfad)") }
let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
var addr = sockaddr_un()
addr.sun_family = sa_family_t(AF_UNIX)
let bytes = Array(pfad.utf8)
withUnsafeMutablePointer(to: &addr.sun_path) { p in
    p.withMemoryRebound(to: CChar.self, capacity: 104) { c in
        for (i, b) in bytes.prefix(103).enumerated() { c[i] = CChar(bitPattern: b) }
        c[min(bytes.count, 103)] = 0
    }
}
let laenge = socklen_t(MemoryLayout<sa_family_t>.size + 1 + bytes.count + 1)
let r = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, laenge) } }
if r != 0 { fehler("awbmac-ctl: \(pfad): \(String(cString: strerror(errno)))") }

var tv = timeval(tv_sec: 30, tv_usec: 0)
setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
_ = anfrage.withUnsafeBytes { Darwin.send(fd, $0.baseAddress, $0.count, 0) }

var rahmen = Zeilenrahmen()
var puffer = [UInt8](repeating: 0, count: 65536)
while true {
    let n = read(fd, &puffer, puffer.count)
    if n <= 0 { fehler("awbmac-ctl: keine Antwort von \(pfad)") }
    let zeilen = rahmen.aufnehmen(Data(puffer[0..<n]))
    if let z = zeilen.first {
        print(String(decoding: z, as: UTF8.self))
        let ok = (try? JSONSerialization.jsonObject(with: z) as? [String: Any])?["ok"] as? Bool ?? false
        exit(ok ? 0 : 1)
    }
}
