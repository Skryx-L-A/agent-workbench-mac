// Die Terminal-Pane -- in zwei Bauarten, weil die Frage GEMESSEN wird
// (MAC-NATIV-PLAN.md, „Offene Architekturfrage"; Zahlen in mac/PLAN-TERMINAL.md):
//
//   strom   SwiftTerm ist der Bildschirm fuer den Steuermodus-Strom des Kerns.
//           Momentaufnahme + Rueckblick kommen mit `awb:layout`, laufende Bytes
//           mit `awb:output`, Tastendruecke gehen als `awb:input` zurueck, die
//           Groesse als `flaeche`. Genau der Weg von xterm.js heute.
//   attach  SwiftTerm haelt einen echten tmux-Client: `tmux attach -t <sitzung>`
//           auf einem eigenen Pseudo-Terminal. tmux zeichnet selbst; die
//           Groesse folgt der Ansicht ueber das Pseudo-Terminal.
//
// Beide stecken hinter derselben Klasse `TerminalBereich`, damit Fenster und
// Steuerkanal nicht wissen muessen, welche laeuft.
import AppKit
import SwiftTerm
import WerkbankProtokoll

/// Was beim Kopieren geschieht: im Betrieb die Zwischenablage des Systems, kopflos
/// ein Merker -- ein Test darf Zwischenablage des Nutzers nie anfassen.
@MainActor
final class Zwischenablage {
    let kopflos: Bool
    private(set) var merker: String?

    init(kopflos: Bool) { self.kopflos = kopflos }

    func schreiben(_ text: String) {
        merker = text
        guard !kopflos else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    func lesen() -> String? {
        kopflos ? merker : NSPasteboard.general.string(forType: .string)
    }
}

/// Die Bauart „strom": ein TerminalView, das der Kern fuettert.
@MainActor
final class StromTerminal: TerminalView, @preconcurrency TerminalViewDelegate {
    let kern: KernVerbindung
    let zwischenablage: Zwischenablage
    /// Der Pane, dessen Bytes hier ankommen und dessen Eingabe hier hinausgeht.
    var pane = ""
    private var rueckblickDa = false
    private var gefuettert = false
    /// Die Groesse hat sich geaendert -- der Bereich meldet die Buehne, nicht die Kachel.
    var aufGroesse: (() -> Void)?
    /// Der Mensch hat in dieses Terminal geklickt oder es hat die Tastatur bekommen:
    /// der Fokus folgt der Kachel (Auftrag 2.3).
    var aufFokus: (() -> Void)?
    /// ⌘-Klick auf einen Pfad in der Ausgabe (Auftrag 3.6): der Wortlaut unter
    /// dem Zeiger, samt Zeilenangabe, wenn eine dabeisteht.
    var aufPfadKlick: ((String) -> Void)?

    init(kern: KernVerbindung, zwischenablage: Zwischenablage, schrift: NSFont) {
        self.kern = kern
        self.zwischenablage = zwischenablage
        super.init(frame: .zero, font: schrift)
        terminalDelegate = self
        configureNativeColors()
    }

    required init?(coder: NSCoder) { fatalError("nicht aus einem Nib") }

    /// Eine neue Lage: Momentaufnahme EINES Panes einspielen -- wie
    /// paneflaeche.ts `zeichneLage`: zurueckgesetzt wird nur ein FRISCHES
    /// Terminal oder eines, das jetzt erst seinen Rueckblick bekommt; sonst
    /// wuerfe jede neue Lage (jeder Groessenwechsel) den Rueckblick weg, und
    /// der Kern schickt ihn nur einmal je Pane. Der Schirm beginnt ohnehin mit
    /// „loeschen, Cursor nach oben".
    ///
    /// DIE GROESSE KOMMT VOR DEM INHALT (08.09.2026, Auftrag geometrie). Bis
    /// heute setzte `lageEinspielen` nur `k.cols`/`k.rows`, fuetterte den
    /// Schirm und liess die Kachel erst danach legen -- und erst dort, in
    /// `Kachel.anordnen`, lief das `resize`. Der Schirm ging damit in ein
    /// Terminal der ALTEN Groesse, und die Groessenaenderung danach brach ihn
    /// um: was oben hinausrollte, lag im Rueckblick und kam nicht zurueck.
    /// GEMESSEN kopflos am 08.09. mit `--terminal strom`: 40 Zeilen im Pane,
    /// 20 im Terminal, und sie kamen ueber zwanzig Sekunden nicht wieder; ein
    /// Ansichtswechsel stellte es sofort her, weil die Kachel dann frisch
    /// entstand. Dieselbe Ursache zeigte sich als Zellen, die es im Pane nicht
    /// gibt -- Reste einer breiteren Zeichnung, die das Umbrechen stehen liess.
    ///
    /// Zuerst stellen, dann fuettern: `resize` bringt SwiftTerm auf die
    /// Panegroesse (und macht dabei seinen `softReset`, der Scrollregion und
    /// Modi der vorigen Zeichnung wegnimmt), und der Schirm beginnt ohnehin mit
    /// „loeschen, Cursor nach oben" -- danach steht Zelle fuer Zelle das, was
    /// `capture-pane -p` liefert. `Kachel.anordnen` stellt weiterhin auch, aber
    /// nur noch als Nachhut fuer den Weg ueber den Rahmen; steht die Groesse
    /// schon, tut es dort nichts mehr.
    func einspielen(pane ziel: String, lage: LageNutzlast, cols: Int, rows: Int) {
        let frisch = ziel != pane || !gefuettert
        pane = ziel
        guard let inhalt = lage.inhalt[ziel] else { return }
        if cols > 0, rows > 0, getTerminal().cols != cols || getTerminal().rows != rows {
            resize(cols: cols, rows: rows)
        }
        let historie = lage.historie[ziel] ?? ""
        if frisch || (!historie.isEmpty && !rueckblickDa) {
            getTerminal().resetToInitialState()
            rueckblickDa = false
        }
        if !historie.isEmpty, !rueckblickDa {
            feed(text: historie)
            rueckblickDa = true
        }
        feed(text: inhalt)
        gefuettert = true
    }

