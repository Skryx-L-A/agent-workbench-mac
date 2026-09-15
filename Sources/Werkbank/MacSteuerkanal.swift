// Der Steuerkanal der Mac-App -- das Gegenstueck zu `awb-ctl` fuer die
// Oberflaeche, damit Shell-Suiten (shell/tests/test-mac-*.sh) sie kopflos
// pruefen koennen. Befehle und Antworten: WerkbankProtokoll/MacSteuerbefehl.swift.
//
// Er tippt NICHT in Panes: Tastendruecke fuer eine Pruefung gehen ueber den
// Steuerkanal des Kerns (`awb-ctl type`), wo `wb-pane-write darf` sie prueft.
// Die einzige Ausnahme ist `latenz`, das die Messmarken durch dieselbe Stelle
// schickt wie die Tastatur -- und deshalb nur in einer Wegwerf-Sitzung auf
// eigenem Socket laeuft, nie an Orchestrator des Nutzers (test-mac-*.sh).
import AppKit
import Foundation
import WerkbankProtokoll

@MainActor
final class MacSteuerkanal {
    private let pfad: String
    private let fenster: Fenster
    private let kern: KernVerbindung
    private let optionen: Laufoptionen
    private var server: Int32 = -1
    private var annahme: DispatchSourceRead?
    private var leser: [Int32: DispatchSourceRead] = [:]
    private var rahmen: [Int32: Zeilenrahmen] = [:]
    private let queue = DispatchQueue(label: "agent-workbench.werkbank.steuer")
    /// Der Editor-Baustein (3.3) in seinem nie gezeigten Fenster, gebaut beim ersten Bedarf.
    private var editor: EditorFenster?
    private var editorAuskunft: [String: Any] = ["gebaut": false]
    /// Dieselbe Zweiteilung fuer das Editor-BLATT im Hauptfenster (3.4).
    private var blattAuskunft: [String: Any] = ["gebaut": false]
    /// Die gewaehlte Fassung (mac/PLAN-EDITOR.md); `editor-oeffnen … <fassung>` weicht fuer eine Messung ab.
    static let editorVorgabe = EditorFassung.text

    init(pfad: String, fenster: Fenster, kern: KernVerbindung, optionen: Laufoptionen) {
        self.pfad = pfad
        self.fenster = fenster
        self.kern = kern
        self.optionen = optionen
    }

