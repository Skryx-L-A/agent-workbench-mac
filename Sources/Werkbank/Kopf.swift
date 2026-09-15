// Der Kopf ueber dem Inhalt (Auftrag 2.2, mac/PLAN.md): Name gross, Herkunft
// klein darunter, rechts die Pille „N laufen“, der Umschalter Orchestrator |
// Worker und das Zahnrad. Im Zustand Agents stehen statt Pille und Umschalter
// Zaehler und Pausenschalter der Welt (Auftrag agentsux Nr. 1).
//
// WO ER SITZT: in der Symbolleiste im Fenstertitel (plattformen.md, macOS:
// „Symbolleiste im Titel, Inhalt darunter“). Der Name ist der Fenstertitel, die
// Herkunft der Untertitel -- genau das Paar, das der Mac fuer „gross, klein
// darunter“ vorsieht -- und die Symbolleiste traegt Pille, Umschalter und
// Zahnrad. Ein zweiter Kopf im Inhalt waere derselbe Streifen noch einmal.
// Die Kopfhoehe ist damit in jeder Sitzung dieselbe: die Hoehe der
// Symbolleiste, gemessen als Fensterhoehe minus Inhaltsflaeche (`hoehe`).
//
// WAS DER UMSCHALTER HERVORHEBT, FOLGT DER BUEHNE (Lehre aus kopfzeile,
// 05.09.; renderer.ts `flaechenmodus`): angezeigt wird, was der Kern als Lage
// wirklich gezeichnet hat -- nur der Orchestrator-Pane heisst Orchestrator,
// alles andere Worker. Die gemerkte Wahl (`ui.flaecheSitzung`, je Sitzung im
// Kern) sagt nur, womit eine Sitzung AUFGEHT, und wird beim Wechsel einmal
// angewandt.
import AppKit
import SwiftUI
import WerkbankProtokoll

@MainActor
final class Kopf: NSObject, NSPopoverDelegate {
    unowned let fenster: Fenster
    let kern: KernVerbindung
    let umschalter = NSSegmentedControl()
    /// Der Umschalter `Code | Agents` (Auftrag macagents): WELCHE Buehne steht
    /// -- die Sitzung mit Terminal, Gespraech und Editor, oder die Welten der
    /// Agents (seit Auftrag agentsui Nr. 6). Er steht LINKS von Pille und Orchestrator |
    /// Worker, weil er die groessere Wahl ist: die beiden daneben ordnen die
    /// Code-Buehne und sagen im Zustand Agents nichts mehr.
    let flaecheUmschalter = NSSegmentedControl()
    let pille: NSHostingView<PilleAnsicht>
    /// Zaehler und Pausenschalter der gewaehlten Welt (WeltenBlatt.swift): nur im Zustand Agents sichtbar.
    let weltenZaehler: NSHostingView<WeltenZaehler>
    let weltenPause: NSHostingView<WeltenWeltPause>
    private var popover: NSPopover?
    /// Fuer welche Sitzung die gemerkte Wahl schon angewandt ist.
    private var wahlAngewandtFuer = ""
    /// Fuer welche Sitzung die Wahl noch DURCHGESETZT wird: der Kern meldet
    /// `selected` schon VOR dem Anhaengen (main.ts `sessionWaehlen`: `ui.set`,
    /// dann `attachTmux`), und sein eigener Wurf nach dem Anhaengen (F1, dann
    /// `paneZeigen` des aktiven Panes) kommt deshalb NACH unserem show-tab an
    /// -- gemessen 06.09. (app.log): erst die Tab-Lage mit drei Panes, danach
    /// viermal der Orchestrator allein. Also wird die Wahl in den ersten zwei
    /// Sekunden nach dem Wechsel an jeder Lage geprueft und bei Widerspruch
    /// noch einmal gesetzt (hoechstens drei Mal); jede Handlung des Menschen
    /// beendet das sofort.
    private var wahlOffenFuer = ""
    private var wahlVersuche = 0
    private var wahlSeit = Date.distantPast
    private static let wahlFrist: TimeInterval = 2.0