    /// DER ROLLBALKEN VON SWIFTTERM BLEIBT AUS (08.09.2026, Auftrag geometrie,
    /// vierte Runde) -- und das ist keine Geschmacksfrage, sondern die Wurzel
    /// des Bildes, das dem Nutzer „manchmal direkt nach dem Fensteroeffnen"
    /// gesehen hat.
    ///
    /// SwiftTerm rechnet seine Spaltenzahl aus dem RAHMEN, und zwar aus
    /// `getEffectiveWidth`: Rahmenbreite MINUS der Breite, die es fuer seinen
    /// Rollbalken reserviert (`reservedScrollerWidth`, nicht oeffentlich).
    /// Ein Rahmen von `cols * Zellbreite` ergibt damit `cols - 3` Spalten.
    /// GEMESSEN kopflos am 08.09.: die Kachel verlangte 145 Spalten, das
    /// Terminal stand nach jedem Rahmenwechsel auf 142, und `Kachel.anordnen`
    /// stellte es auf 145 zurueck -- zwei Umbrueche des Inhalts um jede neue
    /// Lage herum. Genau darin verschwand die oberste Zeile, und genau daher
    /// kamen Zeilen, die bei einer FRUEHEREN Breite umgebrochen waren.
    ///
    /// Reserviert wird nichts mehr, sobald der Rollbalken versteckt ist
    /// (`reservedScrollerWidth` fragt `scroller?.isHidden`), und dann stimmen
    /// Rahmen und Spaltenzahl auf die Zelle genau ueberein. Gebraucht wird er
    /// hier ohnehin nicht: der Rueckblick kommt vom Kern, und das Rad bedient
    /// die Buehne selbst. `updateScroller` fasst `isHidden` nicht an, das
    /// Verstecken haelt also.
    func rollbalkenAus() {
        for v in subviews where v is NSScroller && !v.isHidden { v.isHidden = true }
    }

    func ausgabe(pane p: String, bytes: Data) {
        guard p == pane, !bytes.isEmpty else { return }
        feed(byteArray: ArraySlice([UInt8](bytes)))
    }


    /// ⌘C und das Menue: ueber die Zwischenablage des Bereichs, nie direkt an
    /// NSPasteboard -- SwiftTerms eigene Fassung schriebe sie auch kopflos.
    override func copy(_ sender: Any) {
        if let text = getSelection() { zwischenablage.schreiben(text) }
    }

    override func mouseDown(with event: NSEvent) {
        // ⌘-KLICK OEFFNET EINEN PFAD (Auftrag 3.6). Die Befehlstaste ist auf dem
        // Mac die verabredete Geste dafuer -- Terminal.app und iTerm2 machen es
        // genauso, und SwiftTerm selbst zeigt seine OSC-8-Links nur mit
        // gedrueckter Befehlstaste als Link an (`commandActive` in
        // MacTerminalView). Ein Klick OHNE sie bleibt, was er war: Fokus und
        // Auswahl. Ein eigener Erkenner ist noetig, weil ein Pfad in der
        // Ausgabe eines Agenten kein OSC-8-Link ist, sondern nackter Text.
        if event.modifierFlags.contains(.command), let wortlaut = pfadUnter(punkt: convert(event.locationInWindow, from: nil)) {
            if window?.firstResponder !== self { window?.makeFirstResponder(self) }
            aufFokus?()
            aufPfadKlick?(wortlaut)
            return
        }
        super.mouseDown(with: event)
        if window?.firstResponder !== self { window?.makeFirstResponder(self) }
        aufFokus?()
    }

    /// Die Groesse einer Zelle. `caretFrame` ist die Schreibmarke und damit
    /// genau eine Zelle gross (SwiftTerm setzt sie aus `cellDimension`, das
    /// selbst nicht oeffentlich ist); steht sie noch nicht, wird sie aus der
    /// Flaeche und der Spalten-/Zeilenzahl gerechnet.
    var zellgroesse: (breite: CGFloat, hoehe: CGFloat) {
        let t = getTerminal()
        let k = caretFrame.size
        let b = k.width > 1 ? k.width : (t.cols > 0 ? bounds.width / CGFloat(t.cols) : 0)
        let h = k.height > 1 ? k.height : (t.rows > 0 ? bounds.height / CGFloat(t.rows) : 0)
        return (b, h)
    }

    /// Der Pfad unter einem Punkt der Ansicht -- dieselbe Rechnung wie SwiftTerms
    /// `calculateMouseHit`: Spalte aus x, Zeile von OBEN (die Ansicht ist nicht
    /// umgedreht, deshalb `frame.height - y`).
    func pfadUnter(punkt: CGPoint) -> String? {
        let z = zellgroesse
        guard z.breite > 0, z.hoehe > 0 else { return nil }
        let t = getTerminal()
        let spalte = min(max(0, Int(punkt.x / z.breite)), max(0, t.cols - 1))
        let zeile = min(max(0, Int((frame.height - punkt.y) / z.hoehe)), max(0, t.rows - 1))
        return pfadUnter(zeile: zeile, spalte: spalte)
    }

    /// Der Pfad in einer Schirmzeile an einer Spalte (nullbasiert) -- der Weg,
    /// den auch der Steuerkanal geht, ohne einen Mausklick zu erfinden.
    func pfadUnter(zeile: Int, spalte: Int) -> String? {
        guard let text = getTerminal().getLine(row: zeile)?.translateToString(trimRight: true) else { return nil }
        return Pfadlinks.stelleBeiSpalte(text, spalte: spalte)?.wortlaut
    }

    // MARK: TerminalViewDelegate

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        aufGroesse?()
    }

    func setTerminalTitle(source: TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        guard !pane.isEmpty else { return }
        kern.eingabe(pane: pane, bytes: Data(data))
    }

    func scrolled(source: TerminalView, position: Double) {}
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        if let url = URL(string: link) { NSWorkspace.shared.open(url) }
    }
    func bell(source: TerminalView) {}

    func clipboardCopy(source: TerminalView, content: Data) {
        zwischenablage.schreiben(String(decoding: content, as: UTF8.self))
    }

    func clipboardRead(source: TerminalView) -> Data? {
        zwischenablage.lesen().map { Data($0.utf8) }
    }

    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}

/// Die Bauart „attach": ein echter tmux-Client im Pseudo-Terminal. Eigener
/// `LocalProcess` statt `LocalProcessTerminalView`, weil dessen Zwischenablage
/// fest an `NSPasteboard.general` haengt -- eine Pruefung darf sie nie anfassen.
@MainActor
final class AttachTerminal: TerminalView, @preconcurrency TerminalViewDelegate, @preconcurrency LocalProcessDelegate {
    let zwischenablage: Zwischenablage
    private var process: LocalProcess!
    private(set) var sitzung = ""
    private(set) var laeuft = false
    /// Neue Bytes vom Client -- fuer die Zoom-Messung.
    var aufBytes: (() -> Void)?

