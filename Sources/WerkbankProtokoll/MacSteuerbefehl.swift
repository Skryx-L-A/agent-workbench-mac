// Der Steuerkanal der Mac-App (`awbmac-ctl`), nach dem Vorbild von
// `app/bin/awb-ctl`: ein Unix-Socket, eine JSON-Zeile je Anfrage, eine
// JSON-Zeile je Antwort. Dieselbe Regel wie beim Kern: ein Werkzeug fuer
// Pruefungen, nicht fuer die Agenten in den Panes.
//
//   {"cmd":"ping"}                        Lebenszeichen
//   {"cmd":"ui"}                          Zustand der Ansicht, wie sie gezeichnet ist
//   {"cmd":"klick","ziel":"sitzung:<id>"} ein Bedienelement ausloesen
//        Ziele: sitzung:<id>, worker:<sitzung>/<pane>, workerliste:<pane>, pille,
//               (worker: nimmt auch die kurze Form <pane> -- zuerst die gewaehlte
//                Sitzung, dann die eine andere, die ihn traegt; mehrdeutig bricht ab,
//                weil Pane-Kennungen je tmux-Server gelten und Maschinen sich doppeln)
//               umschalter:orchestrator|worker, zahnrad, seitenleiste,
//               menue:<sitzung>:<punkt>, sortierung:<schluessel>, beendete,
//               kachel:<pane> (Kopfzeile: Fokus + Zoom), kachel-doppel:<pane>
//               (Doppelklick: zurueck), zoom:<pane> (Knopf), fokus:<pane>
//               (Klick ins Terminal), tab:<n> (Tab-Streifen)
//   {"cmd":"ziehen","was":"sitzung|projekt","gezogen":"<id|ordner>","ziel":"<id|ordner>"}
//        eine Zeile vor eine andere ihres Projekts, oder ein Projekt vor ein anderes
//   {"cmd":"schieben","was":"sitzung|projekt","kennung":"<id|ordner>","richtung":"hoch|runter"}
//        dasselbe um EINEN Platz -- der Weg des Kontextmenues
//   {"cmd":"schuss","pfad":"/…/bild.png"} Belegbild des Fensters schreiben
//   {"cmd":"schirm"}                      der Text des Terminals mit der Tastatur
//   {"cmd":"schirm","pane":"%3"}          der Text einer bestimmten Kachel
//   {"cmd":"taste","name":"escape"}       Escape an die Kachelflaeche (aus dem Zoom zurueck)
//   {"cmd":"latenz","n":20}               Tastendruck -> Zeichen, n Runden
//   {"cmd":"auswahl"}                     alles auswaehlen, Text der Auswahl
//   {"cmd":"kopieren"}                    die Auswahl kopieren (kopflos: in einen Merker)
//   {"cmd":"zoom"}                        den gezeigten Pane zoomen, Zeit bis zum Neuzeichnen
//   {"cmd":"fenster","breite":900,"hoehe":600}  Fenstergroesse setzen
//   {"cmd":"teiler","welcher":"seitenleiste","breite":300}  einen Teiler ziehen (seitenleiste|inspektor)
//   {"cmd":"menue"}                       die Menueleiste als Baum: Menues, Punkte, Kuerzel, aktiv/grau
//   {"cmd":"menue","sitzung":"<id>"}      die Punkte des Kontextmenues einer Sitzung
//   {"cmd":"hauptmenue","menue":"Darstellung","punkt":"Orchestrator"}  einen Punkt der Menueleiste ausloesen (wie sein Kuerzel)
//   {"cmd":"umbenennen","sitzung":"<id>","name":"neu"}  das offene Namensfeld beantworten
//   {"cmd":"entscheiden","pfad":"<antrag>","aktion":"approve|reject","grund":"…"}  Antrag entscheiden
//   {"cmd":"muster-entscheiden","schluessel":"<sha>","aktion":"…","grund":"…"}   Rueckfrage entscheiden
//   {"cmd":"grund","text":"…"}            Begruendungsfeld der Leiste setzen
//   {"cmd":"erscheinung","art":"hell|dunkel"}  Erscheinungsbild der App setzen (fuer Bilder)
//   {"cmd":"einstellungen","seite":"sitzung"}  das Einstellungsfenster bauen (nie zeigen), Seite waehlen, Auskunft
//   {"cmd":"einstellungen-klick","knopf":"<kennung>"}      ein Bedienelement darin ausloesen (ohne Menschen-Merkmal)
//   {"cmd":"einstellungen-eingabe","knopf":"<kennung>","wert":"…"}  in ein Feld schreiben, wie getippt und verlassen
//   {"cmd":"einstellungen-zustand","knopf":"<kennung>"}    ein Bedienelement lesen, ohne es anzufassen
//   {"cmd":"einstellungen-schuss","seite":"…","pfad":"/…/bild.png"}  Belegbild des Einstellungsfensters
//   {"cmd":"einstellungen-fenster","breite":820,"hoehe":560}  Groesse des Einstellungsfensters setzen, Rahmen zurueck
//        Ziele im Fuss (2.5): maschine:<name> (Popover auf/zu), maschine-laden:<name>
//               (Schalter umlegen), hinweis (den Hinweis wegraeumen)
//   {"cmd":"sitzung"}                     das Sitzungsfenster bauen (nie zeigen), Auskunft (2.7)
//   {"cmd":"sitzung-klick","knopf":"<kennung>"}     ein Bedienelement darin ausloesen (kein Mensch):
//        neu-start, fort-start, beenden-start, neu-fern-pruefen, zeile:<id>, filter:<zustand>,
//        rolle:<orchestrator|chat>, harness:<id>, modell:<id>, effort:<stufe>, kontext:<tokens>
//   {"cmd":"sitzung-eingabe","knopf":"<kennung>","wert":"…"}  in ein Feld schreiben:
//        neu-name, neu-fern-pfad, neu-maschine, such-feld, zustand-filter, neu-rolle, neu-harness, neu-modell, neu-effort, neu-kontext
//   {"cmd":"sitzung-zustand","knopf":"<kennung>"}   ein Bedienelement lesen, ohne es anzufassen
//   {"cmd":"sitzung-schuss","pfad":"/…/bild.png","art":"rueckfrage"}  Belegbild, mit `art` samt letzter Rueckfrage
//   {"cmd":"erststart"}                   den gefuehrten ersten Start bauen (nie zeigen), Auskunft (3.8)
//   {"cmd":"erststart-klick","knopf":"weiter|ueberspringen|wahl:<wert>|kontext:<tokens>"}
//   {"cmd":"erststart-schuss","pfad":"/…/bild.png"}  Belegbild des Blattes
//   {"cmd":"verbrauch"}                   die Verbrauchsseite bauen (nie zeigen), Auskunft (3.8)
//   {"cmd":"verbrauch-klick","knopf":"zeitraum:<tage>|harness:<id>|modell:<id>|vergleich|zuruecksetzen|neu"}
//   {"cmd":"verbrauch-schuss","pfad":"/…/bild.png"}  Belegbild der Seite
//   Der Editor-Baustein (3.3), in einem nie gezeigten Fenster:
//   {"cmd":"editor-oeffnen","pfad":"/…/datei.ts","fassung":"text"}  bauen und Datei laden (fassung: nur noch text, PLAN-EDITOR.md)
//   {"cmd":"editor-cursor","zeile":4321,"spalte":1}   Cursor auf Zeile:Spalte, Antwort nennt die gelesene Stelle
//   {"cmd":"editor-suche","text":"…"}                 alle Treffer zaehlen, den ersten waehlen
//   {"cmd":"editor-tippen","n":50}                    n Anschlaege, Zeit je Anschlag bis zum Layout (Median, p95)
//   {"cmd":"editor-kopieren","von":10,"bis":12}       Zeilen auswaehlen und kopieren (kopflos: Merker)
//   {"cmd":"editor-schrift","groesse":26}             Schriftgroesse setzen
//   {"cmd":"editor-schuss","pfad":"/…/bild.png"}      Belegbild des Editorfensters
//   {"cmd":"editor-messung","fassung":"text","pfad":"/…/datei.ts","n":50,"wort":"…"}  der ganze Messlauf einer Fassung
//   Das Editor-BLATT im Hauptfenster (3.4) -- Dateibaum, Tabs, Speichern, Auswahl:
//   {"cmd":"editor-blatt"}                            Auskunft (dieselbe wie ui.editorBlatt)
//   {"cmd":"editor-blatt","was":"oeffnen","pfad":"src/a.ts:12:3"}  Datei aus dem Baum, Zeile:Spalte freiwillig
//   {"cmd":"editor-blatt","was":"baum"}               den Dateibaum neu holen (awb:editor-list-files)
//   {"cmd":"editor-blatt","was":"filter","wert":"…"}  das Suchfeld des Baums setzen
//   {"cmd":"editor-blatt","was":"ordner","wert":"src"} einen Ordner auf-/zuklappen
//   {"cmd":"editor-blatt","was":"tab","nr":0}          einen Tab waehlen (-1 = Terminal)
//   {"cmd":"editor-blatt","was":"text","wert":"…"}     den Inhalt ersetzen, wie getippt (macht den Tab schmutzig)
//   {"cmd":"editor-blatt","was":"cursor","zeile":4,"spalte":3}  Cursor setzen
//   {"cmd":"editor-blatt","was":"auswahl","von":1,"bis":2}      ganze Zeilen markieren
//   {"cmd":"editor-blatt","was":"neuladen"}            die Datei erneut aus dem Kern lesen
//   {"cmd":"editor-einklappen","art":"auf|zu"}         ohne `art` umschalten
//   {"cmd":"editor-speichern"}                         awb:editor-write-file
//   {"cmd":"editor-schliessen","nr":0}                 ohne `nr` den gewaehlten Tab (Rueckfrage: AWB_RUECKFRAGE)
//   {"cmd":"editor-senden","pane":"%3"}                die Auswahl in einen Pane -- NIE in den Orchestrator-Pane
//   Die Chat-Buehne (3.2): dieselben Griffe wie `awb-ctl chat-*` der Electron-Fassung
//   {"cmd":"chat-tippen","text":"…"}      in das Feld schreiben und abschicken (Eingabe); meldet `geleert`
//   {"cmd":"chat-feld","text":"…"}        das Feld setzen, Marke ans Ende, Vervollstaendigung pruefen
//   {"cmd":"chat-taste","name":"Enter|Shift+Enter|Escape|ArrowDown|ArrowUp|Tab"}  eine Taste ans Feld
//   {"cmd":"chat-klick","knopf":"freigabe-ja|freigabe-nein|werkzeug:<id>|denken:<id>|modus|halt|neustart|senden|worker:<pane>"}
//   {"cmd":"chat-text"}                   der Verlauf als Text, wie er zu lesen ist
//   {"cmd":"chat-zeiten","leeren":"1"}    die gemessenen Zeichenzeiten (ms), mit `leeren` zuruecksetzen
//        Ziele in der Leiste: klick chat:<id> (unecht: nur bauen, wie ein Steuerkanal-Klick in Electron)
//   Die Blaetter des Inspektors (3.5/3.6) -- Ordner, Aktivitaet, Protokolle:
//   {"cmd":"ordner"}                                  Auskunft (dieselbe wie ui.ordner)
//   {"cmd":"ordner","was":"klick","wert":"/…/src"}    eine Baumzeile anklicken (Ordner auf/zu, Datei oeffnen)
//   {"cmd":"ordner","was":"zeigen","wert":"/…/src"}   bis zu diesem Ordner aufklappen
//   {"cmd":"ordner","was":"suche","wert":"…"}         die Inhaltssuche, sofort (ohne die 300-ms-Ruhe)
//   {"cmd":"ordner","was":"jetzt"}                    die sichtbaren Ordner sofort neu lesen
//   {"cmd":"aktivitaet"}                              Auskunft; "lesen": neu holen
//   {"cmd":"aktivitaet","was":"klick","wert":"/…/x.md"}  erster Klick: Inhalt; zweiter auf denselben: Diff bzw. Auftrag
//   {"cmd":"protokolle"}                              Auskunft; "lesen": Liste neu holen
//   {"cmd":"protokolle","was":"oeffnen","wert":"/…/log"}  ein Protokoll in den Editor
//   Anklickbare Pfade (3.6):
//   {"cmd":"pfad"}                                    Auskunft: Fundstellen im Gespraech, zuletzt geoeffnet
//   {"cmd":"pfad","was":"oeffnen","wert":"a/b.ts:12"} einen Pfad oeffnen, wie ein Klick
//   {"cmd":"pfad","was":"chat","nr":0}                die n-te Fundstelle im Gespraech anklicken
//   {"cmd":"pfad","was":"terminal","pane":"%3","zeile":4,"spalte":11}  ⌘-Klick auf eine Terminalzelle
//        Ziel im Inspektor: klick blatt:freigaben|ordner|aktivitaet|protokolle
//   Die Welten der Agents: der Tab „Agents" (seit agentsui Nr. 6) und das Fenster „Agents-Welten …":
//        Ziel in der Symbolleiste: klick modus:code|agents (der Umschalter Code | Agents)
//   {"cmd":"agents"}                                  Auskunft des Tabs (dieselbe wie ui.agents: Welten plus `tab`)
//   {"cmd":"agents","was":"zeigen|schliessen"}        auf Agents bzw. zurueck auf Code schalten
//   {"cmd":"agents","was":"…","wert":"…","arg":"…"}   sonst dieselben Befehle wie `welten`, am selben Zustand;
//        `fenster`, `schuss`, `sichtbaum`, `erscheinung` meinen hier das Hauptfenster
//   {"cmd":"figuren","was":"standbild","wert":"an|aus"}             Vorschau-Blatt der Figuren
//   {"cmd":"welten"}                                                  Fenster „Agents-Welten …": Auskunft
//   {"cmd":"welten","was":"zeigen|welt|waehlen|darstellung|klappen|reiter|blatt|gespraech|adressen|
//          senden|antworten|zuruecknehmen|pause|stoppen|bestaetigen|abbrechen|ticket|ticketfilter|
//          ticket-neu|inspektor|fenster|erscheinung|quittieren|rueckgabe|zurueckgeben|profil|
//          profil-feld|gedaechtnis|gedaechtnis-text|skill-abnehmen|skill-ablehnen|skill-zeigen|
//          anlegen|anlegen-feld|rechte|rechte-feld|welt-neu|welt-neu-auf|maschinen|umziehen|vergessen",
//          "wert":"…","arg":"…"}
//        `anlegen` kennt oeffnen|abbrechen|vorlage|vorschlag|pruefen|hausvorlage|sichern|
//          ansicht gespraech|formular|gespraech <text> [modell] [trocken]|vorschlagen (Anlege-Menue,
//          agentschat 15.09.2026) und rechte auf|zu (die Karte „Was der Agent darf" im Gespraech);
//          `anlegen-feld` setzt ein Formularfeld, dazu werkzeug <Name> an|aus und skill <name> an|aus
//          (Bash bleibt, Web nur mit Zugang, Modell und Fallback nur verfuegbare der Welt);
//          `rechte` kennt bearbeiten|abbrechen|sichern, `rechte-feld` werkzeug|skill <name> an|aus und
//          bash <muster\nmuster> (Rechte eines Agenten im Profil, `wb-agent rechte`); `vergessen <ordner>`
//          nimmt einen gemerkten Projektordner aus der Liste, nach `bestaetigen` (agentsform 16.09.2026);
//          `welt-neu-auf` legt eine Welt auf einer Agent-Maschine an, `umziehen` bringt sie dorthin
//          (fernwelten 15.09.2026).
//   {"cmd":"figuren-schuss","pfad":"/…/bild.png","dunkel":"1"}      Belegbild des Vorschau-Blatts
//   {"cmd":"quit"}                        sauber beenden
import Foundation