    init(fenster: Fenster, kern: KernVerbindung) {
        self.fenster = fenster
        self.kern = kern
        let oberflaeche = fenster.oberflaeche
        pille = NSHostingView(rootView: PilleAnsicht(kern: kern, offen: { oberflaeche.workerListeOffen }, klick: {}))
        weltenZaehler = NSHostingView(rootView: WeltenZaehler(kern: kern, zustand: fenster.weltenZustand))
        weltenZaehler.sizingOptions = [.intrinsicContentSize]
        weltenPause = NSHostingView(rootView: WeltenWeltPause(kern: kern, zustand: fenster.weltenZustand))
        weltenPause.sizingOptions = [.intrinsicContentSize]
        super.init()
        pille.rootView = PilleAnsicht(kern: kern, offen: { oberflaeche.workerListeOffen }, klick: { [weak self] in self?.workerListeUmschalten() })
        pille.sizingOptions = [.intrinsicContentSize]
        pille.setAccessibilityIdentifier("pille")
        pille.setAccessibilityLabel("Worker: keine Sitzung gewählt")
        pille.setAccessibilityRole(.button)

        umschalter.segmentStyle = .automatic
        umschalter.trackingMode = .selectOne
        umschalter.segmentCount = 2
        umschalter.setLabel("Orchestrator", forSegment: 0)
        umschalter.setLabel("Worker", forSegment: 1)
        umschalter.setToolTip("Den Orchestrator zeigen (⌘1)", forSegment: 0)
        umschalter.setToolTip("Alle Worker der Sitzung zeigen (⌘2)", forSegment: 1)
        umschalter.selectedSegment = 0
        umschalter.target = self
        umschalter.action = #selector(umschalterGeklickt(_:))
        umschalter.setAccessibilityLabel("Was die Fläche zeigt")

        flaecheUmschalter.segmentStyle = .automatic
        flaecheUmschalter.trackingMode = .selectOne
        flaecheUmschalter.segmentCount = 2
        flaecheUmschalter.setLabel("Code", forSegment: 0)
        flaecheUmschalter.setLabel("Agents", forSegment: 1)
        flaecheUmschalter.setToolTip("Die gewählte Sitzung zeigen (⌥⌘A)", forSegment: 0)
        flaecheUmschalter.setToolTip("Die Welten der Agents zeigen (⌥⌘A)", forSegment: 1)
        flaecheUmschalter.selectedSegment = 0
        flaecheUmschalter.target = self
        flaecheUmschalter.action = #selector(flaecheGeklickt(_:))
        flaecheUmschalter.setAccessibilityLabel("Welche Bühne steht")
    }

    // MARK: Buehne und Wahl

    /// Was die Buehne zeigt, aus der Lage des Kerns -- oder nil, wenn die Lage
    /// nicht zur gewaehlten Sitzung gehoert (gerade gewechselt, noch nichts gezeichnet).
    var buehne: Ansicht? {
        guard let s = kern.gewaehlteSitzung, let l = kern.lage else { return nil }
        var gezeichnet = l.panes.map(\.paneId).filter { !$0.isEmpty }
        if gezeichnet.isEmpty, !l.aktiv.isEmpty { gezeichnet = [l.aktiv] }
        guard !gezeichnet.isEmpty else { return nil }
        let eigene = s.workerPanesMitSubagenten.union(s.orchestratorPane.isEmpty ? [] : [s.orchestratorPane])
        guard gezeichnet.contains(where: { eigene.contains($0) }) else { return nil }
        let nurOrchestrator = gezeichnet.count == 1 && !s.orchestratorPane.isEmpty && gezeichnet[0] == s.orchestratorPane
        return nurOrchestrator ? .orchestrator : .worker
    }

    /// Was der Umschalter zeigt: die Buehne, sonst die zuletzt gezeichnete
    /// Buehne, sonst die Wahl. Zwischen `show-pane` und der naechsten Lage des
    /// Kerns ist die Buehne fuer einen Takt nicht zuzuordnen (gemessen 06.09.,
    /// test-mac-skelett Zusage 8: der Umschalter sprang auf die Wahl „Worker“,
    /// obwohl weiter der Orchestrator stand). Die letzte Buehne traegt darueber hinweg.
    var angezeigt: Ansicht {
        if let b = buehne { letzteBuehne = b; return b }
        return letzteBuehne ?? fenster.oberflaeche.ansicht
    }
    private var letzteBuehne: Ansicht?

    /// Die gemerkte Wahl einer Sitzung (`ui.flaecheSitzung`); ohne Eintrag wie
    /// die Electron-Fassung: MIT Workern auf „Worker" (Kacheln), ohne auf dem
    /// Orchestrator (Auftrag 2.3, Rest (a) aus 2.2).
    func gemerkteWahl(_ id: String) -> Ansicht {
        switch kern.modell.ui.flaecheSitzung[id] {
        case "worker": return .worker
        case "orchestrator": return .orchestrator
        default:
            let s = kern.modell.sessions.first { $0.id == id }
            return (s?.workerPanes.isEmpty == false) ? .worker : .orchestrator
        }
    }

