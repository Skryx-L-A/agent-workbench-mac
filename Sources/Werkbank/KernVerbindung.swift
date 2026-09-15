// Die Verbindung zum Kern ueber den Mantel-Socket (app/src/main/mantel.ts).
//
// Sie ist das Gegenstueck zu preload.ts: dieselben Kanaele, dieselben
// Nutzlasten, nur als JSON-Zeilen statt IPC. Alles, was die Oberflaeche
// zeichnet, steht hier als beobachtbarer Zustand; die Ereignisse des Kerns
// kommen auf einer Hintergrund-Warteschlange an und werden auf dem
// Hauptakteur eingetragen.
//
// Die Verbindung haelt sich selbst: reisst sie ab (Kern beendet, Kern noch
// nicht da), versucht sie es jede Sekunde wieder -- ein Fenster, das seinen
// Kern verliert, sagt das sichtbar (`kanalFehler`) statt still stehenzubleiben.
import Foundation
import Observation
import WerkbankProtokoll

@MainActor
@Observable
final class KernVerbindung {
    private(set) var verbunden = false
    private(set) var kernPid = 0
    private(set) var modell = ModellNutzlast(sessions: [], selected: "")
    private(set) var sitzung: SitzungsNutzlast?
    private(set) var lage: LageNutzlast?
    /// Der Steuerkanal des Kerns -- aus `awb:kanal`, fuer die Anzeige.
    private(set) var kernSteuerkanal = ""
    private(set) var kanalFehler: String?
    /// Zaehler der empfangenen Ereignisse je Kanal, fuer `awbmac-ctl ui` und die Messung.
    private(set) var ereignisse: [String: Int] = [:]
    /// Die letzte Zeile des Kerns an den Menschen (`awb:meldung`) und bis wann sie steht.
    private(set) var meldung = ""
    private(set) var meldungBis = Date.distantPast
    /// Antraege, angehaltene Worker und Verlauf (`awb:freigaben`), im Takt des
    /// Kerns. Die Wahrheit liegt in der Ablage des Kerns, nicht im Klick: die
    /// Leiste zeichnet diesen Stand und nichts, was sie sich selbst merkt.
    private(set) var freigaben = FreigabenNutzlast()
    /// Die Ansicht „Agents“ (`awb:aufgaben`, app/src/main/aufgaben.ts), im Takt
    /// des Kerns; nil, bis die erste Meldung da ist (die Ansicht zeigt „ladend“).
    private(set) var aufgaben: AufgabenNutzlast?
    /// Die Welten der Agents (Fassung 28, WeltenNutzlast.swift) -- dasselbe Ereignis
    /// `awb:aufgaben`, Feld `welten`; nil, bis ein Kern sie schickt.
    private(set) var welten: WeltenNutzlast?
    /// Nach jedem (Wieder-)Verbinden -- das Fenster sagt dem Kern dann, ob die Ansicht „Agents“ steht.
    @ObservationIgnored var aufHallo: (() -> Void)?

    /// Der Kern bittet um einen neuen Namen (`awb:umbenennen`): das Fenster oeffnet sein Feld.
    @ObservationIgnored var aufUmbenennen: ((UmbenennenNutzlast) -> Void)?
    /// Ein neuer Datenstand des Einstellungsfensters (`awb:ein-daten-neu`, nach
    /// jedem Schreibvorgang und bei jeder Aenderung der Datei von aussen) -- roh,
    /// das Fenster liest ihn (EinstellungenZustand.datenAngekommen).
    @ObservationIgnored var aufEinstellungenNeu: ((Data) -> Void)?
    /// Ein neuer Datenstand des Sitzungsfensters (`awb:sitz-daten-neu`, nach
    /// jeder Handlung, die die Lage aendert) -- roh, das Blatt liest ihn.
    @ObservationIgnored var aufSitzungNeu: ((Data) -> Void)?
    /// Eine beobachtete Datei hat sich geaendert (`awb:datei-geaendert`):
    /// `name` sagt, wer gemeint ist (`editor` fuer eine offene Datei des
    /// Editor-Blatts, sonst eine Seite), `pfad` welche.
    @ObservationIgnored var aufDateiGeaendert: ((String, String) -> Void)?
    /// Ein Start ist gescheitert (`awb:sitz-startfehler`: ort, kurz, grund, protokoll).
    @ObservationIgnored var aufStartfehler: ((Data) -> Void)?