public struct MacSteuerbefehl: Sendable, Equatable {
    public let cmd: String
    public let text: [String: String]
    public let zahl: [String: Int]

    public init(cmd: String, text: [String: String] = [:], zahl: [String: Int] = [:]) {
        self.cmd = cmd; self.text = text; self.zahl = zahl
    }

    /// Liest eine Anfragezeile; `nil`, wenn sie kein Objekt mit `cmd` ist.
    public static func lesen(_ zeile: Data) -> MacSteuerbefehl? {
        guard let obj = try? JSONSerialization.jsonObject(with: zeile) as? [String: Any],
              let cmd = obj["cmd"] as? String else { return nil }
        var text: [String: String] = [:]
        var zahl: [String: Int] = [:]
        for (k, v) in obj where k != "cmd" {
            if let s = v as? String { text[k] = s }
            else if let n = v as? Int { zahl[k] = n }
            else if let d = v as? Double { zahl[k] = Int(d) }
        }
        return MacSteuerbefehl(cmd: cmd, text: text, zahl: zahl)
    }

    /// Baut die Anfragezeile aus Kommandozeilenargumenten, so wie `awbmac-ctl`
    /// sie bekommt: `klick sitzung:abc` -> {"cmd":"klick","ziel":"sitzung:abc"}.
    public static func ausArgumenten(_ args: [String]) -> Data? {
        guard let cmd = args.first else { return nil }
        var obj: [String: Any] = ["cmd": cmd]
        let rest = Array(args.dropFirst())
        switch cmd {
        case "klick": if let z = rest.first { obj["ziel"] = z }
        // ziehen <sitzung|projekt> <gezogen> <ziel>
        case "ziehen":
            if let w = rest.first { obj["was"] = w }
            if rest.count > 1 { obj["gezogen"] = rest[1] }
            if rest.count > 2 { obj["ziel"] = rest[2] }
        // schieben <sitzung|projekt> <kennung> <hoch|runter>
        case "schieben":
            if let w = rest.first { obj["was"] = w }
            if rest.count > 1 { obj["kennung"] = rest[1] }
            if rest.count > 2 { obj["richtung"] = rest[2] }
        case "schuss": if let p = rest.first { obj["pfad"] = p }
        case "schirm": if let p = rest.first { obj["pane"] = p }
        case "taste": if let n = rest.first { obj["name"] = n }
        case "latenz": if let n = rest.first, let z = Int(n) { obj["n"] = z }
        case "menue": if let z = rest.first { obj["sitzung"] = z }
        // tabfolge [schritte] -- wer nach jedem Tabulator die Tastatur hat.
        case "tabfolge":
            if let n = rest.first, let z = Int(n) { obj["schritte"] = z }
            if rest.count > 1 { obj["wie"] = rest[1] }
        case "hauptmenue":
            if let m = rest.first { obj["menue"] = m }
            if rest.count > 1 { obj["punkt"] = rest.dropFirst().joined(separator: " ") }
        case "umbenennen":
            if let z = rest.first { obj["sitzung"] = z }
            if rest.count > 1 { obj["name"] = rest.dropFirst().joined(separator: " ") }
        case "entscheiden", "muster-entscheiden":
            // entscheiden <pfad> approve|reject [grund …]; muster-entscheiden <schluessel> approve|reject [grund …]
            if let k = rest.first { obj[cmd == "entscheiden" ? "pfad" : "schluessel"] = k }
            if rest.count > 1 { obj["aktion"] = rest[1] }
            if rest.count > 2 { obj["grund"] = rest.dropFirst(2).joined(separator: " ") }
        case "grund":
            obj["text"] = rest.joined(separator: " ")
        case "erscheinung": if let a = rest.first { obj["art"] = a }
        // Ohne Angabe jedes stehende Fenster, mit `haupt` nur das Hauptfenster.
        case "barrierefreiheit":
            if let f = rest.first { obj["fenster"] = f }
            if rest.count > 1, let t = Int(rest[1]) { obj["tiefe"] = t }
        // Das Einstellungsfenster (2.6): einstellungen [seite]; einstellungen-klick <kennung>;
        // einstellungen-eingabe <kennung> <wert …>; einstellungen-zustand <kennung>;
        // einstellungen-schuss <seite|-> <pfad>
        case "einstellungen": if let z = rest.first { obj["seite"] = z }
        case "einstellungen-klick", "einstellungen-zustand": if let k = rest.first { obj["knopf"] = k }
        case "einstellungen-eingabe":
            if let k = rest.first { obj["knopf"] = k }
            if rest.count > 1 { obj["wert"] = rest.dropFirst().joined(separator: " ") }
        case "einstellungen-schuss":
            if let z = rest.first, z != "-" { obj["seite"] = z }
            if rest.count > 1 { obj["pfad"] = rest[1] }
        case "einstellungen-fenster":
            if let m = rest.first {
                let teile = m.split(separator: "x").compactMap { Int($0) }
                if teile.count == 2 { obj["breite"] = teile[0]; obj["hoehe"] = teile[1] }
            }
        // Das Sitzungsfenster (2.7): sitzung; sitzung-klick <kennung>; sitzung-eingabe <kennung> <wert …>;
        // sitzung-zustand <kennung>; sitzung-schuss <pfad> [rueckfrage]
        case "sitzung-klick", "sitzung-zustand": if let k = rest.first { obj["knopf"] = k }
        case "sitzung-eingabe":
            if let k = rest.first { obj["knopf"] = k }
            if rest.count > 1 { obj["wert"] = rest.dropFirst().joined(separator: " ") }
        case "sitzung-schuss":
            if let p = rest.first { obj["pfad"] = p }
            if rest.count > 1 { obj["art"] = rest[1] }
        // Der gefuehrte erste Start (3.8): erststart; erststart-klick <kennung>;
        // erststart-schuss <pfad>
        case "erststart-klick": if let k = rest.first { obj["knopf"] = k }
        case "erststart-schuss": if let p = rest.first { obj["pfad"] = p }
        // Die Verbrauchsseite (3.8): verbrauch; verbrauch-klick <kennung>; verbrauch-schuss <pfad>
        case "verbrauch-klick": if let k = rest.first { obj["knopf"] = k }
        case "verbrauch-schuss": if let p = rest.first { obj["pfad"] = p }
        // Der Editor (3.3): editor-oeffnen <pfad> [fassung]; editor-cursor <zeile> [spalte];
        // editor-suche <text …>; editor-tippen [n]; editor-kopieren <von> <bis>;
        // editor-schrift <groesse>; editor-schuss <pfad>; editor-messung <fassung> <pfad> [n] [wort]
        case "editor-oeffnen":
            if let p = rest.first { obj["pfad"] = p }
            if rest.count > 1 { obj["fassung"] = rest[1] }
        case "editor-cursor":
            if let z = rest.first, let n = Int(z) { obj["zeile"] = n }
            if rest.count > 1, let n = Int(rest[1]) { obj["spalte"] = n }
        case "editor-suche": obj["text"] = rest.joined(separator: " ")
        case "editor-tippen": if let n = rest.first, let z = Int(n) { obj["n"] = z }
        case "editor-kopieren":
            if let v = rest.first, let n = Int(v) { obj["von"] = n }
            if rest.count > 1, let n = Int(rest[1]) { obj["bis"] = n }
        case "editor-schrift": if let g = rest.first, let n = Int(g) { obj["groesse"] = n }
        case "editor-schuss": if let p = rest.first { obj["pfad"] = p }
        // Das Editor-Blatt (3.4): editor-blatt [was] [rest …]; editor-einklappen [auf|zu];
        // editor-speichern; editor-schliessen [nr]; editor-senden [pane]
        case "editor-blatt":
            if let w = rest.first { obj["was"] = w }
            switch rest.first ?? "" {
            case "oeffnen":
                if rest.count > 1 { obj["pfad"] = rest[1] }
            case "filter", "ordner":
                if rest.count > 1 { obj["wert"] = rest.dropFirst().joined(separator: " ") }
            case "text":
                if rest.count > 1 { obj["wert"] = rest.dropFirst().joined(separator: " ") }
            case "tab":
                if rest.count > 1, let n = Int(rest[1]) { obj["nr"] = n }
            case "cursor":
                if rest.count > 1, let n = Int(rest[1]) { obj["zeile"] = n }
                if rest.count > 2, let n = Int(rest[2]) { obj["spalte"] = n }
            case "auswahl":
                if rest.count > 1, let n = Int(rest[1]) { obj["von"] = n }
                if rest.count > 2, let n = Int(rest[2]) { obj["bis"] = n }
            default:
                break
            }
        // Die Blaetter des Inspektors (3.5/3.6): ordner [was] [wert …];
        // aktivitaet [was] [pfad]; protokolle [was] [pfad]; pfad [was] […]
        case "ordner", "aktivitaet", "protokolle":
            if let w = rest.first { obj["was"] = w }
            if rest.count > 1 { obj["wert"] = rest.dropFirst().joined(separator: " ") }
        // Die Welten, im Tab „Agents" oder im eigenen Fenster: agents|welten [was] [wert] [rest …] -- der Rest ist ein Satz.
        case "welten", "agents":
            if let w = rest.first { obj["was"] = w }
            if rest.count > 1 { obj["wert"] = rest[1] }
            if rest.count > 2 { obj["arg"] = rest[2...].joined(separator: " ") }
        // Das Vorschau-Blatt der Agentenfiguren: figuren [standbild an|aus]; figuren-schuss <pfad> [dunkel]
        case "figuren":
            if let w = rest.first { obj["was"] = w }
            if rest.count > 1 { obj["wert"] = rest[1] }
        case "figuren-schuss":
            if let p = rest.first { obj["pfad"] = p }
            if rest.count > 1, rest[1] == "dunkel" { obj["dunkel"] = "1" }
        case "pfad":
            if let w = rest.first { obj["was"] = w }
            switch rest.first ?? "" {
            case "terminal":
                if rest.count > 1 { obj["pane"] = rest[1] }
                if rest.count > 2, let n = Int(rest[2]) { obj["zeile"] = n }
                if rest.count > 3, let n = Int(rest[3]) { obj["spalte"] = n }
            case "chat":
                if rest.count > 1, let n = Int(rest[1]) { obj["nr"] = n }
            default:
                if rest.count > 1 { obj["wert"] = rest.dropFirst().joined(separator: " ") }
            }
        case "editor-einklappen": if let a = rest.first { obj["art"] = a }
        case "editor-schliessen": if let n = rest.first, let z = Int(n) { obj["nr"] = z }
        case "editor-senden": if let p = rest.first { obj["pane"] = p }
        case "editor-messung":
            if let f = rest.first { obj["fassung"] = f }
            if rest.count > 1 { obj["pfad"] = rest[1] }
            if rest.count > 2, let n = Int(rest[2]) { obj["n"] = n }
            if rest.count > 3 { obj["wort"] = rest[3] }
        // Die Chat-Buehne (3.2): chat-tippen <text …>; chat-feld <text …>; chat-taste <name>;
        // chat-klick <knopf>; chat-zeiten [leeren]
        case "chat-tippen", "chat-feld":
            obj["text"] = rest.joined(separator: " ")
        case "chat-taste": if let n = rest.first { obj["name"] = n }
        case "chat-klick": if let k = rest.first { obj["knopf"] = k }
        case "chat-zeiten": if rest.first == "leeren" { obj["leeren"] = "1" }
        case "fenster":
            if let m = rest.first {
                let teile = m.split(separator: "x").compactMap { Int($0) }
                if teile.count == 2 { obj["breite"] = teile[0]; obj["hoehe"] = teile[1] }
            }
        case "teiler":
            if let w = rest.first { obj["welcher"] = w }
            if rest.count > 1, let n = Int(rest[1]) { obj["breite"] = n }
        default:
            // Weitere Argumente reisen als arg1, arg2, … mit.
            for (i, a) in rest.enumerated() { obj["arg\(i + 1)"] = a }
        }
        var d = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
        d.append(0x0A)
        return d
    }
}