    /// Der gewaehlte Worker-Tab, auf die Zahl der Tabs beschnitten (renderer.ts).
    func gewaehlterTab(_ s: SitzungsEintrag) -> Int {
        let tabs = max(1, s.tabs(perTab: kern.modell.capacity.perTab))
        return min(max(0, kern.modell.ui.workerTab), tabs - 1)
    }

    /// Die Panes des gewaehlten Tabs -- was der Umschalter „Worker" und der
    /// Rueckweg aus dem Zoom auf die Buehne legen.
    func panesDesTabs(_ s: SitzungsEintrag) -> [String] {
        s.panesImTab(gewaehlterTab(s), perTab: kern.modell.capacity.perTab)
    }

    /// Ein Tab im Streifen: merken (`worker-tab`) und seine Panes zeigen.
    func tabWaehlen(_ i: Int) {
        guard let s = kern.gewaehlteSitzung else { return }
        wahlOffenFuer = ""
        let tabs = max(1, s.tabs(perTab: kern.modell.capacity.perTab))
        let nr = min(max(0, i), tabs - 1)
        kern.workerTab(nr)
        fenster.oberflaeche.ansicht = .worker
        let panes = s.panesImTab(nr, perTab: kern.modell.capacity.perTab)
        if !panes.isEmpty { kern.tabZeigen(panes) }
    }

    /// Aus der Kachel heraus: diesen Pane allein (`show-pane`), wie der
    /// Zoom-Knopf der Electron-Kopfzeile (renderer.ts `aufZoom`).
    func kachelZoomen(_ pane: String) {
        guard !pane.isEmpty else { return }
        wahlOffenFuer = ""
        kern.paneZeigen(pane)
    }

    /// Aus dem Zoom zurueck zu allen Kacheln des gewaehlten Tabs (`show-tab`).
    func kachelnZurueck() {
        guard let s = kern.gewaehlteSitzung else { return }
        wahlOffenFuer = ""
        let panes = panesDesTabs(s)
        if !panes.isEmpty { kern.tabZeigen(panes) } else if !s.orchestratorPane.isEmpty { kern.paneZeigen(s.orchestratorPane) }
    }

    /// Der Menuepunkt ⌘↩: gezoomt zurueck zu allen, sonst die Kachel mit der Tastatur allein.
    func kachelZoomUmschalten() {
        if fenster.terminal.lageArt == "pane" { kachelnZurueck() } else { kachelZoomen(fenster.terminal.gezeigterPane) }
    }

    /// Die Marken des Tab-Streifens (renderer.ts `zeichneStreifen`), ab zwei Tabs.
    func tabMarken() -> [TabMarke] {
        guard let s = kern.gewaehlteSitzung else { return [] }
        let perTab = kern.modell.capacity.perTab
        let tabs = s.tabs(perTab: perTab)
        guard tabs >= 2 else { return [] }
        return (0..<tabs).compactMap { i in
            let drin = s.workerImTab(i, perTab: perTab)
            if drin.isEmpty && i > 0 { return nil }
            return TabMarke(nr: i, anzahl: drin.count, farbe: TabMarke.farbe(fuer: drin), namen: drin.map(\.name))
        }
    }

    /// Ob der Streifen steht: ab zwei Tabs, und nur, solange Worker auf der
    /// Buehne liegen -- also nie, solange das Agents-Blatt die Buehne hat.
    var streifenDa: Bool { fenster.oberflaeche.modus == .code && buehne == .worker && !tabMarken().isEmpty }

    /// Die Sitzung hat gewechselt: die gemerkte Wahl einmal anwenden.
    func sitzungGewechselt(_ s: SitzungsEintrag?) {
        workerListeSchliessen()
        letzteBuehne = nil
        guard let s else { wahlAngewandtFuer = ""; wahlOffenFuer = ""; return }
        guard wahlAngewandtFuer != s.id else { return }
        wahlAngewandtFuer = s.id
        fenster.oberflaeche.ansicht = gemerkteWahl(s.id)
        wahlOffenFuer = s.id
        wahlVersuche = 0
        wahlSeit = Date()
        ansichtAnwenden()
    }