    /// Ein neuer Stand der Chat-Sitzung auf der Buehne (`awb:chat-stand-neu`,
    /// chatbuehne.ts, Auftrag 3.1): nur das Geaenderte seit dem letzten Takt.
    @ObservationIgnored var aufChatStand: ((ChatStandNachricht) -> Void)?
    /// Ausgabe eines Panes (`awb:output`), roh. Nicht beobachtet: das Terminal haengt sich direkt an.
    @ObservationIgnored var aufAusgabe: ((String, Data) -> Void)?
    /// Eine neue Lage (`awb:layout`), nach dem Eintragen.
    @ObservationIgnored var aufLage: ((LageNutzlast) -> Void)?

    // Die drei Blaetter (Auftraege 3.5/3.6): der Kern schickt sie auf denselben
    // Kanaelen wie an den Renderer -- `ordner-liste` und `suche-lesen` sind
    // Feuern-und-Vergessen, die Antwort kommt als Ereignis zurueck.
    /// Der Inhalt EINES Ordners (`awb:ordner`) -- die Antwort auf `ordner-liste`.
    @ObservationIgnored var aufOrdner: ((OrdnerNutzlast) -> Void)?
    /// Die Aktivitaetsliste (`awb:aktivitaet`).
    @ObservationIgnored var aufAktivitaet: ((AktivitaetNutzlast) -> Void)?
    /// Ein Suchlauf ist fertig (`awb:suche`).
    @ObservationIgnored var aufSuche: ((SucheNutzlast) -> Void)?
    /// Eine Ergebnisdatei ist entstanden (`awb:ergebnis`, results.ts).
    @ObservationIgnored var aufErgebnis: ((ErgebnisNutzlast) -> Void)?

    @ObservationIgnored private let pfad: String
    @ObservationIgnored private let token: String
    @ObservationIgnored private var fd: Int32 = -1
    @ObservationIgnored private var quelle: DispatchSourceRead?
    @ObservationIgnored private var rahmen = Zeilenrahmen()
    @ObservationIgnored private var naechsteId = 1
    @ObservationIgnored private var wartend: [Int: CheckedContinuation<KernAntwort, Never>] = [:]
    @ObservationIgnored private var wiederholung: Timer?
    @ObservationIgnored private let queue = DispatchQueue(label: "agent-workbench.werkbank.kern")

    init(pfad: String, token: String) {
        self.pfad = pfad
        self.token = token
    }