    func lauschen() throws {
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: pfad).deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = try UnixSocket.lauschen(pfad)
        server = fd
        annahme = UnixSocket.annehmer(fd: fd, queue: queue, neu: rueckrufNeu())
    }

    // DIE RUECKRUFE ENTSTEHEN NONISOLATED (gemessen 06.09.2026): ein Abschluss,
    // der in einer @MainActor-Methode entsteht und `self` faengt, wird als
    // `@MainActor @Sendable` gefolgert -- er laesst sich uebergeben, prueft beim
    // Aufruf auf der Warteschlange aber seine Isolation und faellt (SIGTRAP in
    // dispatch_assert_queue). In einer nonisolated Methode gebaut, traegt er
    // keine Isolation; der Sprung auf den Hauptakteur steht dann IM Abschluss.
    private nonisolated func rueckrufNeu() -> @Sendable (Int32) -> Void {
        { client in Task { @MainActor in self.verbindung(client) } }
    }

    private nonisolated func rueckrufDaten(_ fd: Int32) -> @Sendable (Data) -> Void {
        { d in Task { @MainActor in await self.daten(fd, d) } }
    }

    private nonisolated func rueckrufEnde(_ fd: Int32) -> @Sendable () -> Void {
        { Task { @MainActor in self.getrennt(fd) } }
    }

    func schliessen() {
        annahme?.cancel()
        annahme = nil
        for (_, l) in leser { l.cancel() }
        leser.removeAll()
        if server >= 0 { close(server); server = -1 }
        unlink(pfad)
    }

    private func verbindung(_ fd: Int32) {
        rahmen[fd] = Zeilenrahmen()
        leser[fd] = UnixSocket.leser(fd: fd, queue: queue, daten: rueckrufDaten(fd), ende: rueckrufEnde(fd))
    }

    private func getrennt(_ fd: Int32) {
        leser[fd] = nil
        rahmen[fd] = nil
    }

    private func daten(_ fd: Int32, _ d: Data) async {
        guard var r = rahmen[fd] else { return }
        let zeilen = r.aufnehmen(d)
        rahmen[fd] = r
        for z in zeilen {
            let antwort: Data
            if let befehl = MacSteuerbefehl.lesen(z) {
                antwort = await ausfuehren(befehl)
            } else {
                antwort = MacSteuerantwort.fehler("unlesbare Anfrage")
            }
            UnixSocket.schreiben(fd, antwort)
        }
    }

    private func ausfuehren(_ b: MacSteuerbefehl) async -> Data {
        switch b.cmd {
        case "ping":
            return MacSteuerantwort.ok(["pid": Int(getpid()), "kopflos": optionen.kopflos, "terminal": optionen.terminal.rawValue])

        case "ui":
            // Die Auskunft des Editors ist asynchron (Schnittstelle EditorBaustein); vorher lesen.
            editorAuskunft = await editor?.ansicht.auskunft() ?? ["gebaut": false]
            blattAuskunft = await fenster.editorZustand.auskunft()
            return MacSteuerantwort.ok(["ui": ui()])

        case "schirm":
            if let p = b.text["pane"], !p.isEmpty {
                guard let z = fenster.terminal.schirmZeilen(pane: p) else { return MacSteuerantwort.fehler("kein Terminal fuer Pane \(p) auf der Buehne") }
                return MacSteuerantwort.ok(["zeilen": z, "pane": p])
            }
            return MacSteuerantwort.ok(["zeilen": fenster.terminal.schirmZeilen(), "pane": fenster.terminal.gezeigterPane])

        case "taste":
            // Nur Escape an die Kachelflaeche (cancelOperation) -- der Kanal tippt nicht.
            guard b.text["name"] == "escape" else { return MacSteuerantwort.fehler("taste kennt nur escape") }
            fenster.terminal.cancelOperation(nil)
            return MacSteuerantwort.ok(["taste": "escape", "lage": fenster.terminal.lageArt])

        case "klick":
            guard let ziel = b.text["ziel"] else { return MacSteuerantwort.fehler("Feld ziel fehlt") }
            return klick(ziel)

        // DIE REIHENFOLGE VON HAND (Auftrag macleiste, 08.09.2026). Ein Zug mit
        // dem Zeiger laesst sich kopflos nicht ausloesen -- was hier laeuft,
        // ist dieselbe Handlung, die `dropDestination` in der Leiste aufruft.
        case "ziehen":
            guard let was = b.text["was"], let gezogen = b.text["gezogen"], let ziel = b.text["ziel"],
                  !gezogen.isEmpty, !ziel.isEmpty else {
                return MacSteuerantwort.fehler("ziehen <sitzung|projekt> <gezogen> <ziel> erwartet")
            }
            switch was {
            case "sitzung", "zeile":
                guard kern.modell.projekte.contains(where: { $0.zeilen.contains { $0.kennung == gezogen } }) else {
                    return MacSteuerantwort.fehler("Zeile nicht in der Leiste: \(gezogen)")
                }
                fenster.zeileZiehen(gezogen, auf: ziel)
            case "projekt":
                guard kern.modell.projekte.contains(where: { $0.dir == gezogen }) else {
                    return MacSteuerantwort.fehler("Projekt nicht in der Leiste: \(gezogen)")
                }
                fenster.projektZiehen(gezogen, auf: ziel)
            default:
                return MacSteuerantwort.fehler("unbekannte Sorte \(was) -- sitzung oder projekt")
            }
            return MacSteuerantwort.ok(["was": was, "gezogen": gezogen, "ziel": ziel])

        case "schieben":
            guard let was = b.text["was"], let kennung = b.text["kennung"], !kennung.isEmpty else {
                return MacSteuerantwort.fehler("schieben <sitzung|projekt> <kennung> <hoch|runter> erwartet")
            }
            let richtung = b.text["richtung"] ?? "hoch"
            guard richtung == "hoch" || richtung == "runter" else {
                return MacSteuerantwort.fehler("Richtung hoch oder runter erwartet, nicht \(richtung)")
            }
            switch was {
            case "sitzung", "zeile": fenster.zeileSchieben(kennung, hoch: richtung == "hoch")
            case "projekt": fenster.projektSchieben(kennung, hoch: richtung == "hoch")
            default: return MacSteuerantwort.fehler("unbekannte Sorte \(was) -- sitzung oder projekt")
            }
            return MacSteuerantwort.ok(["was": was, "kennung": kennung, "richtung": richtung])

        case "schuss":
            guard let pfad = b.text["pfad"], !pfad.isEmpty else { return MacSteuerantwort.fehler("Feld pfad fehlt") }
            do {
                let (bw, bh) = try fenster.schuss(pfad: pfad)
                return MacSteuerantwort.ok(["pfad": pfad, "breite": bw, "hoehe": bh])
            } catch {
                return MacSteuerantwort.fehler("Bild nicht geschrieben: \(error.localizedDescription)")
            }

        case "latenz":
            let n = b.zahl["n"] ?? 20
            let werte = await fenster.terminal.latenzMessen(runden: n)
            let gueltig = werte.filter { $0 >= 0 }.sorted()
            let median = gueltig.isEmpty ? -1 : gueltig[gueltig.count / 2]
            let p95 = gueltig.isEmpty ? -1 : gueltig[min(gueltig.count - 1, Int(Double(gueltig.count) * 0.95))]
            return MacSteuerantwort.ok(["werteMs": werte, "medianMs": median, "p95Ms": p95, "verloren": werte.count - gueltig.count])

        case "auswahl":
            let text = fenster.terminal.allesAuswaehlen() ?? ""
            return MacSteuerantwort.ok(["text": text, "zeichen": text.count])

        case "kopieren":
            _ = fenster.terminal.allesAuswaehlen()
            fenster.terminal.terminal.copy(self)
            return MacSteuerantwort.ok(["merker": fenster.terminal.zwischenablage.merker ?? "", "kopflos": optionen.kopflos])

        case "zoom":
            let ms = await fenster.terminal.zoomMessen()
            return MacSteuerantwort.ok(["ms": ms])

        case "fenster":
            guard let bw = b.zahl["breite"], let bh = b.zahl["hoehe"] else { return MacSteuerantwort.fehler("breite und hoehe fehlen") }
            var f = fenster.fenster.frame
            f.size = NSSize(width: bw, height: bh)
            fenster.fenster.setFrame(f, display: true)
            fenster.fenster.layoutIfNeeded()
            return MacSteuerantwort.ok(["breite": Int(fenster.fenster.frame.width), "hoehe": Int(fenster.fenster.frame.height),
                                        "cols": fenster.terminal.cols, "rows": fenster.terminal.rows])

        case "tabfolge":
            // DIE TAB-REIHENFOLGE, wie die Tastatur sie geht (abnahme.md,
            // Merkmal 11). `selectNextKeyView` ist derselbe Weg, den AppKit bei
            // der Tabulatortaste nimmt; gemeldet wird nach jedem Schritt, wer
            // die Tastatur hat. Ein Blatt vor dem Fenster (Agents) bekommt die
            // Schleife zuerst -- ein Sheet fuehrt seine eigene.
            let schritte = b.zahl["schritte"] ?? 12
            let ziel = fenster.fenster.attachedSheet ?? fenster.fenster
            // `neu` gibt die Tastatur erst zurueck ans Fenster. Ohne das misst
            // man die Schleife von dort, wo sie gerade steht -- und steht sie im
            // Terminal, bleibt sie dort: Tabulator gehoert im Terminal der
            // Anwendung darin (Vervollstaendigung), nicht der Oberflaeche.
            if b.text["wie"] == "neu" { ziel.makeFirstResponder(nil) }
            var stationen: [[String: Any]] = []
            for _ in 0..<max(1, min(schritte, 60)) {
                ziel.selectNextKeyView(nil)
                let r = ziel.firstResponder
                let e = r as? NSAccessibilityProtocol
                stationen.append([
                    "klasse": r.map { String(describing: type(of: $0)) } ?? "",
                    "rolle": e?.accessibilityRole()?.rawValue ?? "",
                    "label": e?.accessibilityLabel() ?? "",
                    "kennung": e?.accessibilityIdentifier() ?? "",
                ])
            }
            // Ob die Tastaturvollbedienung des Systems an ist, entscheidet, wer
            // ueberhaupt in der Schleife steht: ohne sie nimmt AppKit nur
            // Listen und Textflaechen auf, mit ihr auch jeden Knopf. Die
            // Einstellung gehoert dem System und laesst sich aus einer Pruefung
            // nicht setzen (`cfprefsd` folgt HOME nicht) -- deshalb steht sie
            // in der Antwort, damit eine Messung sagt, welchen Fall sie sah.
            return MacSteuerantwort.ok(["blatt": fenster.fenster.attachedSheet != nil,
                                        "vollbedienung": NSApp.isFullKeyboardAccessEnabled,
                                        "schritte": stationen.count, "stationen": stationen])

        case "menue":
            // Ohne Sitzung: die ganze Menueleiste als Baum (Auftrag 2.8) --
            // jede Handlung mit Kuerzel und Grauzustand, wie sie jetzt staende.
            guard let id = b.text["sitzung"], !id.isEmpty else {
                return MacSteuerantwort.ok(["menues": fenster.menueleisteAuskunft()])
            }
            if let c = kern.modell.chats.first(where: { $0.id == id }) {
                return MacSteuerantwort.ok(["sitzung": c.id, "name": c.name, "art": "chat", "state": c.laeuft ? "running" : "stopped",
                                            "punkte": MenuePunkt.chat.map { ["id": $0.id, "label": $0.titel, "rueckfrage": $0.rueckfrage] }])
            }
            guard let s = kern.modell.sessions.first(where: { $0.id == id }) else {
                return MacSteuerantwort.fehler("Sitzung nicht in der Leiste: \(id)")
            }
            return MacSteuerantwort.ok(["sitzung": s.id, "name": s.name, "art": "terminal", "state": s.state,
                                        "punkte": MenuePunkt.alle.map { ["id": $0.id, "label": $0.titel, "rueckfrage": $0.rueckfrage] }])

        case "hauptmenue":
            // Ein Punkt der Menueleiste, ausgeloest wie durch sein Kuerzel (⌘1, ⌘2 …):
            // derselbe Weg, den die Tastatur nimmt, samt validateMenuItem.
            guard let mTitel = b.text["menue"], let pTitel = b.text["punkt"] else { return MacSteuerantwort.fehler("menue und punkt fehlen") }
            guard let oben = NSApp.mainMenu?.items.first(where: { $0.title == mTitel })?.submenu else {
                return MacSteuerantwort.fehler("kein Menue \(mTitel)")
            }
            // Auch in Untermenues (Sortieren nach, Maschinen), die vorher aus
            // ihrem Delegaten gebaut werden.
            func suchen(_ m: NSMenu) -> (NSMenu, Int)? {
                m.delegate?.menuNeedsUpdate?(m)
                if let i = m.items.firstIndex(where: { $0.title == pTitel }) { return (m, i) }
                for it in m.items { if let sub = it.submenu, let t = suchen(sub) { return t } }
                return nil
            }
            guard let (menue, index) = suchen(oben) else {
                return MacSteuerantwort.fehler("kein Punkt \(pTitel) in \(mTitel)")
            }
            let punkt = menue.items[index]
            let geht = (punkt.target as? NSMenuItemValidation)?.validateMenuItem(punkt) ?? punkt.isEnabled
            let kuerzel = Fenster.kuerzelText(punkt)
            guard geht else { return MacSteuerantwort.ok(["ausgeloest": false, "grau": true, "kuerzel": punkt.keyEquivalent, "kuerzelText": kuerzel]) }
            menue.performActionForItem(at: index)
            return MacSteuerantwort.ok(["ausgeloest": true, "kuerzel": punkt.keyEquivalent, "kuerzelText": kuerzel])

        case "teiler":
            // Den Teiler ziehen wie der Mensch: die Breite geht an den Kern
            // (`sidebar-width` / `blatt-breite`), beschnitten auf die Grenzen der Spalte.
            guard let welcher = b.text["welcher"], welcher == "seitenleiste" || welcher == "inspektor" else {
                return MacSteuerantwort.fehler("teiler seitenleiste|inspektor <breite> erwartet")
            }
            guard let breite = b.zahl["breite"], breite > 0 else { return MacSteuerantwort.fehler("Feld breite fehlt") }
            if welcher == "seitenleiste" {
                guard fenster.seitenleisteSichtbar else { return MacSteuerantwort.fehler("die Seitenleiste ist eingeklappt") }
                fenster.teilerSetzen(seite: breite, melden: true)
            } else {
                guard fenster.freigabenBlattSichtbar else { return MacSteuerantwort.fehler("der Inspektor ist eingeklappt -- erst klick freigaben") }
                fenster.teilerSetzen(blatt: breite, melden: true)
            }
            return MacSteuerantwort.ok(["seitenleisteBreite": fenster.seitenleisteBreite, "inspektorBreite": fenster.inspektorBreite])

        case "umbenennen":
            // Beantwortet das offene Namensfeld -- denselben Weg wie das Sheet.
            guard let id = b.text["sitzung"] else { return MacSteuerantwort.fehler("Feld sitzung fehlt") }
            guard let offen = fenster.oberflaeche.umbenennen, offen.id == id else {
                return MacSteuerantwort.fehler("kein offenes Namensfeld fuer \(id) -- erst klick menue:\(id):umbenennen")
            }
            let name = b.text["name"] ?? ""
            let r = await fenster.umbenennenBestaetigen(id, name)
            return MacSteuerantwort.ok(["sitzung": id, "gelungen": r.ok, "meldung": r.meldung])

        case "entscheiden", "muster-entscheiden":
            // Ueber einen Antrag (pfad) oder eine Rueckfrage (schluessel)
            // entscheiden -- derselbe Weg wie die Knoepfe der Leiste und des
            // Blatts (Fenster.entscheiden), mit Begruendung. Ein Annehmen einer
            // Rueckfrage traegt hier KEINEN Menschen (`echt` = kopflos), der
            // Kern erteilt es dann nicht; Ablehnen darf jeder.
            let kennung = b.text[b.cmd == "entscheiden" ? "pfad" : "schluessel"] ?? ""
            guard !kennung.isEmpty else { return MacSteuerantwort.fehler("Feld \(b.cmd == "entscheiden" ? "pfad" : "schluessel") fehlt") }
            guard let aktion = b.text["aktion"], aktion == "approve" || aktion == "reject" else {
                return MacSteuerantwort.fehler("Feld aktion muss approve oder reject sein")
            }
            let offene = fenster.offeneFreigaben
            guard let f = offene.first(where: { b.cmd == "entscheiden" ? ($0.art == .antrag && $0.pfad == kennung) : ($0.art == .rueckfrage && $0.schluessel == kennung) }) else {
                return MacSteuerantwort.fehler("kein offener Eintrag \(kennung) -- schon entschieden oder noch nicht angekommen")
            }
            fenster.entscheiden(f, annehmen: aktion == "approve", grund: b.text["grund"] ?? "")
            return MacSteuerantwort.ok(["wer": f.wer, "aktion": aktion, "grund": b.text["grund"] ?? ""])

        case "grund":
            // Den Text des Begruendungsfelds der Leiste setzen (klappt es auf).
            fenster.freigabenZustand.begruendungOffen = true
            fenster.freigabenZustand.grund = b.text["text"] ?? ""
            return MacSteuerantwort.ok(["grund": fenster.freigabenZustand.grund])

        case "barrierefreiheit":
            // Der Baum, den AppKit an VoiceOver reicht, samt allem, was
            // bedienbar ist und keine Beschriftung traegt (Barrierefreiheit.swift).
            // Ohne Angabe: jedes Fenster, das gerade steht -- ein Blatt, das nur
            // ein Mensch oeffnet, wird sonst nie gemessen. `fenster: haupt`
            // fragt nur das Hauptfenster.
            let tiefe = b.zahl["tiefe"] ?? 12
            if b.text["fenster"] == "haupt" { return MacSteuerantwort.ok(Barrierefreiheit.auskunft(fenster.fenster, tiefe: tiefe)) }
            return MacSteuerantwort.ok(Barrierefreiheit.auskunftAlle(tiefe: tiefe))

        case "erscheinung":
            // Hell oder dunkel fuer die Bilder einer Suite -- die App folgt
            // sonst dem System. Gesetzt an der App, das Fenster erbt es.
            guard let art = b.text["art"], art == "hell" || art == "dunkel" else { return MacSteuerantwort.fehler("art muss hell oder dunkel sein") }
            // Von Hand heisst: die Einstellung des Kerns greift hier nicht mehr
            // (Fenster.erscheinungAnwenden) -- sonst zoege sie das Bild gleich
            // wieder zurueck.
            fenster.erscheinungVonHand = true
            NSApp.appearance = NSAppearance(named: art == "dunkel" ? .darkAqua : .aqua)
            fenster.fenster.layoutIfNeeded()
            return MacSteuerantwort.ok(["erscheinung": art, "dunkel": fenster.fenster.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua])

        case "editor-oeffnen":
            // Den Baustein bauen (nie zeigen) und eine Datei laden. Eine andere
            // Fassung als die gebaute ersetzt das Fenster (Messung).
            guard let pfad = b.text["pfad"], !pfad.isEmpty else { return MacSteuerantwort.fehler("Feld pfad fehlt") }
            let fassung = EditorFassung(rawValue: b.text["fassung"] ?? "") ?? editor?.ansicht.fassung ?? Self.editorVorgabe
            let e = editorBauen(fassung)
            do {
                let z = try await e.ansicht.oeffnen(pfad: pfad)
                var a = await e.ansicht.auskunft()
                a["lesbarMs"] = z.lesbarMs; a["gefaerbtMs"] = z.gefaerbtMs
                return MacSteuerantwort.ok(a)
            } catch {
                return MacSteuerantwort.fehler("Datei nicht geladen: \(error.localizedDescription)")
            }

        case "editor-cursor":
            guard let e = editor else { return MacSteuerantwort.fehler("kein Editor -- erst editor-oeffnen") }
            guard let zeile = b.zahl["zeile"], zeile >= 1 else { return MacSteuerantwort.fehler("Feld zeile fehlt") }
            await e.ansicht.baustein.cursorSetzen(zeile: zeile, spalte: max(1, b.zahl["spalte"] ?? 1))
            let c = await e.ansicht.baustein.cursor()
            return MacSteuerantwort.ok(["cursor": ["zeile": c.zeile, "spalte": c.spalte]])

        case "editor-suche":
            guard let e = editor else { return MacSteuerantwort.fehler("kein Editor -- erst editor-oeffnen") }
            guard let t = b.text["text"], !t.isEmpty else { return MacSteuerantwort.fehler("Feld text fehlt") }
            let s = await e.ansicht.baustein.suchen(t)
            let c = await e.ansicht.baustein.cursor()
            return MacSteuerantwort.ok(["treffer": s.treffer, "ms": s.ms, "cursor": ["zeile": c.zeile, "spalte": c.spalte]])

        case "editor-tippen":
            guard let e = editor else { return MacSteuerantwort.fehler("kein Editor -- erst editor-oeffnen") }
            let werte = await e.ansicht.baustein.tippen(runden: b.zahl["n"] ?? 50)
            let sortiert = werte.sorted()
            return MacSteuerantwort.ok(["werteMs": werte, "medianMs": sortiert.isEmpty ? -1 : sortiert[sortiert.count / 2],
                                        "p95Ms": sortiert.isEmpty ? -1 : sortiert[min(sortiert.count - 1, Int(Double(sortiert.count) * 0.95))]])

        case "editor-kopieren":
            guard let e = editor else { return MacSteuerantwort.fehler("kein Editor -- erst editor-oeffnen") }
            guard let von = b.zahl["von"], let bis = b.zahl["bis"], von >= 1, bis >= von else { return MacSteuerantwort.fehler("von und bis fehlen") }
            let t = await e.ansicht.baustein.kopieren(von: von, bis: bis)
            return MacSteuerantwort.ok(["text": t, "zeichen": t.count, "kopflos": optionen.kopflos])

        case "editor-schrift":
            guard let e = editor else { return MacSteuerantwort.fehler("kein Editor -- erst editor-oeffnen") }
            guard let g = b.zahl["groesse"], g > 0 else { return MacSteuerantwort.fehler("Feld groesse fehlt") }
            let ms = await e.ansicht.baustein.schrift(groesse: Double(g))
            return MacSteuerantwort.ok(["ms": ms, "schrift": await e.ansicht.baustein.schriftGroesse()])

        case "editor-schuss":
            guard let e = editor else { return MacSteuerantwort.fehler("kein Editor -- erst editor-oeffnen") }
            guard let pfad = b.text["pfad"], !pfad.isEmpty else { return MacSteuerantwort.fehler("Feld pfad fehlt") }
            do {
                let (bw, bh) = try await e.schuss(pfad: pfad)
                return MacSteuerantwort.ok(["pfad": pfad, "breite": bw, "hoehe": bh, "fassung": e.ansicht.fassung.rawValue])
            } catch {
                return MacSteuerantwort.fehler("Bild nicht geschrieben: \(error.localizedDescription)")
            }

        case "editor-messung":
            // Der ganze Messlauf einer Fassung an einer Datei (mac/messungen/editor/editor-messung.sh).
            guard let f = EditorFassung(rawValue: b.text["fassung"] ?? "") else { return MacSteuerantwort.fehler("fassung muss text sein (monaco: Commit f435811, PLAN-EDITOR.md)") }
            guard let pfad = b.text["pfad"], !pfad.isEmpty else { return MacSteuerantwort.fehler("Feld pfad fehlt") }
            let e = editorBauen(f, neu: true)
            let r = await EditorMessung.laufen(e, pfad: pfad, runden: b.zahl["n"] ?? 50, suchwort: b.text["wort"] ?? "function")
            return MacSteuerantwort.ok(r)

        // --- Das Editor-Blatt im Hauptfenster (Auftrag 3.4) --------------------
        case "editor-blatt":
            let z = fenster.editorZustand
            switch b.text["was"] ?? "" {
            case "oeffnen":
                guard let roh = b.text["pfad"], !roh.isEmpty else { return MacSteuerantwort.fehler("Feld pfad fehlt") }
                // `pfad[:zeile[:spalte]]` -- derselbe Griff wie der Pfad-Klick aus dem Gespraech.
                let teile = roh.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
                let pfad = teile[0]
                let zeile = teile.count > 1 ? Int(teile[1]) ?? 0 : 0
                let spalte = teile.count > 2 ? Int(teile[2]) ?? 1 : 1
                let ok = await z.oeffnen(pfad, zeile: zeile, spalte: spalte)
                return ok ? MacSteuerantwort.ok(await z.auskunft()) : MacSteuerantwort.fehler(z.notizSichtbar.isEmpty ? "nicht geoeffnet" : z.notizSichtbar)
            case "baum":
                _ = await z.dateienLaden()
                return MacSteuerantwort.ok(await z.auskunft())
            case "filter":
                z.filter = b.text["wert"] ?? ""
                return MacSteuerantwort.ok(await z.auskunft())
            case "ordner":
                guard let p = b.text["wert"], !p.isEmpty else { return MacSteuerantwort.fehler("Feld wert fehlt") }
                z.ordnerUmschalten(p)
                return MacSteuerantwort.ok(await z.auskunft())
            case "tab":
                guard let n = b.zahl["nr"] else { return MacSteuerantwort.fehler("Feld nr fehlt") }
                await z.aktivieren(n)
                return MacSteuerantwort.ok(await z.auskunft())
            case "text":
                guard await z.textSetzen(b.text["wert"] ?? "") else { return MacSteuerantwort.fehler("kein Dateitab gewaehlt") }
                return MacSteuerantwort.ok(await z.auskunft())
            case "cursor":
                guard let zeile = b.zahl["zeile"], zeile >= 1 else { return MacSteuerantwort.fehler("Feld zeile fehlt") }
                await z.cursorSetzen(zeile: zeile, spalte: max(1, b.zahl["spalte"] ?? 1))
                return MacSteuerantwort.ok(await z.auskunft())
            case "auswahl":
                guard let von = b.zahl["von"], let bis = b.zahl["bis"], von >= 1, bis >= von else { return MacSteuerantwort.fehler("von und bis fehlen") }
                guard await z.auswahlSetzen(von: von, bis: bis) else { return MacSteuerantwort.fehler("kein Dateitab gewaehlt") }
                return MacSteuerantwort.ok(await z.auskunft())
            case "neuladen":
                guard await z.neuLaden() else { return MacSteuerantwort.fehler(z.notizSichtbar.isEmpty ? "nicht neu geladen" : z.notizSichtbar) }
                return MacSteuerantwort.ok(await z.auskunft())
            case "":
                return MacSteuerantwort.ok(await z.auskunft())
            default:
                return MacSteuerantwort.fehler("editor-blatt kennt oeffnen|baum|filter|ordner|tab|text|cursor|auswahl|neuladen")
            }

        case "editor-einklappen":
            let z = fenster.editorZustand
            switch b.text["art"] ?? "" {
            case "zu": z.einklappen()
            case "auf": z.aufklappen()
            default: z.klappUmschalten()
            }
            return MacSteuerantwort.ok(await z.auskunft())

        case "editor-speichern":
            let z = fenster.editorZustand
            guard await z.speichern() else { return MacSteuerantwort.fehler(z.notizSichtbar.isEmpty ? "nicht gespeichert" : z.notizSichtbar) }
            return MacSteuerantwort.ok(await z.auskunft())

        case "editor-schliessen":
            let z = fenster.editorZustand
            let nr = b.zahl["nr"] ?? z.aktiv
            guard await z.schliessen(nr) else { return MacSteuerantwort.fehler("Tab \(nr) nicht geschlossen (Rueckfrage verneint oder kein Tab)") }
            return MacSteuerantwort.ok(await z.auskunft())

        case "editor-senden":
            // DER KANAL SCHREIBT NICHT IN EINEN ORCHESTRATOR-PANE (2026-08-06):
            // `echt` ist nur wahr, wenn ein Mensch im Fenster gedrueckt hat --
            // hier also nie. Ein Worker-Pane nimmt weiter alles an (Regel 1 in
            // wb-pane-write), und genau daran misst die Suite den Weg.
            let r = await fenster.editorZustand.auswahlSenden(pane: b.text["pane"] ?? "", echt: false)
            guard r.ok else { return MacSteuerantwort.fehler(r.meldung) }
            return MacSteuerantwort.ok(["pane": r.pane, "zeichen": r.text.count, "text": r.text])

        // --- Die Welten: der Tab „Agents" und das Fenster „Agents-Welten …" -----------
        // Dieselben Wege wie die Knoepfe; eine Handlung geht mit `echt: false`
        // an den Kern und schreibt deshalb als `cli-operator`. Beide Befehle
        // bedienen DENSELBEN Zustand (Fenster.weltenZustand); sie unterscheiden
        // sich nur darin, welches Fenster `zeigen`, `schliessen`, `fenster`,
        // `schuss`, `sichtbaum` und `erscheinung` meinen und welche Auskunft
        // zurueckkommt: `agents` den Tab im Hauptfenster (seit Auftrag agentsui
        // Nr. 6), `welten` das eigene Fenster.
        case "welten", "agents":
            let tab = b.cmd == "agents"
            let z = fenster.weltenZustand
            let wf = tab ? nil : fenster.weltenBauen()
            let ziel = wf?.fenster ?? fenster.fenster
            let auskunft = {
                tab ? MacSteuerantwort.ok(["agents": self.fenster.agentsAuskunft()])
                    : MacSteuerantwort.ok(["welten": z.auskunft(kern: self.kern, sichtbar: wf?.sichtbar ?? false)])
            }
            let was = b.text["was"] ?? ""
            let wert = b.text["wert"] ?? ""
            let arg = b.text["arg"] ?? ""
            let befehl = tab ? "agents" : "welten"
            switch was {
            case "": return auskunft()
            case "zeigen":
                if let wf {
                    wf.zeigen()
                } else {
                    fenster.modusSetzen(.agents)
                    // Eine Sichtpruefung legt das Hauptfenster HINTER alle anderen, wie `WeltenFenster.zeigen`
                    // (regeln/tests-und-eingriffe.md); das Belegbild zeichnet es auch verdeckt.
                    if !optionen.kopflos, optionen.ohneFokus { fenster.fenster.orderBack(nil) }
                }
                return auskunft()
            case "schliessen":
                if let wf { wf.fenster.performClose(nil) } else { fenster.modusSetzen(.code) }
                return auskunft()
            case "fenster":
                let teile = wert.split(separator: "x").compactMap { Int($0) }
                guard teile.count == 2 else { return MacSteuerantwort.fehler("\(befehl) fenster <breite>x<hoehe>") }
                var f = ziel.frame
                f.size = NSSize(width: teile[0], height: teile[1])
                ziel.setFrame(f, display: true)
                ziel.layoutIfNeeded()
                return MacSteuerantwort.ok(["breite": Int(ziel.frame.width), "hoehe": Int(ziel.frame.height), "fenster": ziel.windowNumber])
            case "sichtbaum":
                return MacSteuerantwort.ok(["baum": Glasbeleg.sichtbaum(ziel, tiefe: Int(wert) ?? 12)])
            case "schuss":
                guard !wert.isEmpty else { return MacSteuerantwort.fehler("\(befehl) schuss <pfad>") }
                do {
                    let s = try Glasbeleg.schuss(ziel, pfad: wert)
                    return MacSteuerantwort.ok(["pfad": wert, "breite": s.breite, "hoehe": s.hoehe, "glasflaechen": s.glas])
                } catch {
                    return MacSteuerantwort.fehler("Bild nicht geschrieben: \(error.localizedDescription)")
                }
            case "erscheinung":
                guard wert == "hell" || wert == "dunkel" else { return MacSteuerantwort.fehler("\(befehl) erscheinung hell|dunkel") }
                let neu = NSAppearance(named: wert == "dunkel" ? .darkAqua : .aqua)
                if tab {
                    // Wie `erscheinung` am Hauptfenster: von Hand, damit die Einstellung des Kerns es nicht zurueckzieht.
                    fenster.erscheinungVonHand = true
                    fenster.erscheinungErzwingen(neu)
                    fenster.fenster.layoutIfNeeded()
                } else {
                    ziel.appearance = neu
                }
                return auskunft()
            case "darstellung":
                guard let d = WeltenZustand.Darstellung(rawValue: wert) else { return MacSteuerantwort.fehler("\(befehl) darstellung baum|liste") }
                z.darstellung = d
                return auskunft()
            case "reiter":
                guard let r = WeltenZustand.Reiter(rawValue: wert) else { return MacSteuerantwort.fehler("\(befehl) reiter chat|tickets") }
                z.reiter = r
                return auskunft()
            case "blatt":
                guard let bl = WeltenZustand.Blatt(rawValue: wert) else { return MacSteuerantwort.fehler("\(befehl) blatt profil|protokoll|gedaechtnis|skills") }
                z.blatt = bl
                return auskunft()
            case "inspektor": z.inspektorOffen = wert != "aus"; return auskunft()
            case "abbrechen": z.rueckfrage = nil; return auskunft()
            case "welt-neu":
                // agents welt-neu global | agents welt-neu <ordner> [name] -- derselbe Weg wie das Menue
                // der Welten und die Einladung, nur mit dem Ordner als Text statt des Dialogs.
                guard !wert.isEmpty else { return MacSteuerantwort.fehler("\(befehl) welt-neu global|<projektordner> [name]") }
                if wert == "global" {
                    await z.weltAnlegen(art: "global", echt: false)
                } else {
                    await z.weltAnlegen(art: "projekt", ordner: wert, name: arg, echt: false)
                }
                return auskunft()
            case "welt-neu-auf":
                // agents welt-neu-auf <maschine> global|<projektordner> -- wie das Menue mit der Wahl der Maschine (Auftrag fernwelten).
                guard !wert.isEmpty, !arg.isEmpty else { return MacSteuerantwort.fehler("\(befehl) welt-neu-auf <maschine> global|<projektordner>") }
                if arg == "global" {
                    await z.weltAnlegen(art: "global", maschine: wert, echt: false)
                } else {
                    await z.weltAnlegen(art: "projekt", ordner: arg, maschine: wert, echt: false)
                }
                return auskunft()
            case "maschinen":
                // agents maschinen -- jede Agent-Maschine einmal fragen; die Auskunft traegt danach ihren Stand.
                _ = await z.maschinenPruefen(echt: false)
                return auskunft()
            default: break
            }
            let weltBefehle = ["welt", "waehlen", "klappen", "gespraech", "adressen", "senden", "antworten", "zuruecknehmen", "pause", "stoppen", "umziehen",
                               "bestaetigen", "ticket", "ticketfilter", "ticket-neu", "quittieren", "rueckgabe", "zurueckgeben", "profil",
                               "profil-feld", "gedaechtnis", "gedaechtnis-text", "anlegen", "anlegen-feld", "skill-abnehmen", "skill-ablehnen", "skill-zeigen"]
            guard weltBefehle.contains(was) else {
                return MacSteuerantwort.fehler("\(befehl) kennt zeigen|schliessen|fenster|schuss|sichtbaum|erscheinung|darstellung|reiter|blatt|inspektor|abbrechen|welt-neu|welt-neu-auf|maschinen|\(weltBefehle.joined(separator: "|"))")
            }
            guard let n = kern.welten, let w = z.welt(n) else { return MacSteuerantwort.fehler("noch keine Welt vom Kern") }
            switch was {
            case "welt":
                guard let ziel = n.welten.first(where: { $0.pfad == wert || $0.name == wert }) else { return MacSteuerantwort.fehler("keine Welt \(wert)") }
                z.weltWaehlen(ziel.pfad, n, echt: false)
            case "waehlen":
                if wert == "kanal" { z.waehlen(WeltenZustand.kanal, w, echt: false) }
                else if wert == "uebersicht" { z.waehlen(WeltenZustand.uebersicht, w, echt: false) }
                else if w.agent(wert) != nil { z.waehlen("agent:\(wert)", w, echt: false) }
                else { return MacSteuerantwort.fehler("kein Agent \(wert) in \(w.name)") }
            case "klappen":
                guard w.teams.contains(where: { $0.name == wert }) else { return MacSteuerantwort.fehler("kein Team \(wert)") }
                z.umklappen(wert)
            case "gespraech":
                guard wert == WeltenZustand.einzel || w.agent(z.agentId)?.direktchats.contains(wert) == true else {
                    return MacSteuerantwort.fehler("welten gespraech einzel|<direktchat des gewaehlten Agenten>")
                }
                z.gespraech = wert
                z.gesehen(w, echt: false)
            case "adressen":
                // Adressfeld und Senden gehoeren zum Kanal; aus der Uebersicht heraus meint der Steuerkanal ihn.
                if z.auswahl == WeltenZustand.uebersicht { z.waehlen(WeltenZustand.kanal, w, echt: false) }
                z.adressfeld = [wert, arg].filter { !$0.isEmpty }.joined(separator: " ")
            case "senden":
                if z.auswahl == WeltenZustand.uebersicht { z.waehlen(WeltenZustand.kanal, w, echt: false) }
                z.entwuerfe[z.gespraechSchluessel()] = [wert, arg].filter { !$0.isEmpty }.joined(separator: " ")
                await z.senden(w, echt: false)
            case "antworten":
                guard w.frage(wert) != nil else { return MacSteuerantwort.fehler("keine Frage \(wert)") }
                await z.antworten(w, frage: wert, text: arg, echt: false)
            case "zuruecknehmen":
                guard w.frage(wert) != nil else { return MacSteuerantwort.fehler("keine Frage \(wert)") }
                await z.zuruecknehmen(w, frage: wert, echt: false)
            case "pause":
                guard wert == "an" || wert == "aus" else { return MacSteuerantwort.fehler("welten pause an|aus [agent]") }
                await z.schalten(w, agent: arg.isEmpty ? nil : arg, laeuft: wert == "aus", echt: false)
            case "stoppen":
                await z.stoppen(w, agent: wert.isEmpty ? nil : wert, echt: false)
            case "umziehen":
                // agents umziehen <maschine> [trocken] -- ohne trocken prueft der Kern und fragt zurueck; `bestaetigen` zieht um.
                guard !wert.isEmpty else { return MacSteuerantwort.fehler("\(befehl) umziehen <maschine> [trocken]") }
                await z.umziehen(w, nach: wert, trocken: arg == "trocken", echt: false)
            case "bestaetigen":
                guard z.rueckfrage != nil else { return MacSteuerantwort.fehler("keine offene Rueckfrage") }
                await z.bestaetigen()
            case "ticket":
                if z.auswahl == WeltenZustand.uebersicht { z.waehlen(WeltenZustand.kanal, w, echt: false) }
                z.reiter = .tickets
                z.ticketAuswahl = wert.isEmpty ? nil : wert
            case "ticketfilter":
                z.ticketFilter = wert.isEmpty ? "offen" : wert
            // --- Auftrag Nr. 2: Quittung, Rueckgabe, Profil, Gedaechtnis -------------
            case "quittieren":
                guard !wert.isEmpty else { return MacSteuerantwort.fehler("welten quittieren <zustellung>") }
                await z.quittieren(w, zustellung: wert, echt: false)
            case "rueckgabe":
                guard let t = w.ticket(wert) else { return MacSteuerantwort.fehler("kein Ticket \(wert)") }
                z.reiter = .tickets
                z.ticketAuswahl = t.id
                z.rueckgabeOffen = t.id
                z.rueckgabeText = arg
            case "zurueckgeben":
                guard w.ticket(wert) != nil else { return MacSteuerantwort.fehler("kein Ticket \(wert)") }
                z.rueckgabeText = arg
                await z.zurueckgeben(w, ticket: wert, echt: false)
            case "profil":
                switch wert {
                case "bearbeiten":
                    guard let a = w.agent(z.agentId) else { return MacSteuerantwort.fehler("erst einen Agenten waehlen") }
                    z.blatt = .profil
                    z.profilEntwurf = WeltenZustand.ProfilEntwurf(a)
                case "abbrechen": z.profilEntwurf = nil
                case "sichern": await z.profilSichern(w, echt: false)
                default: return MacSteuerantwort.fehler("welten profil bearbeiten|abbrechen|sichern")
                }
            case "profil-feld":
                guard z.profilEntwurf != nil else { return MacSteuerantwort.fehler("kein Profil in Bearbeitung") }
                switch wert {
                case "modell": z.profilEntwurf?.modell = arg
                case "denkstufe": z.profilEntwurf?.denkstufe = arg
                case "fallback": z.profilEntwurf?.fallback = arg
                case "fallback-denkstufe": z.profilEntwurf?.fallbackDenkstufe = arg
                case "maschine": z.profilEntwurf?.maschine = arg
                case "spezialgebiet": z.profilEntwurf?.spezialgebiet = arg
                default: return MacSteuerantwort.fehler("welten profil-feld modell|denkstufe|fallback|fallback-denkstufe|maschine|spezialgebiet <wert>")
                }
            case "gedaechtnis":
                switch wert {
                case "bearbeiten":
                    guard let a = w.agent(z.agentId) else { return MacSteuerantwort.fehler("erst einen Agenten waehlen") }
                    z.blatt = .gedaechtnis
                    z.gedaechtnisEntwurf = WeltenZustand.GedaechtnisEntwurf(agent: a.id, text: a.gedaechtnis, sha: a.gedaechtnisSha)
                case "abbrechen": z.gedaechtnisEntwurf = nil
                case "sichern": await z.gedaechtnisSichern(w, echt: false)
                default: return MacSteuerantwort.fehler("welten gedaechtnis bearbeiten|abbrechen|sichern")
                }
            case "gedaechtnis-text":
                guard z.gedaechtnisEntwurf != nil else { return MacSteuerantwort.fehler("kein Gedaechtnis in Bearbeitung") }
                z.gedaechtnisEntwurf?.text = [wert, arg].filter { !$0.isEmpty }.joined(separator: " ").replacingOccurrences(of: "\\n", with: "\n")
            // --- Auftrag Nr. 4: Skill-Vorschlaege --------------------------------------------
            case "skill-abnehmen":
                guard w.ticket(wert)?.skillVorschlag != nil else { return MacSteuerantwort.fehler("kein Skill-Vorschlag \(wert)") }
                z.reiter = .tickets
                z.ticketAuswahl = wert
                await z.skillAbnehmen(w, ticket: wert, echt: false)
            case "skill-ablehnen":
                // welten skill-ablehnen <ticket> [grund] -- ohne Grund steht nur das Feld offen
                guard w.ticket(wert)?.skillVorschlag != nil else { return MacSteuerantwort.fehler("kein Skill-Vorschlag \(wert)") }
                z.reiter = .tickets
                z.ticketAuswahl = wert
                z.skillAblehnenOffen = wert
                z.skillGrund = arg
                if !arg.isEmpty { await z.skillAblehnen(w, ticket: wert, echt: false) }
            case "skill-zeigen":
                if z.skillOffen.contains(wert) { z.skillOffen.remove(wert) } else { z.skillOffen.insert(wert) }
            // --- Auftrag Nr. 3: das Anlege-Menue ------------------------------------------
            case "anlegen":
                switch wert {
                case "oeffnen":
                    if !arg.isEmpty, !n.vorlagen.contains(where: { $0.name == arg }) { return MacSteuerantwort.fehler("keine Vorlage \(arg)") }
                    z.anlegenOeffnen(n, w, vorlage: arg.isEmpty ? nil : arg)
                case "abbrechen": await z.anlegenAbbrechen(w, echt: false)
                case "vorschlagen":
                    // agents anlegen vorschlagen -- derselbe Weg wie „Vorschlagen lassen …" in der Uebersicht: im Gespraech
                    z.anlegenStarten(n, w, vorschlagen: true)
                case "ansicht":
                    // agents anlegen ansicht gespraech|formular (Auftrag agentschat)
                    guard z.anlegen != nil, let ansicht = WeltenZustand.AnlegenAnsicht(rawValue: arg) else {
                        return MacSteuerantwort.fehler("\(befehl) anlegen ansicht gespraech|formular (Menue offen?)")
                    }
                    z.anlegenAnsicht(ansicht)
                case "gespraech":
                    // agents anlegen gespraech <text> [<modell>] [trocken] -- ein Zug; die Ansicht springt aufs Gespraech
                    guard let a = z.anlegen else { return MacSteuerantwort.fehler("erst \(befehl) anlegen oeffnen") }
                    var teile = arg.split(separator: " ").map(String.init)
                    let trocken = teile.last == "trocken"
                    if trocken { teile.removeLast() }
                    if let m = teile.last, a.entwurfModelle.contains(m) { _ = z.anlegenFeld("vorschlagmodell", m); teile.removeLast() }
                    let text = teile.joined(separator: " ")
                    guard !text.isEmpty else { return MacSteuerantwort.fehler("\(befehl) anlegen gespraech <text> [modell] [trocken]") }
                    z.anlegenAnsicht(.gespraech)
                    await z.gespraechSenden(w, text: text, trocken: trocken, echt: false)
                case "vorlage":
                    guard z.anlegen != nil, let v = n.vorlagen.first(where: { $0.name == arg }) else { return MacSteuerantwort.fehler("welten anlegen vorlage <name> (Menue offen?)") }
                    z.vorlageAnwenden(v, w)
                case "vorschlag":
                    // welten anlegen vorschlag [<modell>] [trocken]
                    guard z.anlegen != nil else { return MacSteuerantwort.fehler("erst welten anlegen oeffnen") }
                    let teile = arg.split(separator: " ").map(String.init)
                    if let m = teile.first(where: { $0.contains(":") }) { _ = z.anlegenFeld("vorschlagmodell", m) }
                    await z.vorschlagErzeugen(w, trocken: teile.contains("trocken"), echt: false)
                case "pruefen": await z.entwurfPruefen(w, echt: false)
                case "hausvorlage": await z.entwurfPruefen(w, anweisungenAusVorlage: true, echt: false)
                case "sichern": await z.anlegenSichern(w, echt: false)
                default: return MacSteuerantwort.fehler("welten anlegen oeffnen [vorlage]|vorschlagen|abbrechen|vorlage <name>|vorschlag [modell] [trocken]|ansicht gespraech|formular|gespraech <text> [modell] [trocken]|pruefen|hausvorlage|sichern")
                }
            case "anlegen-feld":
                // welten anlegen-feld <feld> <wert>; welten anlegen-feld werkzeug <Name> an|aus
                guard z.anlegen != nil else { return MacSteuerantwort.fehler("erst welten anlegen oeffnen") }
                if wert == "werkzeug" {
                    let teile = arg.split(separator: " ").map(String.init)
                    guard teile.count == 2, WeltenZustand.werkzeuge.contains(teile[0]) else { return MacSteuerantwort.fehler("welten anlegen-feld werkzeug <\(WeltenZustand.werkzeuge.joined(separator: "|"))> an|aus") }
                    z.werkzeugSetzen(teile[0], teile[1] == "an")
                } else if !z.anlegenFeld(wert, arg) {
                    return MacSteuerantwort.fehler("welten anlegen-feld name|stufe|team|neues-team|spezialgebiet|modell|denkstufe|fallback|fallback-denkstufe|maschine|bash|skills|kontextgrenze|figur|farbe|anweisungen|beschreibung|vorschlagmodell <wert>")
                }
            case "ticket-neu":
                // welten ticket-neu <an|-> <titel | ziel | fertig>
                let teile = arg.components(separatedBy: " | ")
                guard teile.count == 3 else { return MacSteuerantwort.fehler("welten ticket-neu <an|-> <titel | ziel | fertig>") }
                _ = await z.ticketAnlegen(w, WeltenZustand.TicketEntwurf(titel: teile[0], ziel: teile[1], fertig: teile[2], an: wert == "-" ? "" : wert), echt: false)
            default:
                return MacSteuerantwort.fehler("\(befehl) kennt \(was) nicht")
            }
            return auskunft()

        // --- Das Vorschau-Blatt der Agentenfiguren (Bau-Schritt 4) ----------------
        case "figuren":
            let f = fenster.figurenBauen()
            switch b.text["was"] ?? "" {
            case "standbild": f.zustand.standbild = (b.text["wert"] ?? "an") != "aus"
            case "": break
            default: return MacSteuerantwort.fehler("figuren kennt standbild an|aus")
            }
            return MacSteuerantwort.ok(f.auskunft())

        case "figuren-schuss":
            guard let pfad = b.text["pfad"], !pfad.isEmpty else { return MacSteuerantwort.fehler("Feld pfad fehlt") }
            let f = fenster.figurenBauen()
            do {
                let (bw, bh) = try f.schuss(pfad: pfad, dunkel: b.text["dunkel"] == "1")
                return MacSteuerantwort.ok(["pfad": pfad, "breite": bw, "hoehe": bh, "standbild": f.zustand.standbild])
            } catch {
                return MacSteuerantwort.fehler("Bild nicht geschrieben: \(error.localizedDescription)")
            }

        // --- Die Blaetter des Inspektors (Auftraege 3.5 und 3.6) ---------------
        case "ordner":
            let z = fenster.ordnerZustand
            switch b.text["was"] ?? "" {
            case "klick":
                guard let p = b.text["wert"], !p.isEmpty else { return MacSteuerantwort.fehler("Feld wert fehlt") }
                z.klick(p)
                return MacSteuerantwort.ok(["ordner": z.auskunft()])
            case "zeigen":
                guard let p = b.text["wert"], !p.isEmpty else { return MacSteuerantwort.fehler("Feld wert fehlt") }
                fenster.blattZeigen(.ordner)
                z.zeigen(p)
                return MacSteuerantwort.ok(["ordner": z.auskunft()])
            case "suche":
                z.suche = b.text["wert"] ?? ""
                z.jetztSuchen()
                return MacSteuerantwort.ok(["ordner": z.auskunft()])
            case "jetzt":
                z.sichtbarSetzen(true)
                return MacSteuerantwort.ok(["ordner": z.auskunft()])
            case "":
                return MacSteuerantwort.ok(["ordner": z.auskunft()])
            default:
                return MacSteuerantwort.fehler("ordner kennt klick|zeigen|suche|jetzt")
            }

        case "aktivitaet":
            let z = fenster.aktivitaetZustand
            switch b.text["was"] ?? "" {
            case "lesen":
                z.jetztLesen()
                return MacSteuerantwort.ok(["aktivitaet": z.auskunft()])
            case "klick":
                guard let p = b.text["wert"], !p.isEmpty else { return MacSteuerantwort.fehler("Feld wert fehlt") }
                let r = await z.klick(p)
                guard r.ok else { return MacSteuerantwort.fehler(r.meldung) }
                return MacSteuerantwort.ok(["was": r.was, "aktivitaet": z.auskunft(),
                                            "editorBlatt": await fenster.editorZustand.auskunft()])
            case "":
                return MacSteuerantwort.ok(["aktivitaet": z.auskunft()])
            default:
                return MacSteuerantwort.fehler("aktivitaet kennt lesen|klick")
            }

        case "protokolle":
            let z = fenster.protokolleZustand
            switch b.text["was"] ?? "" {
            case "lesen":
                _ = await z.laden()
                return MacSteuerantwort.ok(["protokolle": z.auskunft()])
            case "oeffnen":
                guard let p = b.text["wert"], !p.isEmpty else { return MacSteuerantwort.fehler("Feld wert fehlt") }
                let r = await z.oeffnen(p)
                guard r.ok else { return MacSteuerantwort.fehler(r.meldung) }
                return MacSteuerantwort.ok(["protokolle": z.auskunft(),
                                            "editorBlatt": await fenster.editorZustand.auskunft()])
            case "":
                return MacSteuerantwort.ok(["protokolle": z.auskunft()])
            default:
                return MacSteuerantwort.fehler("protokolle kennt lesen|oeffnen")
            }

        case "pfad":
            switch b.text["was"] ?? "" {
            case "oeffnen":
                guard let p = b.text["wert"], !p.isEmpty else { return MacSteuerantwort.fehler("Feld wert fehlt") }
                let r = await fenster.pfadOeffner.oeffnen(p)
                guard r.ok else { return MacSteuerantwort.fehler(r.meldung) }
                return MacSteuerantwort.ok(pfadAuskunft())
            case "chat":
                let treffer = fenster.chat.alleTreffer
                let nr = b.zahl["nr"] ?? 0
                guard treffer.indices.contains(nr) else {
                    return MacSteuerantwort.fehler("keine Fundstelle \(nr) (es sind \(treffer.count))")
                }
                let t = treffer[nr]
                let r = await fenster.pfadOeffner.oeffnen(t.zeile > 0 ? "\(t.abs):\(t.zeile):\(max(1, t.spalte))" : t.abs, geprueft: true)
                guard r.ok else { return MacSteuerantwort.fehler(r.meldung) }
                return MacSteuerantwort.ok(pfadAuskunft())
            case "terminal":
                guard let zeile = b.zahl["zeile"] else { return MacSteuerantwort.fehler("Feld zeile fehlt") }
                let spalte = b.zahl["spalte"] ?? 0
                guard let wortlaut = fenster.terminal.pfadUnter(pane: b.text["pane"] ?? "", zeile: zeile, spalte: spalte) else {
                    return MacSteuerantwort.fehler("an Zeile \(zeile), Spalte \(spalte) steht kein Pfad")
                }
                // Derselbe Erkenner und derselbe Oeffner wie beim ⌘-Klick des
                // Menschen; nur das Mausereignis wird nicht erfunden, und auf
                // das Ergebnis wird gewartet, damit eine Pruefung nicht raten muss.
                let r = await fenster.pfadOeffner.oeffnen(wortlaut, pane: b.text["pane"] ?? "")
                var felder = pfadAuskunft()
                felder["wortlaut"] = wortlaut
                guard r.ok else { return MacSteuerantwort.fehler(r.meldung) }
                return MacSteuerantwort.ok(felder)
            case "":
                return MacSteuerantwort.ok(pfadAuskunft())
            default:
                return MacSteuerantwort.fehler("pfad kennt oeffnen|chat|terminal")
            }

        case "einstellungen":
            // Bauen und lesen, NIE zeigen -- wie `awb-ctl einstellungen` (einstellungsfenster.ts, Klassendoc).
            let e = await fenster.einstellungenBauen()
            if let seite = b.text["seite"], !seite.isEmpty {
                guard e.zustand.seiteWaehlen(seite) else { return MacSteuerantwort.fehler("unbekannte Seite: \(seite)") }
            }
            e.fenster.layoutIfNeeded()
            return MacSteuerantwort.ok(e.auskunft())

        case "einstellungen-klick":
            guard let k = b.text["knopf"], !k.isEmpty else { return MacSteuerantwort.fehler("Feld knopf fehlt") }
            let e = await fenster.einstellungenBauen()
            let getroffen = e.zustand.klick(k)
            // Der Schreibweg ist asynchron (Kern, wb-state): auf die Antwort warten, damit die Fusszeile sie traegt.
            try? await Task.sleep(for: .milliseconds(50))
            await e.zustand.schreibvorgaengeAbwarten()
            return MacSteuerantwort.ok(["knopf": k, "getroffen": getroffen, "status": e.zustand.status, "sichtbar": e.sichtbar,
                                        "rueckfrage": e.auskunft()["rueckfrage"] ?? [:]])

        case "einstellungen-eingabe":
            guard let k = b.text["knopf"], !k.isEmpty else { return MacSteuerantwort.fehler("Feld knopf fehlt") }
            let e = await fenster.einstellungenBauen()
            let getroffen = e.zustand.eingabe(k, b.text["wert"] ?? "")
            try? await Task.sleep(for: .milliseconds(50))
            await e.zustand.schreibvorgaengeAbwarten()
            return MacSteuerantwort.ok(["knopf": k, "wert": b.text["wert"] ?? "", "getroffen": getroffen, "status": e.zustand.status, "sichtbar": e.sichtbar])

        case "einstellungen-zustand":
            guard let k = b.text["knopf"], !k.isEmpty else { return MacSteuerantwort.fehler("Feld knopf fehlt") }
            let e = await fenster.einstellungenBauen()
            var a = e.zustand.zustandAuskunft(k)
            a["knopf"] = k
            return MacSteuerantwort.ok(a)

        case "einstellungen-fenster":
            // Die Groesse des EINSTELLUNGSfensters -- `fenster` oben setzt das
            // Hauptfenster. Gebraucht wird der Weg fuer die Gegenprobe am
            // kleinsten erlaubten Mass (08.09.2026): dort und nur dort zeigt
            // sich, ob Seitenleiste und Inhalt sich ueberlagern.
            guard let bw = b.zahl["breite"], let bh = b.zahl["hoehe"] else { return MacSteuerantwort.fehler("breite und hoehe fehlen") }
            let ef = await fenster.einstellungenBauen()
            let masse = ef.groesseSetzen(breite: bw, hoehe: bh)
            var antwort = ef.rahmenAuskunft()
            antwort["breite"] = masse.breite
            antwort["hoehe"] = masse.hoehe
            return MacSteuerantwort.ok(antwort)

        case "einstellungen-schuss":
            guard let pfad = b.text["pfad"], !pfad.isEmpty else { return MacSteuerantwort.fehler("Feld pfad fehlt") }
            let e = await fenster.einstellungenBauen()
            if let seite = b.text["seite"], !seite.isEmpty {
                guard e.zustand.seiteWaehlen(seite) else { return MacSteuerantwort.fehler("unbekannte Seite: \(seite)") }
            }
            e.fenster.layoutIfNeeded()
            do {
                let (bw, bh) = try e.schuss(pfad: pfad)
                return MacSteuerantwort.ok(["pfad": pfad, "breite": bw, "hoehe": bh, "seite": e.zustand.seite, "sichtbar": e.sichtbar])
            } catch {
                return MacSteuerantwort.fehler("Bild nicht geschrieben: \(error.localizedDescription)")
            }

        case "sitzung":
            // Bauen und lesen, NIE zeigen -- wie `awb-ctl sitzung` (sitzungsfenster.ts, Klassendoc).
            let s = await fenster.sitzungBauen()
            s.fenster.layoutIfNeeded()
            return MacSteuerantwort.ok(s.auskunft())

        case "sitzung-klick":
            guard let k = b.text["knopf"], !k.isEmpty else { return MacSteuerantwort.fehler("Feld knopf fehlt") }
            let s = await fenster.sitzungBauen()
            let getroffen = s.zustand.klick(k)
            // Die Handlung laeuft im Kern (wb-code, ssh): auf sie warten, damit die Fusszeile die Antwort traegt.
            try? await Task.sleep(for: .milliseconds(50))
            await s.zustand.handlungAbwarten()
            return MacSteuerantwort.ok(["knopf": k, "getroffen": getroffen, "status": s.zustand.status, "statusArt": s.zustand.statusArt,
                                        "sichtbar": s.sichtbar, "rueckfrage": s.auskunft()["rueckfrage"] ?? [:]])

        case "sitzung-eingabe":
            guard let k = b.text["knopf"], !k.isEmpty else { return MacSteuerantwort.fehler("Feld knopf fehlt") }
            let s = await fenster.sitzungBauen()
            let getroffen = s.zustand.eingabe(k, b.text["wert"] ?? "")
            return MacSteuerantwort.ok(["knopf": k, "wert": b.text["wert"] ?? "", "getroffen": getroffen, "status": s.zustand.status, "sichtbar": s.sichtbar])

        case "verbrauch":
            // Bauen und lesen, NIE zeigen -- der Weg des Steuerkanals (3.8).
            let v = await fenster.verbrauchBauen()
            await v.zustand.handlungAbwarten()
            return MacSteuerantwort.ok(v.auskunft())

        case "verbrauch-klick":
            guard let k = b.text["knopf"], !k.isEmpty else { return MacSteuerantwort.fehler("Feld knopf fehlt") }
            let v = await fenster.verbrauchBauen()
            let getroffen = v.zustand.klick(k)
            // Ein Zeitraumwechsel fragt wb-budget neu: darauf warten, damit die
            // Antwort schon den neuen Stand traegt.
            try? await Task.sleep(for: .milliseconds(30))
            await v.zustand.handlungAbwarten()
            return MacSteuerantwort.ok(v.auskunft().merging(["knopf": k, "getroffen": getroffen]) { a, _ in a })

        case "verbrauch-schuss":
            guard let pfad = b.text["pfad"], !pfad.isEmpty else { return MacSteuerantwort.fehler("Feld pfad fehlt") }
            let v = await fenster.verbrauchBauen()
            do {
                let (bw, bh) = try v.schuss(pfad: pfad)
                return MacSteuerantwort.ok(["pfad": pfad, "breite": bw, "hoehe": bh, "sichtbar": v.sichtbar])
            } catch {
                return MacSteuerantwort.fehler("Bild nicht geschrieben: \(error.localizedDescription)")
            }

        case "erststart":
            // Bauen und lesen, NIE zeigen -- wie `awbmac-ctl sitzung` (3.8).
            let e = await fenster.erststartBauen()
            return MacSteuerantwort.ok(e.auskunft())

        case "erststart-klick":
            guard let k = b.text["knopf"], !k.isEmpty else { return MacSteuerantwort.fehler("Feld knopf fehlt") }
            let e = await fenster.erststartBauen()
            let getroffen = e.zustand.klick(k)
            // Der Abschluss schreibt im Kern (wb-state settings set): darauf
            // warten, damit die Antwort den Stand danach traegt.
            try? await Task.sleep(for: .milliseconds(30))
            await e.zustand.handlungAbwarten()
            return MacSteuerantwort.ok(e.auskunft().merging(["knopf": k, "getroffen": getroffen]) { a, _ in a })

        case "erststart-schuss":
            guard let pfad = b.text["pfad"], !pfad.isEmpty else { return MacSteuerantwort.fehler("Feld pfad fehlt") }
            let e = await fenster.erststartBauen()
            do {
                let (bw, bh) = try e.schuss(pfad: pfad)
                return MacSteuerantwort.ok(["pfad": pfad, "breite": bw, "hoehe": bh, "sichtbar": e.sichtbar])
            } catch {
                return MacSteuerantwort.fehler("Bild nicht geschrieben: \(error.localizedDescription)")
            }

        case "sitzung-zustand":
            guard let k = b.text["knopf"], !k.isEmpty else { return MacSteuerantwort.fehler("Feld knopf fehlt") }
            let s = await fenster.sitzungBauen()
            var a = s.zustand.zustandAuskunft(k)
            a["knopf"] = k
            return MacSteuerantwort.ok(a)

        case "sitzung-schuss":
            guard let pfad = b.text["pfad"], !pfad.isEmpty else { return MacSteuerantwort.fehler("Feld pfad fehlt") }
            let s = await fenster.sitzungBauen()
            s.fenster.layoutIfNeeded()
            do {
                let (bw, bh) = try s.schuss(pfad: pfad, rueckfrage: b.text["art"] == "rueckfrage")
                return MacSteuerantwort.ok(["pfad": pfad, "breite": bw, "hoehe": bh, "sichtbar": s.sichtbar, "art": b.text["art"] ?? ""])
            } catch {
                return MacSteuerantwort.fehler("Bild nicht geschrieben: \(error.localizedDescription)")
            }

        // --- Die Chat-Buehne (Auftrag 3.2): dieselben Griffe wie `awb-ctl chat-*` ---
        case "chat-tippen":
            // Text ins Feld und abschicken -- der Weg der Eingabetaste. `geleert`
            // sagt, dass das Feld sofort leer ist (Zusage 4 der Electron-Suite).
            guard fenster.chatGezeigt else { return MacSteuerantwort.fehler("kein Gespraech auf der Buehne") }
            fenster.chat.eingabe = b.text["text"] ?? ""
            fenster.chat.marke = (fenster.chat.eingabe as NSString).length
            let gesendet = fenster.chat.abschicken()
            return MacSteuerantwort.ok(["gesendet": gesendet, "geleert": fenster.chat.eingabe.isEmpty])

        case "chat-feld":
            guard fenster.chatGezeigt else { return MacSteuerantwort.fehler("kein Gespraech auf der Buehne") }
            fenster.chat.eingabe = b.text["text"] ?? ""
            fenster.chat.marke = (fenster.chat.eingabe as NSString).length
            fenster.chat.vervollstaendigen()
            // Die Dateiliste kommt asynchron vom Kern: kurz warten, dann noch einmal nachsehen.
            if fenster.chat.vervoll == nil, ChatVervollstaendigung.ausloeser(fenster.chat.eingabe, marke: fenster.chat.marke)?.art == .datei {
                try? await Task.sleep(for: .milliseconds(300))
                fenster.chat.vervollstaendigen()
            }
            return MacSteuerantwort.ok(["text": fenster.chat.eingabe, "vervoll": fenster.chat.auskunft()["vervoll"] ?? [:]])

        case "chat-taste":
            guard fenster.chatGezeigt else { return MacSteuerantwort.fehler("kein Gespraech auf der Buehne") }
            guard let roh = b.text["name"], !roh.isEmpty else { return MacSteuerantwort.fehler("Feld name fehlt") }
            let umschalt = roh.hasPrefix("Shift+")
            let name = umschalt ? String(roh.dropFirst(6)) : roh
            // Wie der Haken `taste` der Electron-Fassung: nur die Entscheidung,
            // keine Vorgabehandlung des Feldes -- eine nicht verbrauchte
            // Umschalt+Eingabe laesst den Text stehen (Zusage 19 dort).
            let verbraucht = fenster.chat.taste(name, umschalt: umschalt)
            return MacSteuerantwort.ok(["taste": roh, "verbraucht": verbraucht, "wert": fenster.chat.eingabe,
                                        "vervoll": fenster.chat.auskunft()["vervoll"] ?? [:]])

        case "chat-klick":
            guard fenster.chatGezeigt else { return MacSteuerantwort.fehler("kein Gespraech auf der Buehne") }
            guard let knopf = b.text["knopf"], !knopf.isEmpty else { return MacSteuerantwort.fehler("Feld knopf fehlt") }
            return chatKlick(knopf)

        case "chat-text":
            guard fenster.chatGezeigt else { return MacSteuerantwort.fehler("kein Gespraech auf der Buehne") }
            return MacSteuerantwort.ok(["gezeigt": kern.modell.chatGezeigt, "text": fenster.chat.text()])

        case "chat-zeiten":
            if b.text["leeren"] == "1" { fenster.chat.zeitenLeeren(); return MacSteuerantwort.ok(["geleert": true, "zeiten": []]) }
            return MacSteuerantwort.ok(["geleert": false, "zeiten": fenster.chat.zeiten])

        case "quit":
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { NSApp.terminate(nil) }
            return MacSteuerantwort.ok(["beendet": true])

        default:
            return MacSteuerantwort.fehler("unbekannter Befehl \(b.cmd)")
        }
    }

    /// Ein Knopf der Chat-Buehne, derselbe Weg wie die Maus (ChatZustand).
    private func chatKlick(_ knopf: String) -> Data {
        let z = fenster.chat
        if knopf == "freigabe-ja" || knopf == "freigabe-nein" {
            guard let f = fenster.chatOffeneFrage else { return MacSteuerantwort.fehler("keine offene Freigabefrage") }
            z.freigabe(f.anfrageId, erlauben: knopf == "freigabe-ja")
            return MacSteuerantwort.ok(["knopf": knopf, "anfrageId": f.anfrageId, "gelungen": true])
        }
        if knopf.hasPrefix("werkzeug:") || knopf.hasPrefix("denken:") {
            let id = String(knopf.drop(while: { $0 != ":" }).dropFirst())
            guard z.verlauf.bloecke.contains(where: { $0.id == id }) else { return MacSteuerantwort.fehler("kein Block \(id)") }
            z.klappen(id)
            return MacSteuerantwort.ok(["knopf": knopf, "gelungen": true, "aufgeklappt": z.offen.contains(id)])
        }
        if knopf.hasPrefix("worker:") {
            let pane = String(knopf.dropFirst(7))
            guard z.worker.contains(where: { $0.paneId == pane }) else { return MacSteuerantwort.fehler("kein Worker \(pane) in der Leiste") }
            z.workerZeigen(pane)
            return MacSteuerantwort.ok(["knopf": knopf, "gelungen": true])
        }
        switch knopf {
        case "modus":
            guard z.verlauf.laeuft, let neu = z.verlauf.naechsterModus else { return MacSteuerantwort.fehler("die Modus-Marke ist nicht aktiv") }
            z.modusWeiter()
            return MacSteuerantwort.ok(["knopf": knopf, "gelungen": true, "gewuenscht": neu])
        case "halt":
            guard z.verlauf.haltMoeglich else { return MacSteuerantwort.fehler("es laeuft nichts, was sich unterbrechen liesse") }
            z.halt()
            return MacSteuerantwort.ok(["knopf": knopf, "gelungen": true])
        case "neustart":
            guard z.verlauf.neustartMoeglich, !z.verlauf.laeuft else { return MacSteuerantwort.fehler("kein frischer Start angeboten") }
            z.neustart()
            return MacSteuerantwort.ok(["knopf": knopf, "gelungen": true])
        case "senden":
            return MacSteuerantwort.ok(["knopf": knopf, "gelungen": z.abschicken()])
        default:
            return MacSteuerantwort.fehler("unbekannter Knopf \(knopf)")
        }
    }

    /// Was aus `worker:<…>` wird: genau eine Sitzung mit genau einem Pane, oder
    /// ein Satz, der sagt warum nicht.
    private enum WorkerTreffer {
        case eine(sitzung: String, pane: String)
        case fehler(String)
    }

    /// Löst `<sitzung>/<pane>` oder das alte `<pane>` auf.
    ///
    /// Die lange Form wird NICHT geraten: steht die Sitzung nicht in der Leiste
    /// oder trägt sie den Pane nicht, ist das ein Fehler und kein Anlass,
    /// woanders nachzusehen. Die kurze Form fragt zuerst die gewählte Sitzung
    /// (der Normalfall: ein Klick in der Liste dieser Sitzung), dann die
    /// übrigen -- und meldet Mehrdeutigkeit, statt eine davon zu nehmen.
    private func workerTreffer(_ rest: String) -> WorkerTreffer {
        func traegt(_ s: SitzungsEintrag, _ pane: String) -> Bool {
            s.workers.contains { $0.paneId == pane || $0.subagents.contains { $0.paneId == pane } }
                || s.orphanSubagents.contains { $0.paneId == pane }
        }
        // Getrennt wird am LETZTEN Schrägstrich: die Kennung einer fernen
        // Sitzung trägt selbst einen Doppelpunkt, aber nie einen Schrägstrich,
        // und eine Pane-Kennung (`%3`) auch nicht.
        if let schnitt = rest.lastIndex(of: "/") {
            let id = String(rest[rest.startIndex..<schnitt])
            let pane = String(rest[rest.index(after: schnitt)...])
            guard !id.isEmpty, !pane.isEmpty else { return .fehler("worker:<sitzung>/<pane> erwartet") }
            guard let s = kern.modell.sessions.first(where: { $0.id == id }) else {
                return .fehler("Sitzung nicht in der Leiste: \(id)")
            }
            guard traegt(s, pane) else { return .fehler("die Sitzung \(id) hat keinen Worker mit Pane \(pane)") }
            return .eine(sitzung: s.id, pane: pane)
        }
        let pane = rest
        guard !pane.isEmpty else { return .fehler("worker:<pane> oder worker:<sitzung>/<pane> erwartet") }
        if let s = kern.gewaehlteSitzung, traegt(s, pane) { return .eine(sitzung: s.id, pane: pane) }
        let kandidaten = kern.modell.sessions.filter { traegt($0, pane) }
        guard let s = kandidaten.first else { return .fehler("kein Worker mit Pane \(pane) in der Leiste") }
        guard kandidaten.count == 1 else {
            let namen = kandidaten.map(\.id).joined(separator: ", ")
            return .fehler("Pane \(pane) gibt es in mehreren Sitzungen (\(namen)) -- worker:<sitzung>/\(pane) angeben")
        }
        return .eine(sitzung: s.id, pane: pane)
    }

    private func klick(_ ziel: String) -> Data {
        if ziel.hasPrefix("chat:") {
            // Die Chat-Zeile der Leiste: ueber den Steuerkanal UNECHT, also nur
            // bauen (main.ts `chat-bauen`), wie ein Klick ohne isTrusted in Electron.
            let id = String(ziel.dropFirst(5))
            guard kern.modell.chats.contains(where: { $0.id == id }) else { return MacSteuerantwort.fehler("Chat-Sitzung nicht in der Leiste: \(id)") }
            kern.chatZeigen(id, echt: false)
            return MacSteuerantwort.ok(["chat": id, "echt": false])
        }
        if ziel.hasPrefix("projekt:") {
            // Der Abschnittskopf der Seitenleiste (Politur 08.09.): sein
            // Chevron auf oder zu. Die Kennung ist der Ordner des Projekts.
            let id = String(ziel.dropFirst(8))
            guard kern.modell.projekte.contains(where: { $0.id == id }) else {
                return MacSteuerantwort.fehler("Projekt nicht in der Leiste: \(id)")
            }
            let offen = fenster.oberflaeche.zugeklappteProjekte.contains(id)
            fenster.projektKlappen(id, offen: offen)
            return MacSteuerantwort.ok(["projekt": id, "offen": offen])
        }
        if ziel.hasPrefix("neu-ordner:") {
            // Der Plusknopf ueber der Liste. Der Ordner kommt hier als Text
            // mit -- der Dialog des Systems oeffnet sich ueber den Steuerkanal
            // nie (er wartet auf einen Menschen).
            let pfad = String(ziel.dropFirst(11))
            guard !pfad.isEmpty else { return MacSteuerantwort.fehler("klick neu-ordner:<pfad> erwartet einen Ordner") }
            fenster.neueSitzung(ordner: pfad, echt: true)
            return MacSteuerantwort.ok(["neuOrdner": pfad])
        }
        if ziel.hasPrefix("projekt-neu:") {
            // Das Plus am Projektkopf: dieselbe Handlung, der Ordner steht schon fest.
            let dir = String(ziel.dropFirst(12))
            guard kern.modell.projekte.contains(where: { $0.dir == dir }) else {
                return MacSteuerantwort.fehler("Projekt nicht in der Leiste: \(dir)")
            }
            fenster.neueSitzung(ordner: dir, echt: true)
            return MacSteuerantwort.ok(["projektNeu": dir])
        }
        if ziel.hasPrefix("sitzung:") {
            let id = String(ziel.dropFirst(8))
            guard kern.modell.sessions.contains(where: { $0.id == id }) else {
                return MacSteuerantwort.fehler("Sitzung nicht in der Leiste: \(id)")
            }
            kern.waehlen(id)
            return MacSteuerantwort.ok(["gewaehlt": id])
        }
        if ziel.hasPrefix("worker:") {
            // EINE PANE-KENNUNG GILT JE TMUX-SERVER, NICHT JE HAUS (08.09.2026).
            // Jede Maschine hat ihren eigenen Server, und beide fangen bei `%0`
            // an: in der Pruefung trugen der hiesige Worker `bauer` und der
            // ferne `ferner` beide `%2`. `sessions.first(where:)` nahm damit,
            // was zuerst in der Liste stand -- eine stille Fehlbedienung.
            // Die Kennung ist deshalb `<sitzung>/<pane>` wie im Agents-Blatt.
            // Die alte Form `<pane>` bleibt: sie zielt zuerst auf die GEWAEHLTE
            // Sitzung, danach auf die eine andere, die ihn traegt -- und bricht
            // laut ab, sobald mehr als eine in Frage kommt.
            let rest = String(ziel.dropFirst(7))
            let treffer = workerTreffer(rest)
            switch treffer {
            case .eine(let s, let pane):
                fenster.workerZeigen(sitzung: s, pane: pane)
                return MacSteuerantwort.ok(["sitzung": s, "pane": pane])
            case .fehler(let text):
                return MacSteuerantwort.fehler(text)
            }
        }
        if ziel.hasPrefix("menue:") {
            // Getrennt wird am LETZTEN Doppelpunkt, nicht am ersten: die Kennung
            // einer FERNEN Sitzung traegt selbst einen (`<maschine>:<datei>`,
            // sessions.ts), die Kennung eines Menuepunkts nie. Mit `maxSplits: 1`
            // hiess die Sitzung bis zum 06.09. nur „peer" und der Punkt
            // „p-x:fortsetzen" -- das Kontextmenue jeder Fernsitzung war ueber
            // den Steuerkanal unerreichbar (test-mac-fernsitzung.sh, Zusage 8).
            let rest = String(ziel.dropFirst(6))
            guard let schnitt = rest.lastIndex(of: ":") else { return MacSteuerantwort.fehler("menue:<sitzung>:<punkt> erwartet") }
            let sitzungsId = String(rest[rest.startIndex..<schnitt])
            let punkt = String(rest[rest.index(after: schnitt)...])
            guard !sitzungsId.isEmpty, !punkt.isEmpty else { return MacSteuerantwort.fehler("menue:<sitzung>:<punkt> erwartet") }
            guard kern.modell.sessions.contains(where: { $0.id == sitzungsId }) || kern.modell.chats.contains(where: { $0.id == sitzungsId }) else {
                return MacSteuerantwort.fehler("Sitzung nicht in der Leiste: \(sitzungsId)")
            }
            guard MenuePunkt.alle.contains(where: { $0.id == punkt }) else {
                return MacSteuerantwort.fehler("unbekannter Menuepunkt \(punkt)")
            }
            fenster.menuePunkt(sitzungsId, punkt)
            return MacSteuerantwort.ok(["sitzung": sitzungsId, "punkt": punkt])
        }
        if ziel.hasPrefix("sortierung:") {
            let k = String(ziel.dropFirst(11))
            guard ["recent", "folder", "name"].contains(k) else { return MacSteuerantwort.fehler("unbekannte Sortierung \(k)") }
            kern.sortierung(k)
            return MacSteuerantwort.ok(["sortierung": k])
        }
        if ziel == "beendete" {
            let neu = !kern.modell.ui.showStopped
            kern.beendeteZeigen(neu)
            return MacSteuerantwort.ok(["showStopped": neu])
        }
        if ziel.hasPrefix("kachel:") || ziel.hasPrefix("kachel-doppel:") || ziel.hasPrefix("zoom:") || ziel.hasPrefix("fokus:") {
            // Die Kachel: Kopfzeile (Fokus + Zoom), Doppelklick (zurueck), der
            // Zoom-Knopf (schaltet um), ein Klick ins Terminal (nur Fokus) --
            // dieselben Wege wie die Maus in Kachel.swift.
            let teile = ziel.split(separator: ":", maxSplits: 1).map(String.init)
            let pane = teile.count == 2 ? teile[1] : ""
            guard fenster.terminal.gezeigtePanes.contains(pane) else { return MacSteuerantwort.fehler("kein Pane \(pane) auf der Buehne") }
            let gezoomt = fenster.terminal.lageArt == "pane"
            switch teile[0] {
            case "kachel":
                fenster.terminal.fokusSetzen(pane, tastatur: true)
                if !gezoomt { fenster.kopf.kachelZoomen(pane) }
            case "kachel-doppel":
                fenster.terminal.fokusSetzen(pane, tastatur: true)
                if gezoomt { fenster.kopf.kachelnZurueck() } else { fenster.kopf.kachelZoomen(pane) }
            case "zoom":
                if gezoomt { fenster.kopf.kachelnZurueck() } else { fenster.kopf.kachelZoomen(pane) }
            default:
                fenster.terminal.fokusSetzen(pane, tastatur: true)
            }
            return MacSteuerantwort.ok(["pane": pane, "aktiv": fenster.terminal.gezeigterPane, "warGezoomt": gezoomt])
        }
        if ziel.hasPrefix("tab:") {
            guard let n = Int(ziel.dropFirst(4)) else { return MacSteuerantwort.fehler("tab:<n> erwartet") }
            guard let s = kern.gewaehlteSitzung else { return MacSteuerantwort.fehler("keine Sitzung gewaehlt") }
            let tabs = s.tabs(perTab: kern.modell.capacity.perTab)
            guard n >= 0, n < tabs else { return MacSteuerantwort.fehler("Tab \(n) gibt es nicht (\(tabs) Tabs)") }
            fenster.kopf.tabWaehlen(n)
            return MacSteuerantwort.ok(["tab": n, "panes": s.panesImTab(n, perTab: kern.modell.capacity.perTab)])
        }
        if ziel.hasPrefix("modus:") {
            // Der Umschalter Code | Agents in der Symbolleiste.
            guard let m = Buehnenmodus(rawValue: String(ziel.dropFirst(6))) else { return MacSteuerantwort.fehler("modus kennt code|agents") }
            fenster.modusSetzen(m)
            return MacSteuerantwort.ok(["modus": m.rawValue, "agentsSichtbar": fenster.agentsSichtbar])
        }
        if ziel.hasPrefix("umschalter:") {
            guard let a = Ansicht(rawValue: String(ziel.dropFirst(11))) else { return MacSteuerantwort.fehler("unbekannte Ansicht") }
            fenster.ansichtSetzen(a)
            return MacSteuerantwort.ok(["ansicht": a.rawValue])
        }
        if ziel.hasPrefix("workerliste:") {
            // Ein Klick in der offenen Liste: derselbe Weg wie der Knopf in der
            // View. Die Liste zeigt nur die GEWAEHLTE Sitzung, also ist die
            // Kennung hier immer eindeutig; `<sitzung>/<pane>` wird trotzdem
            // angenommen (dieselbe Schreibweise wie im Agents-Blatt) und gegen
            // die gewaehlte Sitzung geprueft.
            var pane = String(ziel.dropFirst(12))
            guard fenster.oberflaeche.workerListeOffen else { return MacSteuerantwort.fehler("die Worker-Liste ist nicht offen -- erst klick pille") }
            guard let s = kern.gewaehlteSitzung else { return MacSteuerantwort.fehler("keine Sitzung gewaehlt") }
            if let schnitt = pane.lastIndex(of: "/") {
                let id = String(pane[pane.startIndex..<schnitt])
                guard id == s.id else { return MacSteuerantwort.fehler("die Liste zeigt \(s.id), nicht \(id)") }
                pane = String(pane[pane.index(after: schnitt)...])
            }
            guard s.workerPanesMitSubagenten.contains(pane) else { return MacSteuerantwort.fehler("kein Worker mit Pane \(pane) in der Liste") }
            fenster.workerZeigen(sitzung: s.id, pane: pane)
            fenster.kopf.workerListeSchliessen()
            return MacSteuerantwort.ok(["sitzung": s.id, "pane": pane])
        }
        if ziel.hasPrefix("maschine:") {
            // Die Karte: ihr Popover auf oder zu (kopflos: der Zustand).
            let name = String(ziel.dropFirst(9))
            guard kern.modell.maschinenKarten.contains(where: { $0.name == name }) else { return MacSteuerantwort.fehler("keine Maschinenkarte \(name)") }
            fenster.karteUmschalten(name)
            return MacSteuerantwort.ok(["maschine": name, "feldOffen": fenster.oberflaeche.offeneKarte == name])
        }
        if ziel.hasPrefix("maschine-laden:") {
            // Der Schalter im Feld: umlegen, derselbe Weg wie das Kaestchen
            // (Electron `maschine-klick <name> laden`).
            let name = String(ziel.dropFirst(15))
            guard let m = kern.modell.maschinenKarten.first(where: { $0.name == name }) else { return MacSteuerantwort.fehler("keine Maschinenkarte \(name)") }
            guard !m.eigen else { return MacSteuerantwort.fehler("die eigene Maschine traegt keinen Schalter") }
            fenster.maschineLaden(name, m.pausiert)
            return MacSteuerantwort.ok(["maschine": name, "laden": m.pausiert])
        }
        if ziel.hasPrefix("blatt:") {
            // Der Umschalter des Inspektors (3.5/3.6) -- derselbe Weg wie das
            // Menue „Blätter" und die vier Kuerzel ⌥⌘1 bis ⌥⌘4.
            let name = String(ziel.dropFirst(6))
            guard let w = BlattWahl(rawValue: name) else {
                return MacSteuerantwort.fehler("blatt kennt \(BlattWahl.allCases.map(\.rawValue).joined(separator: "|"))")
            }
            fenster.blattZeigen(w)
            return MacSteuerantwort.ok(["blatt": fenster.oberflaeche.blatt.rawValue, "offen": fenster.freigabenBlattSichtbar])
        }
        switch ziel {
        case "ergebnis":
            // Der Knopf „Öffnen“ an der Ergebnismeldung. Er oeffnet nebenlaeufig
            // (der Kern muss die Datei erst lesen); was daraus wurde, steht
            // danach in `ui.pfad`.
            guard let e = fenster.ergebnisSichtbar else { return MacSteuerantwort.fehler("keine Ergebnismeldung im Fuss") }
            fenster.ergebnisOeffnen()
            return MacSteuerantwort.ok(["ergebnis": e.path])
        case "ergebnis-weg":
            fenster.ergebnisWeg()
            return MacSteuerantwort.ok([:])
        case "hinweis":
            guard !kern.meldung.isEmpty, kern.meldungBis > Date() else { return MacSteuerantwort.fehler("kein Hinweis im Fuss") }
            fenster.hinweisWeg()
            return MacSteuerantwort.ok(["notiz": ""])
        case "freigaben":
            fenster.freigabenUmschalten(nil)
            return MacSteuerantwort.ok(["freigabenOffen": fenster.freigabenBlattSichtbar])
        case "freigabeleiste":
            guard !fenster.offeneFreigaben.isEmpty else { return MacSteuerantwort.fehler("die Leiste steht nicht: nichts offen") }
            fenster.freigabenBlattZeigen()
            return MacSteuerantwort.ok(["freigabenOffen": fenster.freigabenBlattSichtbar])
        case "freigabe-mehr":
            fenster.freigabenZustand.begruendungOffen.toggle()
            return MacSteuerantwort.ok(["begruendungOffen": fenster.freigabenZustand.begruendungOffen])
        case "freigabe-vor":
            fenster.blaettern(1)
            return MacSteuerantwort.ok(["nr": fenster.freigabenZustand.nr])
        case "freigabe-zurueck":
            fenster.blaettern(-1)
            return MacSteuerantwort.ok(["nr": fenster.freigabenZustand.nr])
        case "pille":
            guard kern.gewaehlteSitzung != nil else { return MacSteuerantwort.fehler("keine Sitzung gewaehlt") }
            fenster.kopf.workerListeUmschalten()
            return MacSteuerantwort.ok(["workerlisteOffen": fenster.oberflaeche.workerListeOffen])
        case "zahnrad":
            fenster.einstellungenZeigen(nil)
            return MacSteuerantwort.ok(["einstellungenOffen": true])
        case "seitenleiste":
            fenster.seitenleisteUmschalten(nil)
            return MacSteuerantwort.ok(["seitenleisteSichtbar": fenster.seitenleisteSichtbar])
        default:
            return MacSteuerantwort.fehler("unbekanntes Ziel \(ziel)")
        }
    }

    /// Das Editorfenster der gefragten Fassung; ein anderes wird ersetzt.
    private func editorBauen(_ fassung: EditorFassung, neu: Bool = false) -> EditorFenster {
        if let e = editor, e.ansicht.fassung == fassung, !neu { return e }
        editor?.fenster.close()
        let e = EditorFenster(fassung: fassung, optionen: optionen)
        editor = e
        return e
    }

    /// Was von den anklickbaren Pfaden zu sehen ist (Auftrag 3.6): die
    /// Fundstellen im Gespraech und das zuletzt Geoeffnete.
    private func pfadAuskunft() -> [String: Any] {
        let treffer = fenster.chat.alleTreffer
        return [
            "chatPfade": treffer.map { ["wortlaut": $0.kandidat, "abs": $0.abs, "art": $0.art,
                                        "zeile": $0.zeile, "spalte": $0.spalte] },
            "chatAnzahl": treffer.count,
            "zuletzt": fenster.pfadOeffner.auskunft(),
        ]
    }

    private func ui() -> [String: Any] {
        let m = kern.modell
        let projekte: [[String: Any]] = m.projekte.map { p in
            [
                "projekt": p.projekt,
                "dir": p.dir,
                // Was der Kopf zeigt: alle Zeilen, Gespraeche eingeschlossen
                // (renderer.ts `zeichneBaum`; Befund 08.09.).
                "anzahl": p.zeilen.count,
                "sitzungen_anzahl": p.sitzungen.count,
                "kurzpfad": p.kurzpfad,
                "wartet": p.wartet,
                // Zu- oder aufgeklappt (Politur 08.09.); zugeklappt zeichnet
                // die Leiste nur noch den Kopf.
                "offen": !fenster.oberflaeche.zugeklappteProjekte.contains(p.id),
                "punkt": p.wartet > 0 ? Punktart.will.rawValue : "",
                "chats": p.chats.map { c -> [String: Any] in
                    ["id": c.id, "name": c.name, "ordner": c.ordner, "laeuft": c.laeuft, "zusatz": c.zusatzzeile,
                     "symbol": ChatZeile.symbol(laeuft: c.laeuft), "gezeigt": c.id == m.gezeigterChat?.id,
                     "punkt": ChatZeile.punkt(laeuft: c.laeuft).rawValue,
                     "punktForm": ChatZeile.punkt(laeuft: c.laeuft).form,
                     "worker": c.worker.map { ["name": $0.name, "pane": $0.paneId, "laeuft": $0.laeuft] }]
                },
                "zeilen": p.zeilen.map(\.id),
                "sitzungen": p.sitzungen.map { s -> [String: Any] in
                    let lebende = Set(s.workers.filter { $0.alive }.map(\.name))
                    return [
                        "id": s.id, "name": s.name, "state": s.state, "zustandText": s.zustandText,
                        "punkt": SitzungsZeile.punkt(fuer: s).rawValue,
                        "punktForm": SitzungsZeile.punkt(fuer: s).form,
                        "punktWort": SitzungsZeile.punkt(fuer: s).wort,
                        "alive": s.alive, "tmuxSession": s.tmuxSession,
                        "orchestratorPane": s.orchestratorPane, "machine": s.machine, "fern": s.fern(eigene: m.machine),
                        "zusatz": s.zusatzzeile(eigene: m.machine), "pendingApprovals": s.pendingApprovals,
                        "verloren": s.verloren, "startet": s.startet, "startFehler": s.startFehler,
                        "worker": s.workers.map { w -> [String: Any] in
                            let kind = !w.requestedBy.isEmpty && lebende.contains(w.requestedBy)
                            let z = WorkerZeile(worker: w, kind: kind, kinder: 0)
                            return ["name": w.name, "state": w.state, "zustandText": WorkerZeile.wort(fuer: w.state),
                                    "punkt": WorkerZeile.punkt(fuer: w.state).rawValue,
                                    "punktForm": WorkerZeile.punkt(fuer: w.state).form,
                                    "unten": z.unten, "model": w.model,
                                    "tokens": w.tokensKurz, "pane": w.paneId, "alive": w.alive, "kind": kind,
                                    "herkunft": kind ? w.requestedBy : "",
                                    "subagenten": w.subagents.map { ["name": $0.anzeigename, "type": $0.type, "pane": $0.paneId] }]
                        },
                        "elternloseSubagenten": s.orphanSubagents.map { ["name": $0.anzeigename, "type": $0.type, "pane": $0.paneId] },
                    ]
                },
            ]
        }
        let menuePunkte = MenuePunkt.alle.map { $0.id }
        var umbenennen: [String: Any] = ["offen": false]
        if let u = fenster.oberflaeche.umbenennen { umbenennen = ["offen": true, "id": u.id, "name": u.name, "dir": u.dir] }
        // Die Freigabeleiste und das Blatt, wie die Electron-Fassung sie meldet
        // (`rendered.freigabeleiste`, `rendered.freigaben`) -- gleiche Feldnamen,
        // damit eine Suite beide Fassungen gleich liest.
        let offene = fenster.offeneFreigaben
        let vorne = fenster.freigabenZustand.vorne(offene)
        let fr = kern.freigaben
        let leiste: [String: Any] = [
            "offen": !offene.isEmpty,
            "anzahl": offene.count,
            "abzeichen": String(offene.count),
            "abzeichenLeer": offene.isEmpty,
            "wer": vorne?.wer ?? "",
            "worum": vorne.map { "wartet auf Dich · \($0.worum)" } ?? "",
            "art": vorne?.art.rawValue ?? "",
            "nr": fenster.freigabenZustand.nr,
            "knoepfe": offene.isEmpty ? [] : ["Freigeben", "Ablehnen"],
            "begruendungOffen": fenster.freigabenZustand.begruendungOffen,
            "grund": fenster.freigabenZustand.grund,
        ]
        let blatt: [String: Any] = [
            "offen": fenster.freigabenBlattSichtbar,
            "requests": fr.requests.map { ["path": $0.path, "parent": $0.parent, "childName": $0.childName, "childModel": $0.childModel, "dir": $0.dir, "task": $0.task] },
            // Der gezeichnete Wortlaut einer Antragskarte (Kopf, Zusatz, Aufgabe) --
            // wie `requestTexte` der Electron-Fassung: was im Blatt als TEXT steht.
            "requestTexte": fr.requests.map { "\($0.parent) → \($0.childName) \($0.modellText) · \($0.projekt) Aufgabe: \($0.task)" },
            "guardBlocks": fr.guardBlocks.map { ["pane": $0.pane, "workerName": $0.workerName, "sessionName": $0.sessionName, "wartet": $0.wartet,
                                                 "schluessel": $0.schluessel, "command": $0.command, "muster": $0.muster, "unbekannterPane": $0.unbekannterPane] },
            "blockTexte": fr.guardBlocks.map { "\($0.wer) \($0.command)" },
            "verlauf": fr.guardLog.map { ["guard": $0.guardName, "reason": $0.reason, "anzahl": $0.anzahl] },
            "meldung": fenster.freigabenZustand.meldungBis < Date() ? "" : fenster.freigabenZustand.meldung,
        ]
        return [
            "freigabeleiste": leiste,
            "freigaben": blatt,
            // Der Inspektor und seine drei uebrigen Blaetter (3.5/3.6).
            "blatt": fenster.oberflaeche.blatt.rawValue,
            "blattOffen": fenster.freigabenBlattSichtbar,
            "ordner": fenster.ordnerZustand.auskunft(),
            "aktivitaet": fenster.aktivitaetZustand.auskunft(),
            "protokolle": fenster.protokolleZustand.auskunft(),
            "pfad": pfadAuskunft(),
            "fenster": [
                "breite": Int(fenster.fenster.frame.width), "hoehe": Int(fenster.fenster.frame.height),
                "x": Int(fenster.fenster.frame.origin.x), "y": Int(fenster.fenster.frame.origin.y),
                "sichtbar": fenster.fenster.isVisible, "titel": fenster.fenster.title, "untertitel": fenster.fenster.subtitle,
                // OB DIE APP VORN IST (08.09.2026). Unter `--ohne-fokus` darf
                // kein Fenster die App aktivieren -- daran haengt, ob eine
                // Pruefung jemandem die Tastatur wegnimmt (Laufoptionen.swift,
                // `vorZeigen`). Kopflos ist die Frage ohne Sinn und die Antwort
                // immer falsch; gemessen wird sie am sichtbaren Fenster.
                "appAktiv": NSApp.isActive,
                // Und welches Fenster die Tastatur hat: `makeKeyAndOrderFront`
                // holt sie auch dann, wenn das System die Aktivierung der App
                // ablehnt (macOS 14 und spaeter gibt sie nicht jedem Aufruf).
                "schluesselfenster": NSApp.keyWindow?.title ?? "",
                // Und wie oft ein Fenster die App nach vorn holen WOLLTE -- die
                // Zahl, an der die Zusage haengt (Laufoptionen.swift, `Fensterweg`).
                "aktivierungen": Fensterweg.aktivierungen,
                "dunkel": fenster.fenster.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua,
                // Fenster- und Ansichtszustand (Auftrag 2.8): Vollbild, die Breiten
                // der Spalten, der Name des gemerkten Rahmens, die Symbolleiste
                // mit ihren VoiceOver-Beschriftungen.
                "vollbild": fenster.vollbild,
                "seitenleisteBreite": fenster.seitenleisteBreite,
                "inspektorBreite": fenster.inspektorBreite,
                "rahmenName": Fenster.rahmenName,
                "symbolleiste": fenster.symbolleisteAuskunft(),
            ],
            // DIE FARBEN DER ZUSTANDSPUNKTE (08.09.2026). `zustandsfarben` ist,
            // was der Kern geschickt hat (kontrastgeprueft, `zustandsfarbenLesbar`);
            // `punkte` ist, was am Bildpunkt wirklich steht. Beide muessen
            // gleich sein -- dazwischen liegt nur das Zeichnen.
            "thema": [
                "wirksam": Zustandsfarben.aktuell.wirksam,
                "zustandsfarben": Zustandsfarben.aktuell.hex,
                "punkte": Dictionary(uniqueKeysWithValues: Punktart.allCases.map {
                    ($0.rawValue, Zustandsfarben.gemessen($0, dunkel: fenster.fenster.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua))
                }),
                "quelle": Dictionary(uniqueKeysWithValues: Punktart.allCases.map { ($0.rawValue, $0.kernfarbe ?? "") }),
            ] as [String: Any],
            "kern": ["verbunden": kern.verbunden, "pid": kern.kernPid, "fehler": kern.kanalFehler ?? "",
                     "steuerkanal": kern.kernSteuerkanal, "ereignisse": kern.ereignisse, "gesendet": kern.gesendet],
            "seitenleiste": ["sichtbar": fenster.seitenleisteSichtbar, "projekte": projekte, "gewaehlt": m.selected,
                             "showStopped": m.ui.showStopped, "sort": m.ui.sort, "order": m.ui.order, "alle": m.all,
                             // Die von Hand gezogenen Reihenfolgen, wie der Kern
                             // sie fuehrt (uistate.ts), und die Ordner in der
                             // Folge, in der die Leiste sie WIRKLICH zeichnet.
                             "projektReihenfolge": m.ui.projektReihenfolge,
                             "projektFolge": m.projekte.map(\.dir),
                             "menuePunkte": menuePunkte, "gezeichneteZeilen": fenster.seitenleisteZeilen,
                             "zeilenhoehen": fenster.seitenleisteZeilenhoehen,
                             "inhaltsflaeche": fenster.seitenleisteInhaltsflaeche,
                             "zustandsbreiten": fenster.seitenleisteZustandsbreiten,
                             "plusknoepfe": ["projekt-neu": fenster.seitenleistePlusknoepfe("projekt-neu"),
                                             "neu-ordner": fenster.seitenleistePlusknoepfe("neu-ordner")],
                             // Der Kontrast des Projektnamens, gerechnet gegen den
                             // Grund der Leiste (Leistenkontrast, 08.09.2026).
                             "kontrast": Leistenkontrast.auskunft(
                                 dunkel: fenster.fenster.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua),
                             // Die Sollzahlen der Leiste -- damit eine Pruefung
                             // die gemessenen Hoehen dagegenhalten kann.
                             "masse": ["zeile": Int(Leistenmasse.zeile), "kopf": Int(Leistenmasse.kopf),
                                       "inhalt": Int(Leistenmasse.inhalt), "punkt": Int(Leistenmasse.punkt)]],
            "umbenennen": umbenennen,
            // Die Chat-Buehne (3.2): was liegt, wie es gezeichnet ist (ChatZustand.auskunft).
            "chat": fenster.chat.auskunft(),
            "buehne": ["art": fenster.oberflaeche.modus == .agents ? "agents" : (!m.chatGezeigt.isEmpty ? "chat" : (!m.chatWerkstattGezeigt.isEmpty ? "werkstatt" : "terminal")),
                       "chatId": m.chatGezeigt.isEmpty ? m.chatWerkstattGezeigt : m.chatGezeigt, "chatSichtbar": fenster.chatGezeigt],
            // Der Umschalter Code | Agents und das Blatt dahinter (macagents).
            "modus": fenster.oberflaeche.modus.rawValue,
            "agents": fenster.agentsAuskunft(),
            "rueckfrage": ["titel": fenster.oberflaeche.letzteRueckfrage, "antwort": fenster.oberflaeche.letzteRueckfrageAntwort],
            "meldung": kern.meldungBis < Date() ? "" : kern.meldung,
            // Der Statusfuss (Auftrag 2.5), wie `rendered.status` der Electron-Fassung.
            "status": StatusfussAuskunft.auskunft(kern: kern, oberflaeche: fenster.oberflaeche, kopflos: optionen.kopflos),
            // Was der Umschalter ZEIGT (die Buehne) und was gewaehlt ist (die Wahl) -- Kopf.swift.
            "umschalter": fenster.kopf.angezeigt.rawValue,
            "umschalterWahl": fenster.oberflaeche.ansicht.rawValue,
            "kopf": fenster.kopf.auskunft(),
            "einstellungenOffen": fenster.oberflaeche.einstellungenOffen,
            // Das Einstellungsfenster (2.6): Seite, Felder mit Werten, Fusszeile, Rueckfrage -- nur wenn gebaut.
            "einstellungen": fenster.einstellungen?.auskunft() ?? ["gebaut": false],
            // Das Sitzungsfenster (2.7): Gruppen, Zeilen, Wahl, Fusszeile, Rueckfrage -- nur wenn gebaut.
            "sitzungenOffen": fenster.oberflaeche.sitzungenOffen,
            "sitzung": fenster.sitzungen?.auskunft() ?? ["gebaut": false],
            // Der gefuehrte erste Start (3.8): Schritt, Wahl, Antworten -- nur wenn gebaut.
            "erststart": fenster.erststart?.auskunft() ?? ["gebaut": false],
            // Die Verbrauchsseite (3.8): Zeitraum, Filter, Abschnitte -- nur wenn gebaut.
            "verbrauch": fenster.verbrauch?.auskunft() ?? ["gebaut": false],
            // Der Editor-Baustein (3.3): Fassung, Pfad, Zeilen, Cursor -- nur wenn gebaut.
            "editor": editorAuskunft,
            // Das Editor-Blatt im Hauptfenster (3.4): Tabs, Baum, Klappzustand.
            "editorBlatt": blattAuskunft.merging([
                "sichtbar": fenster.editorSichtbar,
                "leisteHoehe": Int(fenster.editorLeisteHoehe.rounded()),
            ]) { a, _ in a },
            "terminal": ["art": optionen.terminal.rawValue, "pane": fenster.terminal.gezeigterPane,
                         "panes": fenster.terminal.gezeigtePanes, "lage": fenster.terminal.lageArt,
                         "cols": fenster.terminal.cols, "rows": fenster.terminal.rows,
                         "sichtbar": !fenster.terminal.isHidden, "zeilen": fenster.terminal.schirmZeilen(),
                         // Die Kacheln, wie sie liegen (Auftrag 2.3): x/y von oben links, b/h
                         // mit Kopfzeile, cols/rows aus dem Kern, aktiv = hat die Tastatur.
                         "kacheln": fenster.terminal.kachelAuskunft(),
                         // Die Buehne: Groesse, der Abstand links (0, solange die
                         // Seitenleiste steht) und wo sie im FENSTER anfaengt.
                         "buehne": ["b": fenster.terminal.buehneGroesse.b, "h": fenster.terminal.buehneGroesse.h,
                                    "einzug": Int(fenster.buehnenEinzugJetzt.rounded()), "x": fenster.buehnenXImFenster,
                                    "xroh": fenster.buehnenXRoh, "seiteX": fenster.seitenleisteXImFenster],
                         "gemeldet": ["cols": fenster.terminal.gemeldet.cols, "rows": fenster.terminal.gemeldet.rows,
                                      "meldungen": fenster.terminal.meldungen],
                         "zelle": ["b": fenster.terminal.zelle.breite, "h": fenster.terminal.zelle.hoehe],
                         // Was SwiftTerm wirklich zeichnet, aus der Instanz gelesen.
                         "zelleGemessen": fenster.terminal.zelleGemessen.map { ["b": $0.breite, "h": $0.hoehe] } ?? [:],
                         "kachelZeilen": fenster.terminal.kachelZeilen, "kopfHoehe": Int(KachelKopf.hoehe), "fuge": Int(Kachelung.fuge),
                         // Die Schriftgroesse, die der Kern zuletzt gemeldet hat
                         // (Auftrag 4.1): seit der Kern im Mantelbetrieb keinen
                         // eigenen Renderer mehr hat, ist DAS die Stelle, an der
                         // sich eine geaenderte Einstellung nachweisen laesst --
                         // `awb-ctl ui` las sie vorher aus dem Electron-Fenster.
                         "schrift": kern.modell.schriftgroesse,
                         "gezoomt": fenster.terminal.lageArt == "pane"],
        ]
    }
}