    /// Eine Lage ist da: steht die Wahl der eben gewaehlten Sitzung noch aus,
    /// wird sie gegen die Lage geprueft und, wenn der Kern etwas anderes
    /// gezeichnet hat (sein eigener Wurf nach dem Anhaengen), noch einmal gesetzt.
    func lageAngekommen(_ l: LageNutzlast) {
        guard let s = kern.gewaehlteSitzung, wahlOffenFuer == s.id, buehne != nil else { return }
        if Date().timeIntervalSince(wahlSeit) > Self.wahlFrist || wahlVersuche >= 3 { wahlOffenFuer = ""; return }
        let gezeichnet = Set(l.panes.map(\.paneId).filter { !$0.isEmpty })
        let ziel: Set<String>
        switch fenster.oberflaeche.ansicht {
        case .worker:
            let panes = panesDesTabs(s)
            ziel = panes.isEmpty ? [s.orchestratorPane] : Set(panes)
        case .orchestrator:
            ziel = [s.orchestratorPane]
        }
        guard gezeichnet != ziel else { return }
        wahlVersuche += 1
        ansichtAnwenden()
    }

    /// Der Mensch (oder ein Klick ueber den Steuerkanal) hat gewaehlt: merken
    /// -- hier und im Kern -- und die Buehne danach richten.
    func ansichtSetzen(_ neu: Ansicht) {
        wahlOffenFuer = ""
        fenster.oberflaeche.ansicht = neu
        if let s = kern.gewaehlteSitzung { kern.flaecheModus(s.id, neu.rawValue) }
        ansichtAnwenden()
        nachziehen()
    }

    /// Orchestrator = dessen Pane; Worker = alle Worker-Panes der Sitzung
    /// (`show-tab`). Ohne Worker-Pane bleibt der Orchestrator: eine leere Buehne
    /// waere schlimmer als die falsche Wahl, und der Umschalter zeigt ohnehin,
    /// was zu sehen ist.
    func ansichtAnwenden() {
        guard let s = kern.gewaehlteSitzung, fenster.optionen.terminal == .strom else { return }
        switch fenster.oberflaeche.ansicht {
        case .orchestrator:
            if !s.orchestratorPane.isEmpty { kern.paneZeigen(s.orchestratorPane) }
        case .worker:
            // Die Panes des gewaehlten Tabs (`capacity.perTab`, `ui.workerTab`),
            // nicht mehr alle Worker: mehr als ein Tab voll waere sonst auf
            // einer Buehne, die dafuer zu klein ist (renderer.ts `tabZeigen`).
            let panes = panesDesTabs(s)
            if !panes.isEmpty {
                kern.tabZeigen(panes)
            } else if !s.orchestratorPane.isEmpty {
                kern.paneZeigen(s.orchestratorPane)
            }
        }
    }

    /// Ein bestimmter Worker-Pane (Klick in der Liste): die Wahl steht auf
    /// Worker, gezeigt wird genau dieser Pane.
    func workerPaneZeigen(_ pane: String) {
        wahlOffenFuer = ""
        fenster.oberflaeche.ansicht = .worker
        // Der Tab, in dem der Pane liegt, wird mitgemerkt: der Rueckweg aus dem
        // Zoom landet dann auf seinen Nachbarn (renderer.ts `workerZeile.tab`).
        if let s = kern.gewaehlteSitzung {
            let perTab = max(1, kern.modell.capacity.perTab)
            if let i = s.flacheWorker.firstIndex(where: { $0.paneId == pane }) { kern.workerTab(i / perTab) }
        }
        kern.paneZeigen(pane)
    }

    @objc private func umschalterGeklickt(_ sender: NSSegmentedControl) {
        ansichtSetzen(sender.selectedSegment == 0 ? .orchestrator : .worker)
    }

    @objc private func flaecheGeklickt(_ sender: NSSegmentedControl) {
        fenster.modusSetzen(sender.selectedSegment == 0 ? .code : .agents)
    }

    // MARK: Titel und Umschalter nachziehen (im Takt des Fensters)