    init(zwischenablage: Zwischenablage, schrift: NSFont) {
        self.zwischenablage = zwischenablage
        super.init(frame: .zero, font: schrift)
        terminalDelegate = self
        process = LocalProcess(delegate: self)
        configureNativeColors()
    }

    required init?(coder: NSCoder) { fatalError("nicht aus einem Nib") }

    func anhaengen(sitzung neu: String, tmuxBin: String, socket: String) {
        if laeuft { process.terminate(); laeuft = false }
        sitzung = neu
        guard !neu.isEmpty else { return }
        var args: [String] = []
        if !socket.isEmpty { args += ["-L", socket] }
        args += ["attach-session", "-t", neu]
        // Die GANZE Umgebung der App plus TERM: tmux findet seinen Server ueber
        // TMPDIR/TMUX_TMPDIR, und ohne sie (SwiftTerms Vorgabe liefert nur TERM,
        // LANG und Co.) sucht der Client unter /tmp -- gemessen 06.09.: leerer
        // Schirm, kein Fehler, weil der Client sich schweigend beendete.
        var umgebung = ProcessInfo.processInfo.environment
        umgebung["TERM"] = "xterm-256color"
        umgebung["COLORTERM"] = "truecolor"
        umgebung.removeValue(forKey: "TMUX")
        umgebung.removeValue(forKey: "TMUX_PANE")
        let liste = umgebung.map { "\($0.key)=\($0.value)" }
        let exe = tmuxBin.contains("/") ? tmuxBin : (pfadSuchen(tmuxBin, umgebung["PATH"] ?? "") ?? tmuxBin)
        process.startProcess(executable: exe, args: args, environment: liste)
        laeuft = true
    }

    func beenden() {
        if laeuft { process.terminate(); laeuft = false }
    }

    /// ⌘C und das Menue: ueber die Zwischenablage des Bereichs, nie direkt an
    /// NSPasteboard -- SwiftTerms eigene Fassung schriebe sie auch kopflos.
    override func copy(_ sender: Any) {
        if let text = getSelection() { zwischenablage.schreiben(text) }
    }

    // MARK: TerminalViewDelegate
    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        guard process.running else { return }
        var size = getWindowSize()
        _ = PseudoTerminalHelpers.setWinSize(masterPtyDescriptor: process.childfd, windowSize: &size)
    }
    func setTerminalTitle(source: TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func send(source: TerminalView, data: ArraySlice<UInt8>) { process.send(data: data) }
    func scrolled(source: TerminalView, position: Double) {}
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        if let url = URL(string: link) { NSWorkspace.shared.open(url) }
    }
    func bell(source: TerminalView) {}
    func clipboardCopy(source: TerminalView, content: Data) {
        zwischenablage.schreiben(String(decoding: content, as: UTF8.self))
    }
    func clipboardRead(source: TerminalView) -> Data? {
        zwischenablage.lesen().map { Data($0.utf8) }
    }
    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}

    // MARK: LocalProcessDelegate
    func processTerminated(_ source: LocalProcess, exitCode: Int32?) { laeuft = false }
    func dataReceived(slice: ArraySlice<UInt8>) {
        feed(byteArray: slice)
        aufBytes?()
    }
    func getWindowSize() -> winsize {
        let t = getTerminal()
        let scale = window?.backingScaleFactor ?? 2
        let f = frame.size
        return winsize(ws_row: UInt16(t.rows), ws_col: UInt16(t.cols),
                       ws_xpixel: UInt16(max(0, f.width * scale)), ws_ypixel: UInt16(max(0, f.height * scale)))
    }
}

/// Sucht ein Programm im PATH -- posix_spawn braucht den vollen Pfad.
func pfadSuchen(_ name: String, _ pfad: String) -> String? {
    for teil in pfad.split(separator: ":") {
        let k = "\(teil)/\(name)"
        if FileManager.default.isExecutableFile(atPath: k) { return k }
    }
    return nil
}

/// Der Bereich, der die Terminal-Panes der Buehne zeigt -- egal in welcher Bauart.
///
/// DIE KACHELFLAECHE (Auftrag 2.3): eine Lage `tab` wird zu so vielen Kacheln,
/// wie sie Panes (und fehlende Panes) hat; jede Kachel ist Kopfzeile plus ein
/// StromTerminal in GENAU der Groesse, die der Kern dem Pane gegeben hat. Wo die
/// Kacheln liegen, rechnet `Kachelung` -- dieselbe Rechnung wie paneflaeche.ts,
/// auf denselben drei Wegen (Raster, Teilraster, Reihenfolge).
///
/// DIE BUEHNE AN DEN KERN ist die Flaeche fuer Terminals in Zellen: die rohe
/// Flaeche minus eine Kopfzeile je Kachelzeile, abgerundet (`flaecheInZellen`
/// des Renderers). Der Kern schneidet daraus die Kacheln in Zellen
/// (capacity.ts `kachelZellen`) und stellt die tmux-Fenster; die Kachel hier
/// legt das Terminal dann in der zurueckgemeldeten Groesse hinein. Gemeldet
/// wird nur, was sich geaendert hat -- eine Zahl, die sich aus der Lage selbst
/// ergibt (Summe der Zeilen), war der Kreis aus 2.2 und ist weg.
@MainActor
final class TerminalBereich: NSView {
    let art: TerminalArt
    let kern: KernVerbindung
    let optionen: Laufoptionen
    let zwischenablage: Zwischenablage
    private var attach: AttachTerminal?
    /// Die Kacheln der Buehne in Lage-Reihenfolge (erst gezeigte, dann fehlende).
    private(set) var kacheln: [Kachel] = []
    /// Terminals je Pane -- ein Pane behaelt sein Terminal ueber Lagen hinweg
    /// (paneflaeche.ts `paneTerms`), damit Rueckblick und Auswahl bleiben.
    private var terminals: [String: StromTerminal] = [:]
    /// Das Mass-Terminal: nie gezeigt, nie umgestellt, liefert die Zellgroesse.
    private var mass: StromTerminal?
    private let flaeche = NSView()
    private let schrift: NSFont
    /// Die zuletzt eingespielte Lage.
    private(set) var lage: LageNutzlast?
    /// Welche Art die letzte Lage hatte (pane | tab) -- fuer die Auskunft.
    var lageArt: String { lage?.art ?? "pane" }
    /// Der Pane mit der Tastatur.
    private(set) var aktiv = ""
    /// Zuletzt gemeldete Buehne, damit dieselbe Groesse nicht zweimal reist.
    private(set) var gemeldet: (cols: Int, rows: Int) = (0, 0)
    /// Wie oft die Buehne seit dem Start an den Kern gegangen ist. Die Zahl
    /// steht in `awbmac-ctl ui`, damit eine Pruefung nachweisen kann, dass ein
    /// Zug am Teiler oder an der Seitenleiste GENAU EINE Meldung ergibt und
    /// nicht eine je Zwischenwert der Bewegung.
    private(set) var meldungen = 0
    /// Die Uhr, die das Ende einer Bewegung abwartet (siehe `meldungAnstossen`).
    private var meldeUhr: Timer?
    /// Waehrend die Meldung selbst laeuft, stoesst das erzwungene Layout keine
    /// zweite an.
    private var imMelden = false
    /// Eine Bewegung der Seitenleiste oder des Inspektors laeuft: bis sie steht,
    /// geht keine Zwischengroesse an den Kern.
    private var inBewegung = false
    /// Die Flaeche, die der vorige Blick waehrend der Bewegung gesehen hat.
    private var letzteBewegung: CGSize = .zero
    /// Die zuletzt gelegten Kacheln in Terminalflaeche (fuer die Auskunft).
    private(set) var gelegt: [Kachelung.Rechteck] = []
    private(set) var kachelZeilen = 1
    /// Zaehlt jedes Neuzeichnen (Lage oder Bytes) -- fuer die Zoom-Messung.
    private var bildZaehler = 0
    /// Zaehlt nur die Lagen (strom): der Zoom ist erst mit der neuen Lage da.
    private var lageZaehler = 0
    /// Aus der Kachel heraus: diesen Pane allein zeigen; und zurueck zu allen.
    var aufZoom: ((String) -> Void)?
    var aufZurueck: (() -> Void)?
    /// ⌘-Klick auf einen Pfad in einer Kachel (Auftrag 3.6): Pane und Wortlaut.
    var aufPfadKlick: ((String, String) -> Void)?
    /// Was in der Kopfzeile eines Panes steht -- das Fenster kennt das Modell.
    var kopfZuPane: ((String) -> KachelKopfDaten)?