public enum MacSteuerantwort {
    public static func ok(_ felder: [String: Any] = [:]) -> Data {
        var obj: [String: Any] = ["ok": true]
        for (k, v) in felder { obj[k] = v }
        return zeile(obj)
    }

    public static func fehler(_ text: String) -> Data {
        zeile(["ok": false, "error": text])
    }

    private static func zeile(_ obj: [String: Any]) -> Data {
        guard JSONSerialization.isValidJSONObject(obj),
              var d = try? JSONSerialization.data(withJSONObject: obj) else {
            return Data("{\"ok\":false,\"error\":\"Antwort nicht als JSON darstellbar\"}\n".utf8)
        }
        d.append(0x0A)
        return d
    }
}

/// Der Vorgabepfad des Mac-Steuerkanals: dieselbe Ableitung wie beim Kern
/// (`defaultControlSocketPath` in config.ts), nur mit dem Namen `awbmac`.
public func vorgabeMacSteuerpfad(_ env: [String: String] = ProcessInfo.processInfo.environment) -> String {
    if let p = env["AWBMAC_CONTROL_SOCKET"], !p.isEmpty { return p }
    let basis = env["XDG_RUNTIME_DIR"].flatMap { $0.isEmpty ? nil : $0 } ?? NSTemporaryDirectory()
    return (basis as NSString).appendingPathComponent("awbmac-\(getuid()).sock")
}