    func nachziehen() {
        let s = kern.gewaehlteSitzung
        var titel = s.map { $0.name.isEmpty ? $0.projekt : $0.name } ?? "Werkbank"
        var herkunft = s?.herkunft(eigene: kern.modell.machine) ?? ""
        // LIEGT EIN GESPRAECH AUF DER BUEHNE, beschreibt der Kopf es (renderer.ts
        // `zeichneKopf`, Befund 6 vom 04.09.): Name der Chat-Sitzung, darunter
        // Modell und Ordner -- keine Maschine, ein Gespraech laeuft immer hier.
        if let c = kern.modell.gezeigterChat {
            titel = c.name.isEmpty ? c.projekt : c.name
            let modell = fenster.chat.verlauf.kopf.modell.isEmpty ? fenster.chat.verlauf.status.modell : fenster.chat.verlauf.kopf.modell
            herkunft = [modell, ModellNutzlast.Projekt.kurz(c.ordner)].filter { !$0.isEmpty }.joined(separator: " · ")
        }
        let agents = fenster.oberflaeche.modus == .agents
        // IM ZUSTAND AGENTS BESCHREIBT DER KOPF DIE WELT, wie das Fenster „Agents-Welten …":
        // ihr Name als Titel, darunter die globale Welt oder ihr Projekt.
        if agents {
            let w = kern.welten.flatMap { fenster.weltenZustand.welt($0) }
            titel = w?.name ?? "Agents"
            herkunft = w.map(WeltenWorte.herkunft) ?? ""
        }
        if fenster.fenster.title != titel { fenster.fenster.title = titel }
        if fenster.fenster.subtitle != herkunft { fenster.fenster.subtitle = herkunft }
        // Zaehler und Pausenschalter der Welt stehen nur im Zustand Agents in der Symbolleiste,
        // und nur, wenn es eine Welt gibt: ohne Welt zaehlen sie nichts und schalten nichts
        // (Auftrag agentsux Nr. 1, „keine leeren Flaechen ohne Erklaerung"; die Mitte erklaert).
        let weltDa = agents && kern.welten.flatMap { fenster.weltenZustand.welt($0) } != nil
        for item in fenster.fenster.toolbar?.items ?? [] where [Self.weltenZaehlerKennung, Self.weltenPauseKennung].contains(item.itemIdentifier) {
            if item.isHidden == weltDa { item.isHidden = !weltDa }
        }
        // PILLE UND ORCHESTRATOR | WORKER GEHEN, SOLANGE AGENTS VORN LIEGT (Auftrag
        // agentsux Nr. 1, Befund des Nutzers: „Der Orchestrator/Worker-Schalter ist noch zu
        // sehen, wenn ich auf Agents gehe"). Bis dahin stand der Umschalter grau da, damit
        // die Symbolleiste beim Umschalten nicht springt; beide ordnen aber nur die
        // Code-Buehne und sagen neben einer Welt nichts. An ihrer Stelle stehen Zaehler und
        // Pausenschalter der Welt. Die Kuerzel ⌘1/⌘2 und ⌥⌘L sind im Zustand Agents grau
        // (`validateMenuItem`), zurueck auf Code ist alles wieder da.
        for item in fenster.fenster.toolbar?.items ?? [] where [Self.pilleKennung, Self.umschalterKennung].contains(item.itemIdentifier) {
            if item.isHidden != agents { item.isHidden = agents }
        }
        if agents, fenster.oberflaeche.workerListeOffen { workerListeSchliessen() }
        let flaecheSeg = agents ? 1 : 0
        if flaecheUmschalter.selectedSegment != flaecheSeg { flaecheUmschalter.selectedSegment = flaecheSeg }
        umschalter.isEnabled = s != nil && !fenster.chatGezeigt && !agents
        // UND ER HEBT DABEI NICHTS HERVOR (08.09.2026, Rest aus der Abnahme).
        // Grau allein reichte nicht: das gewaehlte Segment blieb dunkel und
        // behauptete weiter, der Orchestrator liege vorn, waehrend das
        // Agents-Blatt stand. Die Electron-Fassung nimmt die Hervorhebung dort
        // weg (renderer.ts: `const an = !agents && ...`); `selectedSegment = -1`
        // ist ihr Gegenstueck in AppKit. Auf dem Rueckweg nach Code setzt
        // dieselbe Zeile die Hervorhebung wieder auf die Buehne.
        let seg = agents ? -1 : (angezeigt == .orchestrator ? 0 : 1)
        if umschalter.selectedSegment != seg { umschalter.selectedSegment = seg }
        // Die Pille sagt VoiceOver, was sie zaehlt und was sie oeffnet (Auftrag 2.8).
        let pilleText = s == nil ? "Worker: keine Sitzung gewählt" : "\(PilleAnsicht.text(s?.laufendeWorker ?? 0)), öffnet die Worker-Liste (⌥⌘L)"
        if pille.accessibilityLabel() != pilleText { pille.setAccessibilityLabel(pilleText) }
        if s == nil, fenster.oberflaeche.workerListeOffen { workerListeSchliessen() }
    }