    /// Das Terminal mit der Tastatur (Schirm, Auswahl, Messungen) -- sonst das erste.
    var terminal: TerminalView {
        if art == .attach { return attach! }
        return terminals[aktiv] ?? kacheln.compactMap(\.terminal).first ?? massTerminal()
    }

    init(art: TerminalArt, kern: KernVerbindung, optionen: Laufoptionen, kopflos: Bool) {
        self.art = art
        self.kern = kern
        self.optionen = optionen
        self.zwischenablage = Zwischenablage(kopflos: kopflos)
        self.schrift = NSFont.monospacedSystemFont(ofSize: CGFloat(kern.modell.schriftgroesse), weight: .regular)
        super.init(frame: .zero)
        let view: NSView
        switch art {
        case .strom:
            view = flaeche
            kern.aufLage = { [weak self] lage in
                self?.lageEinspielen(lage)
                self?.lageZaehler += 1
                self?.bildGemeldet()
            }
            kern.aufAusgabe = { [weak self] pane, bytes in
                guard let self else { return }
                self.terminals[pane]?.ausgabe(pane: pane, bytes: bytes)
                self.bildGemeldet()
            }
        case .attach:
            let a = AttachTerminal(zwischenablage: zwischenablage, schrift: schrift)
            attach = a
            view = a
            a.aufBytes = { [weak self] in self?.bildGemeldet() }
        }
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.topAnchor.constraint(equalTo: topAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("nicht aus einem Nib") }

    private func stromAnlegen(pane: String) -> StromTerminal {
        let s = StromTerminal(kern: kern, zwischenablage: zwischenablage, schrift: schrift)
        s.pane = pane
        // Auch der Ruf des Terminals selbst laeuft ueber die Uhr: waehrend
        // die Seitenleiste sich bewegt, meldet er sonst jeden Zwischenwert
        // (gemessen 08.09.: dreiundzwanzig je Zug).
        s.aufGroesse = { [weak self] in self?.groesseGemeldet() }
        s.aufFokus = { [weak self] in self?.fokusSetzen(pane) }
        s.aufPfadKlick = { [weak self] wortlaut in self?.aufPfadKlick?(pane, wortlaut) }
        return s
    }

    private func massTerminal() -> StromTerminal {
        if let m = mass { return m }
        let m = StromTerminal(kern: kern, zwischenablage: zwischenablage, schrift: schrift)
        mass = m
        return m
    }

    /// Die Zellgroesse: dieselbe Rechnung wie SwiftTerms `computeFontDimensions`
    /// (Ascent + Descent + Leading, Vorschub von „W", auf den Bildpunkt gerundet),
    /// weil `cellDimension` dort nicht oeffentlich ist.
    /// DIE ZELLE, WIE SWIFTTERM SIE WIRKLICH BENUTZT (08.09.2026, des Nutzers
    /// Befund „am unteren Rand des Orchestrator-Terminals fehlen Zeilen").
    ///
    /// `zelle` unten RECHNET die Zellgroesse aus den Fontmetriken nach -- also
    /// aus derselben Formel, die SwiftTerm benutzt. Eine nachgerechnete Zahl
    /// ist aber eine Behauptung; diese hier ist gelesen:
    /// `getOptimalFrameSize()` gibt den Rahmen, den SwiftTerm fuer seine
    /// aktuellen Zeilen und Spalten braucht, und geteilt durch die Zeilenzahl
    /// steht die Zellhoehe da, mit der wirklich gezeichnet wird.
    ///
    /// Die BREITE aus dieser Rechnung traegt noch die Breite des Rollbalkens in
    /// sich (`reservedScrollerWidth`, in SwiftTerm nicht oeffentlich); sie ist
    /// deshalb nur ein Anhalt. Die HOEHE ist exakt, und um sie geht es.
    var zelleGemessen: Kachelung.Zelle? {
        let t = massTerminal()
        let term = t.getTerminal()
        let r = t.getOptimalFrameSize()
        guard term.rows > 0, term.cols > 0, r.height > 0 else { return nil }
        return Kachelung.Zelle(breite: r.width / CGFloat(term.cols), hoehe: r.height / CGFloat(term.rows))
    }

    var zelle: Kachelung.Zelle {
        let f = schrift as CTFont
        let hoehe = ceil(CTFontGetAscent(f) + CTFontGetDescent(f) + CTFontGetLeading(f))
        let glyph = schrift.glyph(withName: "W")
        let breite = schrift.advancement(forGlyph: glyph).width
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let gerechnet = Kachelung.Zelle(breite: max(1, (breite * scale).rounded() / scale),
                                        hoehe: max(1, ceil(hoehe * scale) / scale))
        // DIE HOEHE WIRD GELESEN, NICHT GERATEN (08.09.2026). Die Rechnung
        // darueber ist SwiftTerms eigene Formel, von Hand nachgebaut -- und ein
        // Nachbau kann auseinandergehen, sobald dort ein Zeilenabstand oder
        // eine Ersatzschrift ins Spiel kommt. Zwei Zeilen zu viel gerechnet,
        // und die untersten Zeilen des Panes liegen unter der Kachelkante.
        // `zelleGemessen` liest die Zahl aus der Instanz; die BREITE von dort
        // traegt die Rollbalkenbreite mit und bleibt deshalb gerechnet.
        guard let echt = zelleGemessen, echt.hoehe > 0 else { return gerechnet }
        return Kachelung.Zelle(breite: gerechnet.breite, hoehe: echt.hoehe)
    }

    // MARK: Lage

    /// Eine neue Lage: je Pane eine Kachel mit seinem Terminal, fehlende Panes
    /// als Platzhalter mit Grund; danach legen und die Buehne melden.
    private func lageEinspielen(_ neu: LageNutzlast) {
        lage = neu
        var ziele = neu.panes
        if ziele.isEmpty, !neu.aktiv.isEmpty { ziele = [LageNutzlast.Kachel(paneId: neu.aktiv, cols: neu.cols, rows: neu.rows)] }
        var gesehen = Set<String>()
        var neueKacheln: [Kachel] = []
        /// Was gefuettert wird, sobald die Kacheln liegen -- siehe unten.
        var zuFuettern: [(StromTerminal, LageNutzlast.Kachel)] = []
        for box in ziele where !box.paneId.isEmpty && !gesehen.contains(box.paneId) {
            gesehen.insert(box.paneId)
            let t = terminals[box.paneId] ?? stromAnlegen(pane: box.paneId)
            terminals[box.paneId] = t
            let k = kacheln.first { $0.pane == box.paneId && $0.fehltGrund == nil } ?? Kachel(
                pane: box.paneId, terminal: t,
                zoom: { [weak self] p in self?.aufZoom?(p) },
                zurueck: { [weak self] in self?.aufZurueck?() },
                fokus: { [weak self] p in self?.fokusSetzen(p, tastatur: true) })
            k.cols = box.cols
            k.rows = box.rows
            neueKacheln.append(k)
            zuFuettern.append((t, box))
        }
        for f in neu.fehlend where !f.pane.isEmpty {
            let k = Kachel(pane: f.pane, terminal: nil, zoom: { _ in }, zurueck: {}, fokus: { _ in })
            k.fehlt(f.grund)
            neueKacheln.append(k)
        }
        for alt in kacheln where !neueKacheln.contains(where: { $0 === alt }) { alt.removeFromSuperview() }
        for k in neueKacheln where k.superview == nil { flaeche.addSubview(k) }
        for (pane, t) in terminals where !gesehen.contains(pane) {
            t.removeFromSuperview()
            terminals[pane] = nil
        }
        kacheln = neueKacheln
        kachelZeilen = Kachelung.zeilenZahl(neu)
        aktiv = gesehen.contains(neu.aktiv) ? neu.aktiv : (neueKacheln.first { $0.fehltGrund == nil }?.pane ?? "")
        legen()
        // ERST LIEGEN, DANN FUETTERN (08.09.2026, Auftrag geometrie, vierte
        // Runde -- urspruenglicher des Nutzers Befund „manchmal direkt nach dem
        // Fensteroeffnen, behebt sich nach kurzer Zeit selbst").
        //
        // SwiftTerm rechnet seine Groesse aus dem RAHMEN: `setFrameSize` ruft
        // `processSizeChange`, das `newCols` aus der nutzbaren Breite geteilt
        // durch die Zellbreite bildet -- und die nutzbare Breite ist die
        // Rahmenbreite MINUS dem Rollbalken. Jede Rahmenaenderung ist damit
        // eine Groessenaenderung des Terminals, und die bricht den Inhalt neu
        // um. Beim ERSTEN Zeigen einer Kachel geht ihr Rahmen von Null auf
        // seine echte Groesse, also feuert das immer.
        //
        // Bis hierher wurde deshalb genau in der falschen Reihenfolge
        // gearbeitet: fuettern, dann legen. Der frisch gesetzte Schirm lief
        // durch das Umbrechen des Rahmenwechsels, und was dabei ueber den
        // oberen Rand rollte, lag im Rueckblick und kam nicht zurueck.
        // GEMESSEN kopflos mit einem Programm, das auf SIGWINCH sofort absolut
        // neu zeichnet: die Kachel war 52 Spalten breit, im Terminal stand
        // aber eine Zeile, die bei 49 umgebrochen war -- der Breite, die der
        // Rahmen fuer einen Augenblick hergab. Danach zeigte der Schirm
        // `ZEILE-2` dort, wo der Pane `ZEILE-1` hatte, und jeder spaetere
        // Layoutwechsel stellte es her.
        //
        // Jetzt liegen die Kacheln zuerst: `legen()` setzt jeden Rahmen, und
        // `Kachel.anordnen` bringt das Terminal danach auf genau die Zellen der
        // Kachel. Erst dann geht der Schirm hinein -- in ein Terminal, dessen
        // Groesse steht und sich nicht mehr aendert.
        for (t, box) in zuFuettern {
            t.einspielen(pane: box.paneId, lage: neu, cols: box.cols, rows: box.rows)
        }
        kopfzeilenNachziehen()
        if let t = terminals[aktiv], let w = window, w.firstResponder !== t { w.makeFirstResponder(t) }
        meldungAnstossen()
        nachfordern()
    }

    /// Wie oft die Buehne fuer die gemeldete Groesse schon nachgefordert wurde.
    private var nachgefordert = 0

    /// Passt ein Pane nicht in seine Kachel, obwohl die Buehne gemeldet ist,
    /// hat der Kern die Meldung nicht mehr umgesetzt (zwei Durchgaenge von
    /// `flaecheSetzen`, der aeltere gewann -- gemessen 06.09.: sechs Kacheln
    /// zu 23 Zeilen, die Panes blieben auf 24). Dieselbe Zahl noch einmal
    /// gemeldet laesst ihn neu zeichnen (paneflaeche.ts `nachfordern`); hoechstens
    /// zweimal je Meldung, damit daraus kein Kreis wird.
    private func nachfordern() {
        guard art == .strom, gemeldet.cols > 0, nachgefordert < 2 else { return }
        let z = zelle
        let passtNicht = kacheln.contains { k in
            guard k.terminal != nil, k.cols > 0, k.rows > 0 else { return false }
            let innen = k.bounds.height - (k.kopfSichtbar ? KachelKopf.hoehe : 0)
            return CGFloat(k.rows) * z.hoehe > innen + 0.5 || CGFloat(k.cols) * z.breite > k.bounds.width + 0.5
        }
        guard passtNicht else { return }
        nachgefordert += 1
        kern.flaeche(cols: gemeldet.cols, rows: gemeldet.rows)
    }

    /// Die Kacheln in die Flaeche legen: erst in Terminalflaeche gerechnet,
    /// dann je Kachelzeile um eine Kopfzeile nach unten versetzt und um sie
    /// hoeher gemacht (paneflaeche.ts, „DIE KOPFZEILEN KOMMEN OBEN DRAUF").
    private func legen() {
        guard art == .strom, let lage else { return }
        let roh = flaeche.bounds.size
        guard roh.width > 0, roh.height > 0 else { return }
        let z = zelle
        let tf = Kachelung.terminalflaeche(roh: roh, kopf: KachelKopf.hoehe, kachelZeilen: kachelZeilen)
        let rechtecke = Kachelung.kacheln(lage, zelle: z, flaeche: tf)
        gelegt = rechtecke
        let reihen = Kachelung.reihenIndex(rechtecke)
        for (i, k) in kacheln.enumerated() {
            guard i < rechtecke.count else { k.isHidden = true; continue }
            let r = rechtecke[i]
            let y = r.y + CGFloat(reihen[i]) * KachelKopf.hoehe
            // AppKit zaehlt von unten: die Kachel liegt bei `y` von oben.
            let h = r.h + KachelKopf.hoehe
            k.isHidden = false
            k.frame = NSRect(x: r.x.rounded(), y: (roh.height - y - h).rounded(), width: r.b.rounded(), height: h.rounded())
            k.anordnen(zelle: z)
        }
    }

    override func layout() {
        super.layout()
        legen()
        meldungAnstossen()
    }

    /// Die Kopfzeilen fuellen -- im Takt des Fensters, weil der Name aus dem
    /// Modell kommt und das eigenen Takt hat (paneflaeche.ts `zeigeNamen`).
    func kopfzeilenNachziehen() {
        // Die Tastatur kann auch ohne Klick wandern (Tab-Taste, Programm):
        // `becomeFirstResponder` ist in SwiftTerm nicht ueberschreibbar, also
        // wird hier im Takt nachgesehen, wer sie hat.
        if let t = window?.firstResponder as? StromTerminal, terminals[t.pane] === t, t.pane != aktiv { aktiv = t.pane }
        let mehrere = kacheln.count > 1
        let gezoomt = lageArt == "pane"
        for k in kacheln {
            let d = kopfZuPane?(k.pane) ?? KachelKopfDaten()
            k.nachziehen(daten: d, aktiv: k.pane == aktiv, gezoomt: gezoomt, mehrere: mehrere)
        }
    }

    /// Der Fokus folgt der Kachel: Klick oder Tastatur im Terminal, Klick auf
    /// die Kopfzeile (`tastatur`: das Terminal bekommt sie dann auch).
    func fokusSetzen(_ pane: String, tastatur: Bool = false) {
        guard terminals[pane] != nil else { return }
        if tastatur, let t = terminals[pane], let w = window, w.firstResponder !== t { w.makeFirstResponder(t) }
        guard pane != aktiv else { return }
        aktiv = pane
        kopfzeilenNachziehen()
    }

    /// Escape ausserhalb eines Terminals: aus dem Zoom zurueck zu allen Kacheln.
    /// IM Terminal gehoert Escape der Anwendung dort (vi, readline) -- deshalb
    /// nur hier, und daneben ⌘↩ im Menue Darstellung (Kachel zoomen).
    override func cancelOperation(_ sender: Any?) {
        if lageArt == "pane" { aufZurueck?() }
    }

    /// WIE LANGE EINE BEWEGUNG NACHKLINGEN DARF, bevor gemeldet wird. Ein Bild
    /// der Animation kommt alle 16 ms; 80 ms liegen darueber und unter allem,
    /// was ein Mensch als Verzoegerung bemerkt.
    static let melderuhe: TimeInterval = 0.08
    /// Dieselbe Ruhe nach einem Zug an der Seitenleiste oder am Inspektor:
    /// AppKit animiert das Ein- und Ausklappen etwa eine Viertelsekunde, und
    /// erst danach darf die Aufteilung zu Ende gelegt werden -- frueher risse
    /// die Bewegung mitten im Bild ab.
    static let bewegungsruhe: TimeInterval = 0.35
    /// Der Abstand zweier Blicke, mit denen das Ende einer laengeren Bewegung
    /// festgestellt wird.
    static let nachschau: TimeInterval = 0.1

    /// DIE MELDUNG KOMMT AM ENDE DER BEWEGUNG, NICHT BEI JEDEM ZWISCHENWERT
    /// (08.09.2026, Befund des Nutzers „wenn ich links die Leiste einklappe, ist
    /// mein Cursor an der falschen Stelle und die Statusleiste ist weg, bis ich
    /// das Fenster resize").
    ///
    /// GEMESSEN, ZWEIERLEI: Ein Ein- oder Ausklappen der Seitenleiste ist
    /// animiert, und waehrend der Bewegung legt AppKit die Flaeche viele Male
    /// neu. Bis heute ging JEDER Zwischenwert an den Kern -- bei sechs Kacheln
    /// vierundzwanzig Meldungen je Zug, also vierundzwanzig Groessenwechsel in
    /// tmux und ebenso viele SIGWINCH in jedes Programm darin. Und schlimmer:
    /// der LETZTE Layoutdurchgang faellt nicht ans Ende der Animation. Bei
    /// einer einzelnen Kachel kam die letzte Meldung mitten aus der Bewegung
    /// (gemessen: 119 Spalten statt 149 beim Einklappen, 150 statt 120 beim
    /// Ausklappen, in zwei von vier Zuegen), und danach kam nichts mehr: das
    /// Programm im Pane zeichnete gegen eine Groesse, die es nie bekommen hat.
    /// Genau das raeumt der naechste Zug am Fensterrand auf.
    ///
    /// Also wird gesammelt: jeder Layoutdurchgang und jeder Schritt der
    /// Seitenleiste (`flaecheSpaeterMelden` aus dem Fenster) setzen die Uhr
    /// neu; erst wenn die Bewegung steht, wird EINMAL zu Ende gelegt, gemessen
    /// und gemeldet.
    /// Die Uhr stellen -- `.common`, damit sie auch waehrend eines Zuges am
    /// Fensterrand laeuft (dort haelt AppKit den Runloop im Modus
    /// `eventTracking`, und im Vorgabemodus schwiege sie bis zum Loslassen).
    private func uhrStellen(_ ruhe: TimeInterval) {
        meldeUhr?.invalidate()
        let uhr = Timer(timeInterval: ruhe, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.meldungAbschicken() }
        }
        meldeUhr = uhr
        RunLoop.main.add(uhr, forMode: .common)
    }