    /// Verbindet und bleibt dran: ohne Kern wird jede Sekunde neu probiert.
    func starten() {
        versuchen()
        wiederholung = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.versuchen() }
        }
    }

    func beenden() {
        wiederholung?.invalidate()
        wiederholung = nil
        quelle?.cancel()
        quelle = nil
        fd = -1
        verbunden = false
    }

    private func versuchen() {
        guard fd < 0, !pfad.isEmpty else { return }
        do {
            let neu = try UnixSocket.verbinden(pfad)
            fd = neu
            rahmen = Zeilenrahmen()
            quelle = UnixSocket.leser(fd: neu, queue: queue, daten: rueckrufDaten(), ende: rueckrufEnde())
            UnixSocket.schreiben(neu, KernAnfrage.hallo(token: token))
            kanalFehler = nil
        } catch {
            kanalFehler = "\(error)"
        }
    }

    // Nonisolated gebaut, aus demselben Grund wie in MacSteuerkanal.swift.
    private nonisolated func rueckrufDaten() -> @Sendable (Data) -> Void {
        { d in Task { @MainActor in self.empfangen(d) } }
    }

    private nonisolated func rueckrufEnde() -> @Sendable () -> Void {
        { Task { @MainActor in self.getrennt() } }
    }

    private func getrennt() {
        verbunden = false
        fd = -1
        quelle = nil
        kanalFehler = "Die Verbindung zum Kern ist abgerissen (\(pfad))."
        for (_, c) in wartend { c.resume(returning: KernAntwort(zeile: Data("{\"ok\":false,\"error\":\"Verbindung abgerissen\"}".utf8))) }
        wartend.removeAll()
    }

    private func empfangen(_ daten: Data) {
        for zeile in rahmen.aufnehmen(daten) {
            switch KernNachricht.lesen(zeile) {
            case .hallo(let pid):
                verbunden = true
                kernPid = pid
                aufHallo?()
                // Das Thema kommt sonst erst beim naechsten Wechsel
                // (`awb:thema-neu` wird nur bei einer Aenderung geschickt).
                // Also einmal danach fragen, sobald die Verbindung steht.
                Task { @MainActor in await self.themaHolen() }
            case .antwort(let id, _, let z):
                if let c = wartend.removeValue(forKey: id) { c.resume(returning: KernAntwort(zeile: z)) }
            case .ereignis(let kanal, let z):
                ereignisse[kanal, default: 0] += 1
                ereignis(kanal, z)
            case .unbekannt:
                break
            }
        }
    }

    private func ereignis(_ kanal: String, _ zeile: Data) {
        switch kanal {
        case "awb:model":
            if let m = try? Nutzlast.lesen(ModellNutzlast.self, aus: zeile) { modell = m }
        case "awb:session":
            sitzung = try? Nutzlast.lesen(SitzungsNutzlast.self, aus: zeile)
        case "awb:layout":
            if let l = try? Nutzlast.lesen(LageNutzlast.self, aus: zeile) {
                lage = l
                aufLage?(l)
            }
        case "awb:output":
            if let a = try? Nutzlast.lesen(AusgabeNutzlast.self, aus: zeile) {
                aufAusgabe?(a.paneId, a.bytes)
            }
        case "awb:kanal":
            if let obj = try? JSONSerialization.jsonObject(with: zeile) as? [String: Any] {
                kernSteuerkanal = obj["pfad"] as? String ?? ""
            }
        case "awb:umbenennen":
            if let u = try? Nutzlast.lesen(UmbenennenNutzlast.self, aus: zeile), !u.id.isEmpty {
                aufUmbenennen?(u)
            }
        case "awb:meldung":
            if let m = try? Nutzlast.lesen(MeldungNutzlast.self, aus: zeile), !m.text.isEmpty {
                meldung = m.text
                meldungBis = Date().addingTimeInterval(Double(max(1000, m.dauerMs)) / 1000)
            }
        case "awb:ein-daten-neu":
            aufEinstellungenNeu?(zeile)
        case "awb:sitz-daten-neu":
            aufSitzungNeu?(zeile)
        case "awb:sitz-startfehler":
            aufStartfehler?(zeile)
        case "awb:datei-geaendert":
            if let obj = try? JSONSerialization.jsonObject(with: zeile) as? [String: Any] {
                aufDateiGeaendert?(obj["name"] as? String ?? "", obj["pfad"] as? String ?? "")
            }
        case "awb:freigaben":
            if let f = try? Nutzlast.lesen(FreigabenNutzlast.self, aus: zeile), f != freigaben { freigaben = f }
        case "awb:aufgaben":
            if let n = AufgabenNutzlast.lesen(zeile), n != aufgaben { aufgaben = n }
            if let w = WeltenNutzlast.lesen(zeile), w != welten { welten = w }
        case "awb:chat-stand-neu":
            if let n = ChatStandNachricht.lesen(zeile) { aufChatStand?(n) }
        case "awb:ordner":
            if let o = try? Nutzlast.lesen(OrdnerNutzlast.self, aus: zeile) { aufOrdner?(o) }
        case "awb:aktivitaet":
            if let a = try? Nutzlast.lesen(AktivitaetNutzlast.self, aus: zeile) { aufAktivitaet?(a) }
        case "awb:suche":
            if let s = try? Nutzlast.lesen(SucheNutzlast.self, aus: zeile) { aufSuche?(s) }
        case "awb:ergebnis":
            if let e = try? Nutzlast.lesen(ErgebnisNutzlast.self, aus: zeile), !e.path.isEmpty { aufErgebnis?(e) }
        case "awb:thema-neu":
            themaSetzen(ThemaNutzlast.lesen(zeile))
        default:
            break
        }
    }

    // --- Die Wege hinaus, wortgleich zu preload.ts ---------------------------

    /// Zaehler der gesendeten Bedienungen je Aktion -- fuer `awbmac-ctl ui` und die Fehlersuche.
    private(set) var gesendet: [String: Int] = [:]

    /// `ipcRenderer.send` -- feuern und vergessen.
    func send(_ kanal: String, _ args: [Any]) {
        if kanal == "awb:bedienung", let a = (args.first as? [String: Any])?["aktion"] as? String { gesendet[a, default: 0] += 1 }
        if kanal == "awb:chat-bereit" { gesendet["chat-bereit", default: 0] += 1 }
        guard fd >= 0 else { gesendet["verworfen", default: 0] += 1; return }
        UnixSocket.schreiben(fd, KernAnfrage.send(kanal: kanal, args: args))
    }

    // MARK: Das Thema (Farben der Zustandspunkte)

    /// Was der Kern zuletzt ueber Farben und Erscheinungsbild gesagt hat.
    private(set) var thema = ThemaNutzlast()

    /// Einmal nachfragen (`awb:thema-daten`, main.ts) -- der Kanal
    /// `awb:thema-neu` meldet nur AENDERUNGEN.
    func themaHolen() async {
        let a = await invoke("awb:thema-daten")
        guard let daten = a.wertJSON else { return }
        themaSetzen(ThemaNutzlast.lesen(daten))
    }

    /// Ein neues Thema ist da -- das Fenster richtet sein Erscheinungsbild danach.
    var aufThema: ((ThemaNutzlast) -> Void)?

    private func themaSetzen(_ t: ThemaNutzlast) {
        guard t.da, t != thema else { return }
        thema = t
        Zustandsfarben.aktuell.uebernehmen(t)
        aufThema?(t)
    }

    /// `ipcRenderer.invoke` -- wartet auf die Antwort mit derselben Kennung.
    func invoke(_ kanal: String, _ args: [Any] = []) async -> KernAntwort {
        guard fd >= 0 else {
            return KernAntwort(zeile: Data("{\"ok\":false,\"error\":\"nicht verbunden\"}".utf8))
        }
        let id = naechsteId
        naechsteId += 1
        return await withCheckedContinuation { c in
            wartend[id] = c
            UnixSocket.schreiben(fd, KernAnfrage.invoke(id: id, kanal: kanal, args: args))
        }
    }

    func bedienung(_ aktion: String, _ wert: Any) {
        send("awb:bedienung", [["aktion": aktion, "wert": wert]])
    }

    func waehlen(_ sitzungsId: String) {
        bedienung("select", sitzungsId)
    }

    func paneZeigen(_ paneId: String) {
        bedienung("show-pane", paneId)
    }

    /// Mehrere Panes nebeneinander auf die Buehne (`show-tab`, main.ts
    /// `tabZeigen`) -- der Weg des Umschalters „Worker“.
    func tabZeigen(_ paneIds: [String]) {
        guard !paneIds.isEmpty else { return }
        bedienung("show-tab", paneIds)
    }

    /// DIE VON HAND GEZOGENE REIHENFOLGE DER ZEILEN (`order`, uistate.ts).
    /// Eine flache Liste ueber alle Projekte, in der die Zeilen eines Projekts
    /// vollstaendig hintereinander stehen -- dieselbe Zusage wie
    /// `flacheReihenfolge` in renderer.ts, ohne die die Gruppierung den Zug
    /// wieder einebnen wuerde.
    func reihenfolge(_ kennungen: [String]) {
        bedienung("order", kennungen)
    }

    /// DIE VON HAND GEZOGENE REIHENFOLGE DER PROJEKTE (`projekt-order`,
    /// uistate.ts `projektReihenfolge`): ein Ordner je Eintrag. Der Kern merkt
    /// sie, damit die Electron-Fassung dieselbe Reihenfolge zeichnet.
    func projektReihenfolge(_ ordner: [String]) {
        bedienung("projekt-order", ordner)
    }

    /// Welcher Worker-Tab gewaehlt ist (`worker-tab`, uistate.ts `workerTab`) --
    /// derselbe Merker wie in der Electron-Fassung (renderer.ts `tabZeigen`).
    func workerTab(_ i: Int) {
        bedienung("worker-tab", max(0, i))
    }

    /// Die Wahl des Umschalters je Sitzung merken (`flaeche-modus`, uistate.ts
    /// `flaecheSitzung`) -- dieselbe Ablage wie die Electron-Fassung.
    func flaecheModus(_ sitzungsId: String, _ modus: String) {
        bedienung("flaeche-modus", ["id": sitzungsId, "modus": modus])
    }

    /// Ein Punkt des Sitzungsmenues -- derselbe Weg wie das Popup der
    /// Electron-Fassung und der Steuerbefehl `sitzung-menue-punkt` (main.ts).
    /// `bestaetigt`: die Rueckfrage vor dem Loeschen hat das Fenster schon gestellt.
    func menuePunkt(_ sitzungsId: String, _ punkt: String, echt: Bool, bestaetigt: Bool = false) {
        bedienung("sitzung-menue-punkt", ["id": sitzungsId, "punkt": punkt, "echt": echt, "bestaetigt": bestaetigt])
    }

    /// Der neue Name zurueck an den Kern (`awb:sitzung-umbenennen` ruft `wb-state touch`).
    func umbenennen(_ sitzungsId: String, _ name: String) async -> (ok: Bool, meldung: String) {
        let a = await invoke("awb:sitzung-umbenennen", [sitzungsId, name])
        var text = a.fehler ?? ""
        if let w = a.wertJSON, let obj = try? JSONSerialization.jsonObject(with: w) as? [String: Any] {
            text = obj["meldung"] as? String ?? text
            let ok = obj["ok"] as? Bool ?? false
            if !text.isEmpty { meldung = text; meldungBis = Date().addingTimeInterval(4) }
            return (ok, text)
        }
        if !text.isEmpty { meldung = text; meldungBis = Date().addingTimeInterval(4) }
        return (a.ok, text)
    }

    /// Eine Meldung ins Fenster, wie sie der Kern selbst schickt -- fuer
    /// Handlungen, die der Mantel selbst ausfuehrt (der Plusknopf der Leiste).
    func melden(_ text: String) {
        guard !text.isEmpty else { return }
        meldung = text
        meldungBis = Date().addingTimeInterval(4)
    }

    /// Beendete Sitzungen zeigen oder nicht (`showStopped`, A12) -- der Kern filtert.
    func beendeteZeigen(_ an: Bool) {
        bedienung("show-stopped", an)
    }

    /// Die Sortierung der Leiste (`ui.sort`: recent | folder | name) -- ueber
    /// denselben Kanal wie das Einstellungsfenster.
    func sortierung(_ schluessel: String) {
        Task { _ = await invoke("awb:ein-ui", ["sort", schluessel]) }
    }

    /// Die Buehne des Mantels -- MIT Vorgabe (`awb:mantel-flaeche`), damit der
    /// versteckte Renderer des Kerns nicht daneben seine eigene meldet.
    func flaeche(cols: Int, rows: Int) {
        Task { _ = await invoke("awb:mantel-flaeche", [cols, rows]) }
    }

    /// Tastendruecke des Menschen -- derselbe Weg wie `awb:input` aus dem Renderer.
    func eingabe(pane: String, bytes: Data) {
        send("awb:input", [["paneId": pane, "base64": bytes.base64EncodedString()]])
    }

    /// Ueber einen Antrag entscheiden -- derselbe Weg wie die Electron-Leiste
    /// (`freigaben-entscheiden`, ruft `wb-decide`). Der Kern liest die Ablage
    /// danach neu und schickt `awb:freigaben`; erst das raeumt die Zeile ab.
    func antragEntscheiden(pfad: String, annehmen: Bool, grund: String) {
        bedienung("freigaben-entscheiden", ["path": pfad, "action": annehmen ? "approve" : "reject", "reason": grund])
    }

    /// Ueber einen angehaltenen Befehl der Rueckfrage-Stufe entscheiden
    /// (`muster-entscheiden`). `echt` sagt, dass ein Mensch im Fenster
    /// geklickt hat -- nur dann erteilt der Kern; Ablehnen darf jeder.
    func musterEntscheiden(schluessel: String, annehmen: Bool, grund: String, echt: Bool) {
        bedienung("muster-entscheiden", ["schluessel": schluessel, "action": annehmen ? "approve" : "reject", "reason": grund, "echt": echt])
    }

    /// Der Hinweis ist gelesen (Klick im Fuss, Statusfuss.swift).
    func meldungWeg() {
        meldungBis = .distantPast
    }

    /// Eine ferne Maschine abrufen oder pausieren (`maschine-laden`, schreibt
    /// `remoteMachinesPausiert` ueber denselben Weg wie die Seite „Maschinen“).
    func maschineLaden(_ maschine: String, _ laden: Bool) {
        bedienung("maschine-laden", ["maschine": maschine, "laden": laden])
    }

    var gewaehlteSitzung: SitzungsEintrag? {
        modell.sessions.first { $0.id == modell.selected }
    }

    // MARK: Die Chat-Buehne (Auftrag 3.2) -- die Kanaele aus preload.ts `awbChat`

    /// Der Wahrheitswert einer Antwort (`{ok, value: true|false}`).
    private func jaNein(_ a: KernAntwort) -> Bool {
        guard a.ok, let w = a.wertJSON else { return false }
        return String(decoding: w, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    }

    /// Der Stand der Sitzung auf der Buehne ab diesem Takt (`awb:chat-daten`, 0 = alles).
    /// Welche Sitzung, sagt der Kern (`chatIdVon`): die auf der Buehne.
    func chatDaten(seit: Int) async -> ChatStandNachricht? {
        let a = await invoke("awb:chat-daten", [seit])
        guard a.ok, let w = a.wertJSON else { return nil }
        return ChatStandNachricht.lesen(w)
    }

    func chatSenden(_ text: String) async -> Bool { jaNein(await invoke("awb:chat-senden", [text])) }

    func chatFreigabe(_ anfrageId: String, erlauben: Bool) async -> Bool { jaNein(await invoke("awb:chat-freigabe", [anfrageId, erlauben])) }

    func chatNeustart() async -> Bool { jaNein(await invoke("awb:chat-neustart")) }

    func chatModus(_ modus: String) async -> Bool { jaNein(await invoke("awb:chat-modus", [modus])) }

    func chatHalt() async -> Bool { jaNein(await invoke("awb:chat-halt")) }

    /// Die Dateiliste des Projektordners fuer das `@` (`awb:chat-dateien`): EINMAL
    /// je Sitzung geholt, im Fenster gefiltert (Befund B1).
    func chatDateien() async -> (quelle: String, dateien: [Dateivorschlag]) {
        let a = await invoke("awb:chat-dateien")
        guard a.ok, let w = a.wertJSON, let o = try? JSONSerialization.jsonObject(with: w) as? [String: Any] else { return ("git", []) }
        let liste = (o["dateien"] as? [[String: Any]] ?? []).compactMap { d -> Dateivorschlag? in
            guard let pfad = d["pfad"] as? String else { return nil }
            return Dateivorschlag(pfad: pfad, ordner: d["ordner"] as? Bool ?? false)
        }
        return (o["quelle"] as? String ?? "git", liste)
    }

    /// Die Buehne hat gezeichnet (`awb:chat-bereit`): darauf wartet `zeigeAufBuehne` im Kern.
    func chatBereit(_ id: String) { send("awb:chat-bereit", [id]) }

    /// Eine Chat-Sitzung waehlen: der ECHTE Klick legt sie auf die Buehne
    /// (`chat-zeigen`), ein unechter (Steuerkanal, kopflos) startet sie nur
    /// (`chat-bauen`) -- dieselbe Zweiteilung wie im Renderer (`isTrusted`).
    func chatZeigen(_ id: String, echt: Bool) { bedienung(echt ? "chat-zeigen" : "chat-bauen", id) }

    /// Einen Worker der Werkstatt dieser Chat-Sitzung auf die Buehne (`chat-worker`, `<chatId>|<paneId>`).
    func chatWorkerZeigen(chat: String, pane: String) { bedienung("chat-worker", "\(chat)|\(pane)") }

    // MARK: Ordner, Aktivitaet, Protokolle, Suche (Auftraege 3.5 und 3.6)

    /// EINEN Ordner anfordern; leer heisst „die Wurzel", die der Kern bestimmt
    /// (`ordnerWurzel`: der Projektordner der gewaehlten Sitzung, sonst das
    /// Eigenheim). Die Antwort kommt als `awb:ordner`.
    func ordnerListe(_ pfad: String = "") { bedienung("ordner-liste", pfad) }

    /// Einen Pfad im Programm des Menschen oeffnen (`shell.openPath` im Kern).
    /// Geprueft wird dort: unter der Wurzel und nicht ausgeschlossen.
    func ordnerOeffnen(_ pfad: String) { bedienung("ordner-oeffnen", pfad) }

    /// Die Aktivitaetsliste anfordern; die Antwort kommt als `awb:aktivitaet`.
    func aktivitaetLesen() { bedienung("aktivitaet-lesen", "") }

    /// Die Inhaltssuche unter `pfad`; die Antwort kommt als `awb:suche` und
    /// traegt die Anfrage mit, damit eine ueberholte Antwort auffaellt.
    func sucheLesen(_ query: String, pfad: String) {
        bedienung("suche-lesen", ["query": query, "pfad": pfad])
    }

    /// Der erste Klick auf einen Aktivitaetseintrag: sein Inhalt
    /// (`awb:aktivitaet-read`). Gelesen wird nur, was der Kern selbst zuletzt
    /// gemeldet hat -- die Oberflaeche bestimmt nicht, welche Datei er liest.
    func aktivitaetInhalt(_ pfad: String) async -> (ok: Bool, inhalt: String, fehler: String) {
        let a = await invoke("awb:aktivitaet-read", [pfad])
        guard let w = brueckenWert(a) else { return (false, "", brueckenFehler(a)) }
        return (true, w["content"] as? String ?? "", "")
    }

    /// Der zweite Klick auf eine Aenderung: die beiden Fassungen (`awb:aktivitaet-diff`).
    func aktivitaetDiff(_ pfad: String) async -> (ok: Bool, alt: String, neu: String, fehler: String) {
        let a = await invoke("awb:aktivitaet-diff", [pfad])
        guard let w = brueckenWert(a) else { return (false, "", "", brueckenFehler(a)) }
        return (true, w["original"] as? String ?? "", w["modified"] as? String ?? "", "")
    }

    /// Der zweite Klick auf ein Ergebnis: Auftrag und Ergebnis (`awb:aktivitaet-auftrag`).
    func aktivitaetAuftrag(_ pfad: String) async -> (ok: Bool, auftrag: String, ergebnis: String, fehler: String) {
        let a = await invoke("awb:aktivitaet-auftrag", [pfad])
        guard let w = brueckenWert(a) else { return (false, "", "", brueckenFehler(a)) }
        return (true, w["auftrag"] as? String ?? "", w["ergebnis"] as? String ?? "", "")
    }

    /// Die Protokoll-Liste aus den Einstellungen (`awb:protokolle-list`).
    func protokolleListe() async -> (liste: [ProtokollEintrag], fehler: String) {
        let a = await invoke("awb:protokolle-list")
        guard a.ok, let w = a.wertJSON,
              let obj = try? JSONSerialization.jsonObject(with: w) as? [String: Any] else {
            return ([], a.fehler ?? "keine Antwort")
        }
        if obj["ok"] as? Bool == false { return ([], obj["error"] as? String ?? "abgelehnt") }
        guard let roh = obj["value"], let d = try? JSONSerialization.data(withJSONObject: roh),
              let liste = try? JSONDecoder().decode([ProtokollEintrag].self, from: d) else {
            return ([], "unlesbare Liste")
        }
        return (liste, "")
    }

    /// Eine Protokolldatei lesen (`awb:protokolle-read`). Nur ein Pfad AUS der
    /// Liste ist erlaubt; das prueft der Kern, nicht die Oberflaeche.
    func protokollLesen(_ pfad: String) async -> (ok: Bool, inhalt: String, fehler: String) {
        let a = await invoke("awb:protokolle-read", [pfad])
        guard a.ok, let w = a.wertJSON,
              let obj = try? JSONSerialization.jsonObject(with: w) as? [String: Any] else {
            return (false, "", a.fehler ?? "keine Antwort")
        }
        if obj["ok"] as? Bool == false { return (false, "", obj["error"] as? String ?? "abgelehnt") }
        return (true, obj["value"] as? String ?? "", "")
    }

    /// Welche Kandidaten es wirklich gibt (`awb:chat-pfade`). `pane` nennt einen
    /// Terminal-Pane; leer heisst „die Chat-Sitzung auf der Buehne". Der Kern
    /// merkt sich, was er gefunden hat -- nur das laesst sich danach oeffnen.
    func pfadePruefen(pane: String, kandidaten: [String]) async -> [PfadTreffer] {
        guard !kandidaten.isEmpty else { return [] }
        let a = await invoke("awb:chat-pfade", [pane, kandidaten])
        guard a.ok, let w = a.wertJSON,
              let obj = try? JSONSerialization.jsonObject(with: w) as? [String: Any],
              obj["ok"] as? Bool != false,
              let liste = obj["value"] as? [[String: Any]] else { return [] }
        return liste.compactMap { t in
            guard let abs = t["abs"] as? String, let kandidat = t["kandidat"] as? String else { return nil }
            return PfadTreffer(kandidat: kandidat, abs: abs, art: t["art"] as? String ?? "datei",
                               zeile: t["zeile"] as? Int ?? 0, spalte: t["spalte"] as? Int ?? 0)
        }
    }

    /// Was ein Klick oeffnen soll (`awb:chat-pfad-oeffnen`): der Kern entscheidet
    /// Text, Binaer oder Ordner und liest den Text selbst; Binaeres schickt er
    /// gleich an das System.
    func pfadOeffnen(_ abs: String) async -> (art: String, name: String, inhalt: String, fehler: String) {
        let a = await invoke("awb:chat-pfad-oeffnen", [abs])
        guard let w = brueckenWert(a) else { return ("", "", "", brueckenFehler(a)) }
        return (w["art"] as? String ?? "", w["name"] as? String ?? "", w["content"] as? String ?? "", "")
    }

    /// Eine Ergebnisdatei im Programm des Menschen oeffnen (`ergebnis-oeffnen`).
    func ergebnisOeffnen(_ pfad: String) { bedienung("ergebnis-oeffnen", pfad) }

    /// Der Wert einer Bruecken-Antwort (`{ok:true,value:{…}}`) als Verzeichnis,
    /// oder `nil` bei jedem Fehler auf einer der beiden Ebenen.
    private func brueckenWert(_ a: KernAntwort) -> [String: Any]? {
        guard a.ok, let w = a.wertJSON,
              let obj = try? JSONSerialization.jsonObject(with: w) as? [String: Any],
              obj["ok"] as? Bool != false else { return nil }
        return obj["value"] as? [String: Any]
    }

    private func brueckenFehler(_ a: KernAntwort) -> String {
        if let w = a.wertJSON, let obj = try? JSONSerialization.jsonObject(with: w) as? [String: Any],
           let e = obj["error"] as? String { return e }
        return a.fehler ?? "keine Antwort"
    }
}