    /// Die Kopfhoehe: Titel samt Symbolleiste, in jeder Sitzung dieselbe.
    var hoehe: CGFloat {
        fenster.fenster.frame.height - fenster.fenster.contentLayoutRect.height
    }

    // MARK: Die Worker-Liste hinter der Pille

    var workerListeOffen: Bool { fenster.oberflaeche.workerListeOffen }


    func workerListeUmschalten() {
        if workerListeOffen { workerListeSchliessen() } else { workerListeOeffnen() }
    }

    func workerListeOeffnen() {
        guard kern.gewaehlteSitzung != nil else { return }
        fenster.oberflaeche.workerListeOffen = true
        guard !fenster.optionen.kopflos else { return }
        let p = NSPopover()
        p.behavior = .transient
        p.delegate = self
        let inhalt = WorkerListe(kern: kern, handlungen: fenster) { [weak self] in self?.workerListeSchliessen() }
        // DIE LISTE MUSS IHRE GROESSE KENNEN, BEVOR DAS POPOVER AUFGEHT
        // (08.09.2026, Befund des Nutzers: „das Popover erscheint eher in der
        // Bildschirmmitte statt direkt unter der Pille"). Ein frischer
        // `NSHostingController` hat noch keine Groesse; AppKit setzt das
        // Popover dann fuer eine Platzhaltergroesse und laesst es wachsen,
        // nachdem es steht -- gewachsen ist es nach unten UND nach oben, und
        // die Unterkante der Pille lag am Ende 65 Punkte ueber dem Popover
        // (gemessen). Erst messen, dann zeigen: derselbe Aufruf, 0 Punkte.
        let halter = NSHostingController(rootView: inhalt)
        // `preferredContentSize` ist der vorgesehene Weg, eine SwiftUI-Ansicht
        // ihre Groesse an AppKit zu melden; `fittingSize` von Hand zu setzen
        // traf sie beim Leerzustand um 15 Punkte nicht (gemessen 08.09.2026),
        // weil dessen Text erst beim Umbruch seine Hoehe kennt.
        halter.sizingOptions = [.preferredContentSize]
        halter.view.layoutSubtreeIfNeeded()
        p.contentViewController = halter
        popover = p
        p.show(relativeTo: pille.bounds, of: pille, preferredEdge: .minY)
    }

    func workerListeSchliessen() {
        fenster.oberflaeche.workerListeOffen = false
        if let p = popover, p.isShown { p.performClose(nil) }
        popover = nil
    }

    func popoverDidClose(_ notification: Notification) {
        fenster.oberflaeche.workerListeOffen = false
        popover = nil
    }