    /// Aus dem Terminal (SwiftTerm meldet seine neue Zellzahl) -- derselbe Weg.
    private func groesseGemeldet() { meldungAnstossen() }

    /// Aus einem Layoutdurchgang. Waehrend einer Bewegung schweigt er ganz;
    /// sonst sammelt er, was in `melderuhe` anfaellt, zu EINER Meldung.
    private func meldungAnstossen() {
        guard art == .strom, !imMelden, !inBewegung else { return }
        if let u = meldeUhr, u.isValid { return }
        uhrStellen(Self.melderuhe)
    }

    /// Von aussen (Fenster): die Seitenleiste oder der Inspektor bewegt sich.
    /// Mit `bewegungsruhe` heisst das: bis dahin wird gar nichts gemeldet, und
    /// danach wird nachgesehen, ob die Bewegung wirklich steht.
    func flaecheSpaeterMelden(ruhe: TimeInterval = TerminalBereich.melderuhe) {
        guard art == .strom else { return }
        guard ruhe >= Self.bewegungsruhe else { meldungAnstossen(); return }
        inBewegung = true
        letzteBewegung = .zero
        uhrStellen(ruhe)
    }

    /// Was VOR dem Messen noch zu Ende gelegt werden muss -- das Fenster haengt
    /// hier das Nachziehen der Aufteilung ein.
    var vorDemMelden: (() -> Void)?

    private func meldungAbschicken() {
        meldeUhr = nil
        imMelden = true
        // Erst zu Ende legen, dann messen.
        vorDemMelden?()
        needsLayout = true
        layoutSubtreeIfNeeded()
        let jetzt = flaeche.bounds.size
        imMelden = false
        // STEHT DIE BEWEGUNG WIRKLICH? Dauert die Animation laenger als
        // `bewegungsruhe`, waere die Zahl hier ein Zwischenwert. Also erst
        // melden, wenn zwei Blicke im Abstand von `nachschau` dieselbe Flaeche
        // sehen.
        if inBewegung, jetzt != letzteBewegung {
            letzteBewegung = jetzt
            uhrStellen(Self.nachschau)
            return
        }
        inBewegung = false
        imMelden = true
        flaecheMelden()
        imMelden = false
    }

    /// Die Buehne an den Kern (`awb:mantel-flaeche`): die Flaeche fuer
    /// Terminals in Zellen -- ohne die Kopfzeilen und ohne die Fugen der
    /// aktuellen Lage (`Kachelung.fugen`), damit der Kern Kacheln schneidet,
    /// die in ihre Flaeche passen.
    private func flaecheMelden() {
        guard art == .strom else { return }
        let roh = flaeche.bounds.size
        guard roh.width > 0, roh.height > 0 else { return }
        let tf = Kachelung.terminalflaeche(roh: roh, kopf: KachelKopf.hoehe, kachelZeilen: kachelZeilen)
        let f = lage.map { Kachelung.fugen($0) } ?? (waagerecht: 0, senkrecht: 0)
        let ohneFugen = CGSize(width: tf.width - CGFloat(f.waagerecht) * Kachelung.fuge, height: tf.height - CGFloat(f.senkrecht) * Kachelung.fuge)
        guard let roh2 = Kachelung.zellen(flaeche: ohneFugen, zelle: zelle) else { return }
        // GEMELDET WIRD NUR, WAS SICH GLATT TEILEN LAESST (08.09.2026).
        //
        // Der Kern teilt die gemeldeten Zellen gleichmaessig auf die Kacheln
        // (`capacity.ts`, `kachelZellen`), tmux legt sie danach selbst -- und
        // tmux verschenkt den Rest nicht: aus 47 Zeilen auf zwei Kachelzeilen
        // macht es 23 und 24. Die Kachelrechnung hier gibt beiden Zeilen
        // dieselbe Hoehe, also 23. Der Pane mit 24 Zeilen zeichnet dann eine
        // Zeile ueber seine Kachel hinaus (gemessen 08.09. unter Last:
        // „Terminal [384, 384] ragt aus der Kachel 384x368", sechsmal, und es
        // stand still -- die Wartezeit der Suite half nicht, weil nichts mehr
        // nachkam).
        //
        // Also wird abgerundet, bis es aufgeht: Zeilen auf ein Vielfaches der
        // Kachelzeilen, Spalten auf ein Vielfaches der dichtesten Zeile. Was
        // dabei wegfaellt, ist hoechstens eine Zellenreihe am Rand -- und die
        // war ohnehin nicht darstellbar.
        let proZeile = max(1, f.waagerecht + 1)
        let zeilen = max(1, kachelZeilen)
        let z = (cols: max(20, roh2.cols - roh2.cols % proZeile),
                 rows: max(5, roh2.rows - roh2.rows % zeilen))
        guard z.cols != gemeldet.cols || z.rows != gemeldet.rows else { return }
        gemeldet = z
        nachgefordert = 0
        meldungen += 1
        kern.flaeche(cols: z.cols, rows: z.rows)
    }