    /// Der Beleg der offenen Liste fuer kopflose Bilder (Fenster.schuss): das
    /// Popover zeichnet ausserhalb des Bildschirms nichts, also dieselbe View
    /// ueber ImageRenderer, rechts oben unter dem Kopf, wo das Popover haengt.
    func belegZeichnen(in rep: NSBitmapImageRep, fensterHoehe: CGFloat) {
        guard workerListeOffen, let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return }
        let dunkel = fenster.fenster.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let beleg = WorkerListe(kern: kern, handlungen: fenster)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(nsColor: .separatorColor)))
            .environment(\.colorScheme, dunkel ? .dark : .light)
        let renderer = ImageRenderer(content: beleg)
        renderer.scale = fenster.fenster.backingScaleFactor
        guard let bild = renderer.nsImage else { return }
        let rahmenBreite = CGFloat(rep.pixelsWide) / renderer.scale
        // Unter der Pille: rechts, mit dem Zahnrad und dem Umschalter davor.
        let x = rahmenBreite - bild.size.width - 180
        let y = fensterHoehe - hoehe - bild.size.height - 4
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        bild.draw(in: NSRect(x: max(8, x), y: max(0, y), width: bild.size.width, height: bild.size.height),
                  from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
    }

    /// DIE SYMBOLLEISTE ALS BELEG (08.09.2026). Im Bild des Rahmens stehen ihre
    /// Elemente als leere Kapseln: macOS 26 setzt den Hintergrund eines
    /// Symbolleisten-Elements ueber den Fensterserver zusammen, und
    /// `cacheDisplay` auf dem Fensterrahmen bekommt davon nur diesen
    /// Hintergrund, nie den Inhalt. Genau deshalb war an den Belegbildern der
    /// Abnahme nicht zu sehen, was der Umschalter hervorhebt. Also dieselben
    /// Ansichten noch einmal, jede aus sich selbst heraus gezeichnet, an ihre
    /// Stelle im Bild -- derselbe Handgriff wie bei Seitenleiste und Inspektor.
    ///
    /// WAS DAMIT NICHT GEHT (gemessen 08.09.): im DUNKLEN Erscheinungsbild
    /// bleibt der Weg wirkungslos -- die Elemente kommen dort auch aus sich
    /// selbst heraus leer, und im Bild stehen weiter die Kapseln. Ein Bild des
    /// dunklen Kopfes braucht deshalb weiter eine echte Bildschirmaufnahme.
    func symbolleisteZeichnen(in rep: NSBitmapImageRep) {
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return }
        for v in [flaecheUmschalter as NSView, pille, umschalter] {
            guard v.window != nil, !v.isHiddenOrHasHiddenAncestor else { continue }
            let ziel = v.convert(v.bounds, to: nil)
            guard ziel.width > 1, ziel.height > 1, let eigen = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { continue }
            // IM ERSCHEINUNGSBILD DES FENSTERS zeichnen: ausserhalb eines
            // Zeichenzyklus loesen sich dynamische Farben nach
            // `NSAppearance.current` auf, und im dunklen Bild blieben die
            // Elemente sonst leer (gemessen 08.09., dieselbe Falle wie beim
            // Fenstergrund des Einstellungsbelegs).
            fenster.fenster.effectiveAppearance.performAsCurrentDrawingAppearance {
                v.cacheDisplay(in: v.bounds, to: eigen)
                let bild = NSImage(size: v.bounds.size)
                bild.addRepresentation(eigen)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = ctx
                bild.draw(in: ziel, from: .zero, operation: .sourceOver, fraction: 1)
                NSGraphicsContext.restoreGraphicsState()
            }
        }
    }

    // MARK: Symbolleisten-Elemente

    static let pilleKennung = NSToolbarItem.Identifier("werkbank.pille")
    static let umschalterKennung = NSToolbarItem.Identifier("werkbank.umschalter")
    static let flaecheKennung = NSToolbarItem.Identifier("werkbank.flaeche")
    static let weltenZaehlerKennung = NSToolbarItem.Identifier("werkbank.welten-zaehler")
    static let weltenPauseKennung = NSToolbarItem.Identifier("werkbank.welten-pause")

    /// Der Zaehler der Welt; versteckt, bis der Umschalter auf Agents steht (`nachziehen`).
    func weltenZaehlerItem() -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: Self.weltenZaehlerKennung)
        item.view = weltenZaehler
        item.label = "Zähler der Welt"
        item.toolTip = "Wer dich braucht, wer läuft, wie viele Tickets offen sind"
        item.isHidden = fenster.oberflaeche.modus != .agents
        return item
    }

    /// Der Pausenschalter der Welt; versteckt wie der Zaehler.
    func weltenPauseItem() -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: Self.weltenPauseKennung)
        item.view = weltenPause
        item.label = "Welt pausieren"
        item.toolTip = "Pause hält jeden Agenten der Welt am nächsten Checkpoint an"
        item.isHidden = fenster.oberflaeche.modus != .agents
        return item
    }

    func flaecheItem() -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: Self.flaecheKennung)
        item.view = flaecheUmschalter
        item.label = "Bühne"
        item.toolTip = "Die Sitzung oder die Welten der Agents zeigen"
        return item
    }

    func pilleItem() -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: Self.pilleKennung)
        item.view = pille
        item.label = "Worker"
        item.toolTip = "Worker dieser Sitzung, die gerade arbeiten oder warten"
        item.isHidden = fenster.oberflaeche.modus == .agents
        return item
    }

    func umschalterItem() -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: Self.umschalterKennung)
        item.view = umschalter
        item.label = "Ansicht"
        item.toolTip = "Orchestrator oder Worker zeigen"
        item.isHidden = fenster.oberflaeche.modus == .agents
        return item
    }

    /// Die Auskunft fuer `awbmac-ctl ui`.
    /// WO DAS POPOVER HAENGT (08.09.2026, Befund des Nutzers: „das Popover
    /// erscheint eher in der Bildschirmmitte statt direkt unter der Pille").
    /// Beide Rahmen in Bildschirmkoordinaten, dazu die zwei Zahlen, an denen
    /// sich das messen laesst: der senkrechte Abstand von der Unterkante der
    /// Pille zur Oberkante des Popovers, und die waagerechte Ueberdeckung.
    /// Ohne offenes Popover bleibt `da` falsch und die Zahlen sind -1.
    func lageAuskunft() -> [String: Any] {
        func rahmen(_ r: NSRect) -> [Int] { [Int(r.minX), Int(r.minY), Int(r.width), Int(r.height)] }
        let pilleSchirm = pille.window?.convertToScreen(pille.convert(pille.bounds, to: nil)) ?? .zero
        guard let p = popover, p.isShown, let pw = p.contentViewController?.view.window else {
            return ["da": false, "pille": rahmen(pilleSchirm), "popover": [-1, -1, -1, -1], "abstand": -1, "ueberdeckung": -1]
        }
        let pop = pw.frame
        return [
            "da": true,
            "pille": rahmen(pilleSchirm),
            "popover": rahmen(pop),
            // Die Pille sitzt oben, das Popover haengt darunter: der Abstand
            // ist die Luecke zwischen Pillen-Unterkante und Popover-Oberkante.
            "abstand": Int((pilleSchirm.minY - pop.maxY).rounded()),
            "ueberdeckung": Int(max(0, min(pilleSchirm.maxX, pop.maxX) - max(pilleSchirm.minX, pop.minX)).rounded()),
        ]
    }

    func auskunft() -> [String: Any] {
        let s = kern.gewaehlteSitzung
        let n = s?.laufendeWorker ?? 0
        let worker: [[String: Any]] = (s?.flacheWorker ?? []).map { w in
            let kind = s?.istKind(w) ?? false
            let fremd = (s?.fern(eigene: kern.modell.machine) ?? false) ? (s?.machine ?? "") : ""
            let z = WorkerZeile(worker: w, kind: kind, kinder: 0, maschine: fremd)
            return ["name": w.name, "state": w.state, "zustandText": WorkerZeile.wort(fuer: w.state),
                    "punkt": WorkerZeile.punkt(fuer: w.state).rawValue,
                    "punktForm": WorkerZeile.punkt(fuer: w.state).form, "unten": z.unten, "model": w.model,
                    "tokens": w.tokensKurz, "pane": w.paneId, "kind": kind,
                    "herkunft": [fremd, kind ? "auf Antrag von \(w.requestedBy)" : ""].filter { !$0.isEmpty }.joined(separator: " · "),
                    "subagenten": w.subagents.map { ["name": $0.anzeigename, "type": $0.type, "pane": $0.paneId] }]
        }
        return [
            "da": s != nil,
            "name": fenster.fenster.title,
            "herkunft": fenster.fenster.subtitle,
            "laufen": n,
            "pille": PilleAnsicht.text(n),
            "pilleFarbe": n > 0 ? "laeuft" : "ruhig",
            "hoehe": Int(hoehe.rounded()),
            "umschalter": angezeigt.rawValue,
            "wahl": fenster.oberflaeche.ansicht.rawValue,
            "buehne": buehne?.rawValue ?? "",
            // Der Umschalter Code | Agents: was er zeigt und ob der Umschalter
            // Orchestrator | Worker daneben gerade etwas zu schalten hat.
            "flaeche": fenster.oberflaeche.modus.rawValue,
            "umschalterAktiv": umschalter.isEnabled,
            // Was er WIRKLICH hervorhebt -- leer, solange er nichts hervorhebt.
            "umschalterHervorgehoben": umschalter.selectedSegment >= 0 && umschalter.selectedSegment < umschalter.segmentCount
                ? (umschalter.label(forSegment: umschalter.selectedSegment) ?? "") : "",
            "kapazitaet": ["perRow": kern.modell.capacity.perRow, "perColumn": kern.modell.capacity.perColumn, "perTab": kern.modell.capacity.perTab,
                           "tabs": kern.modell.capacity.tabs, "workerCount": kern.modell.capacity.workerCount],
            "streifen": ["da": streifenDa, "tabs": s?.tabs(perTab: kern.modell.capacity.perTab) ?? 0,
                         "gewaehlt": s.map { gewaehlterTab($0) } ?? 0, "perTab": kern.modell.capacity.perTab,
                         "hoehe": Int(fenster.streifenHoehe.rounded()),
                         "marken": tabMarken().map { ["nr": $0.nr, "text": $0.text, "anzahl": $0.anzahl, "farbe": $0.farbe, "namen": $0.namen] }],
            "workerliste": ["offen": workerListeOffen, "worker": worker,
                            "elternloseSubagenten": (s?.orphanSubagents ?? []).map { ["name": $0.anzeigename, "type": $0.type, "pane": $0.paneId] },
                            "leer": worker.isEmpty, "leerText": worker.isEmpty ? WorkerListe.leerText : "",
                            "lage": lageAuskunft()],
        ]
    }
}