    /// Die Panes der Buehne in Lage-Reihenfolge (ohne fehlende).
    var gezeigtePanes: [String] {
        switch art {
        case .strom: return kacheln.filter { $0.fehltGrund == nil }.map(\.pane)
        case .attach: return attach.map { [$0.sitzung] } ?? []
        }
    }

    /// Die gewaehlte Sitzung hat gewechselt (attach: neuen Client starten).
    func sitzungGewechselt(_ s: SitzungsEintrag?) {
        guard art == .attach else { return }
        attach?.anhaengen(sitzung: s?.tmuxSession ?? "", tmuxBin: optionen.tmuxBin, socket: optionen.tmuxSocket)
    }

    var gezeigterPane: String {
        switch art {
        case .strom: return aktiv
        case .attach: return attach?.sitzung ?? ""
        }
    }

    var cols: Int { terminal.getTerminal().cols }
    var rows: Int { terminal.getTerminal().rows }

    /// Der sichtbare Schirm des Terminals mit der Tastatur als Zeilen, rechts beschnitten.
    func schirmZeilen() -> [String] {
        schirmZeilen(terminal)
    }

    func schirmZeilen(_ tv: TerminalView) -> [String] {
        let t = tv.getTerminal()
        return (0..<t.rows).map { t.getLine(row: $0)?.translateToString(trimRight: true) ?? "" }
    }

    /// Der Schirm eines bestimmten Panes der Buehne.
    func schirmZeilen(pane: String) -> [String]? {
        terminals[pane].map { schirmZeilen($0) }
    }

    /// Was an einer Zelle steht, wenn dort ein Pfad steht (Auftrag 3.6) --
    /// derselbe Erkenner, den der ⌘-Klick des Menschen benutzt. Ohne `pane`
    /// gilt die Kachel mit der Tastatur. Geoeffnet wird hier nichts: das tut der
    /// Aufrufer, damit der Steuerkanal auf das Ergebnis warten kann.
    func pfadUnter(pane: String, zeile: Int, spalte: Int) -> String? {
        let ziel = pane.isEmpty ? terminal : terminals[pane]
        guard let t = ziel as? StromTerminal else { return nil }
        return t.pfadUnter(zeile: zeile, spalte: spalte)
    }

    /// Tastendruecke, so wie der Mensch sie tippt: durch dieselbe Stelle wie die
    /// Tastatur -- in das Terminal, das sie hat.
    func tippen(_ text: String) {
        terminal.send(txt: text)
    }

    private func bildGemeldet() {
        bildZaehler += 1
    }

    /// Die Auskunft ueber die gelegten Kacheln fuer `awbmac-ctl ui`.
    func kachelAuskunft() -> [[String: Any]] {
        let roh = flaeche.bounds.size
        return kacheln.enumerated().map { i, k in
            // Zurueck in die Rechnung des Renderers: y von oben.
            let f = k.frame
            let r: [String: Any] = [
                "pane": k.pane, "name": k.daten.name, "zustand": k.daten.zustand, "modell": k.daten.modell, "tokens": k.daten.tokens,
                "x": Int(f.minX), "y": Int(roh.height - f.maxY), "b": Int(f.width), "h": Int(f.height),
                "kopf": k.kopfSichtbar ? Int(KachelKopf.hoehe) : 0,
                "cols": k.cols, "rows": k.rows, "aktiv": k.pane == aktiv, "fehlt": k.fehltGrund != nil, "grund": k.fehltGrund ?? "",
                "terminalCols": k.terminal?.getTerminal().cols ?? 0, "terminalRows": k.terminal?.getTerminal().rows ?? 0,
                "schirm": k.terminal.map { [Int($0.frame.width), Int($0.frame.height)] } ?? [0, 0],
                // Wo die Terminalansicht IN der Kachel sitzt (y von oben, die
                // Kachel ist gespiegelt): damit eine Pruefung nicht nur die
                // Groesse, sondern die LAGE gegen die Kachel halten kann --
                // die unterste Zeile des Panes darf nie unter die Kante rutschen.
                "schirmY": k.terminal.map { Int($0.frame.minY.rounded()) } ?? 0,
                "reihe": i < gelegt.count ? Kachelung.reihenIndex(gelegt)[i] : 0,
            ]
            return r
        }
    }

    var buehneGroesse: (b: Int, h: Int) { (Int(flaeche.bounds.width), Int(flaeche.bounds.height)) }

    /// Wartet auf das naechste Neuzeichnen, hoechstens `ms` Millisekunden.
    func naechstesBild(ms: Int) async -> Bool {
        let start = bildZaehler
        let frist = DispatchTime.now().uptimeNanoseconds + UInt64(ms) * 1_000_000
        while DispatchTime.now().uptimeNanoseconds < frist {
            if bildZaehler != start { return true }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return false
    }

    /// Latenz Tastendruck -> Zeichen auf dem Schirm, `runden` Mal, in Millisekunden.
    /// Setzt voraus, dass der Pane tippt, was er bekommt (z. B. `cat`).
    func latenzMessen(runden: Int) async -> [Double] {
        var werte: [Double] = []
        for i in 0..<max(1, runden) {
            let marke = "m\(i)q"
            let start = DispatchTime.now().uptimeNanoseconds
            tippen(marke)
            var gesehen = false
            let frist = start + 3_000_000_000
            while DispatchTime.now().uptimeNanoseconds < frist {
                if schirmZeilen().contains(where: { $0.contains(marke) }) { gesehen = true; break }
                try? await Task.sleep(for: .milliseconds(1))
            }
            let ende = DispatchTime.now().uptimeNanoseconds
            werte.append(gesehen ? Double(ende - start) / 1_000_000.0 : -1)
            // Zeile beenden, damit die naechste Marke sauber steht.
            tippen("\r")
            try? await Task.sleep(for: .milliseconds(50))
        }
        return werte
    }

    /// Alles auswaehlen und den Text der Auswahl liefern (Pruefung Auswahl/Kopieren).
    func allesAuswaehlen() -> String? {
        terminal.selectAll()
        return terminal.getSelection()
    }

    /// Den Zoom des gezeigten Panes umschalten und messen, wie lange das Neuzeichnen braucht.
    func zoomMessen() async -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        switch art {
        case .strom:
            // Der Kern zoomt den Pane (paneZeigen zoomt, `resize-pane -Z`) und schickt eine neue Lage.
            let pane = aktiv
            guard !pane.isEmpty else { return -1 }
            kern.paneZeigen(pane)
            let vorher = lageZaehler
            let frist = start + 3_000_000_000
            var da = false
            while DispatchTime.now().uptimeNanoseconds < frist {
                if lageZaehler != vorher { da = true; break }
                try? await Task.sleep(for: .milliseconds(1))
            }
            return da ? Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000.0 : -1
        case .attach:
            // Praefix + z, so wie ein Mensch am tmux-Client.
            attach?.send(data: ArraySlice([0x02, UInt8(ascii: "z")]))
        }
        let gekommen = await naechstesBild(ms: 3000)
        let ende = DispatchTime.now().uptimeNanoseconds
        return gekommen ? Double(ende - start) / 1_000_000.0 : -1
    }
}
