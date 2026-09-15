// Der Editor-Baustein (Auftrag 3.3): ein Blatt, das eine Datei zeigt, den
// Cursor auf Zeile:Spalte setzt, sucht, kopiert und seine Schrift wechselt.
// NSTextView mit TextKit 2 (NSTextLayoutManager) und Syntaxfaerbung ueber
// Highlightr (highlight.js in JavaScriptCore); Auswahl, Dienste, Rechtschreibung,
// Dark Mode und Schrift kommen vom System.
//
// GEMESSEN GEGEN MONACO IN EINEM WKWebView (06.09.2026, mac/PLAN-EDITOR.md): die
// Monaco-Fassung stand hinter derselben Schnittstelle `EditorBaustein` im
// Commit f435811 und wurde nach der Entscheidung entfernt; die Schnittstelle
// bleibt, damit `mac/messungen/editor/editor-messung.sh` dieselben Griffe misst.
//
// `EditorAnsicht` ist der Baustein fuer Auftrag 3.4 (Editor-Blatt);
// `EditorFenster` haelt ihn fuer den Steuerkanal in einem nie gezeigten
// Fenster, wie die Einstellungen.
//
// Kopflos misst der Steuerkanal „bis zum fertigen Layout“: der Sichtausschnitt
// des NSTextLayoutManager. Gezeichnet wird ausserhalb des Bildschirms nichts.
//
// Textstile und Systemfarben: die Schrift ist die Monospace-Systemschrift in
// der Systemgroesse (NSFont.systemFontSize, keine feste Zahl), Grund und Text
// sind `textBackgroundColor` und `textColor`; nur die Token-Farben kommen aus
// dem Farbschema des Hervorhebers und folgen dem Erscheinungsbild.
import AppKit
import Highlightr

/// Die Fassung des Bausteins -- seit der Entscheidung nur noch `text` (mac/PLAN-EDITOR.md).
enum EditorFassung: String, Sendable {
    case text
}

/// Was ein Editor koennen muss, damit Blatt (3.4) und Messung ihn gleich anfassen.
@MainActor
protocol EditorBaustein: AnyObject {
    var view: NSView { get }
    var fassung: EditorFassung { get }
    /// Faehig zum Messen: die Fassung ist geladen.
    func bereit(frist: Duration) async -> Bool
    /// Text laden; zurueck kommt die Zeit bis zum lesbaren Layout und bis zur Faerbung (ms).
    func oeffnen(text: String, sprache: String) async -> (lesbarMs: Double, gefaerbtMs: Double)
    /// Ganze Zeilen auswaehlen (`von` bis `bis`, beide einschliesslich) -- der Weg der Maus.
    func auswahlSetzen(von: Int, bis: Int) async
    /// Die Auswahl: ihr Text und die Zeilen, ueber die sie geht. Leer, wenn nichts markiert ist.
    func auswahl() async -> (text: String, von: Int, bis: Int)
    func cursorSetzen(zeile: Int, spalte: Int) async
    func cursor() async -> (zeile: Int, spalte: Int)
    func zeilen() async -> Int
    /// Alle Treffer zaehlen, den ersten auswaehlen; Zeit in ms.
    func suchen(_ text: String) async -> (treffer: Int, ms: Double)
    /// n Anschlaege an der Cursorstelle, je Anschlag die Zeit bis zum fertigen Layout (ms).
    func tippen(runden: Int) async -> [Double]
    /// Zeilen von..bis auswaehlen und kopieren; der kopierte Text.
    func kopieren(von: Int, bis: Int) async -> String
    /// Schriftgroesse setzen; Zeit bis zum neuen Layout (ms).
    func schrift(groesse: Double) async -> Double
    func schriftGroesse() async -> Double
    /// Dem Erscheinungsbild folgen (hell/dunkel); die Grundfarbe danach als Hex.
    func erscheinung(dunkel: Bool) async -> String
    func hintergrund() async -> String
    func textLesen() async -> String
}

// MARK: - Sprachwahl

enum EditorSprache {
    /// Die Sprache aus der Dateiendung, im Namen von highlight.js.
    static func fuer(pfad: String) -> String {
        switch (pfad as NSString).pathExtension.lowercased() {
        case "ts", "tsx": return "typescript"
        case "js", "mjs", "cjs", "jsx": return "javascript"
        case "swift": return "swift"
        case "py": return "python"
        case "sh", "bash", "zsh": return "bash"
        case "md", "markdown": return "markdown"
        case "json": return "json"
        case "yml", "yaml": return "yaml"
        case "css": return "css"
        case "html", "htm": return "xml"
        case "rs": return "rust"
        case "go": return "go"
        case "c", "h": return "c"
        case "cpp", "cc", "hpp": return "cpp"
        default: return "plaintext"
        }
    }
}

// MARK: - Fassung text: NSTextView + TextKit 2 + Highlightr

/// Ein NSTextView, dessen ⌘C ueber die Zwischenablage des Bereichs laeuft --
/// kopflos ein Merker, nie NSPasteboard.general (regeln/tests-und-eingriffe.md).
@MainActor
final class EditorTextView: NSTextView {
    var zwischenablage: Zwischenablage?

    override func copy(_ sender: Any?) {
        guard let z = zwischenablage, z.kopflos else { super.copy(sender); return }
        let r = selectedRange()
        z.schreiben((string as NSString).substring(with: r))
    }
}

/// Highlightr auf einer seriellen Warteschlange: der JSContext von highlight.js
/// vertraegt keinen gleichzeitigen Zugriff, und Thema, Schrift und Faerbung
/// gehen alle durch dieselbe Instanz.
final class Hervorheber: @unchecked Sendable {
    private let h: Highlightr
    private let queue = DispatchQueue(label: "agent-workbench.werkbank.hervorheber")

    init?() {
        guard let h = Highlightr() else { return nil }
        self.h = h
    }

    func thema(_ name: String, schrift: NSFont) {
        queue.sync {
            _ = h.setTheme(to: name)
            h.theme.setCodeFont(schrift)
        }
    }

    func schrift(_ f: NSFont) { queue.sync { h.theme.setCodeFont(f) } }

    /// Faerbt im Hintergrund; das Ergebnis kommt als unveraenderliche Kopie.
    func faerben(_ code: String, sprache: String) async -> NSAttributedString? {
        await withCheckedContinuation { (c: CheckedContinuation<NSAttributedString?, Never>) in
            queue.async {
                let r = self.h.highlight(code, as: sprache, fastRender: true).map { NSAttributedString(attributedString: $0) }
                nonisolated(unsafe) let ergebnis = r
                c.resume(returning: ergebnis)
            }
        }
    }
}

/// WARUM EIN EIGENER SPEICHER UND NICHT Highlightrs CodeAttributedString (gemessen
/// 06.09.2026): der Swift-Unterklasse von NSTextStorage kostet jeder Attributlauf
/// eine Bruecke Dictionary <-> NSDictionary; ein Schriftwechsel ueber 5000 Zeilen
/// (rund 60 000 Laeufe) brauchte damit 1040 ms allein fuer die Attribute. Ein
/// NSTextStorage aus AppKit, auf den die Faerbung von aussen gelegt wird, kommt
/// ohne die Bruecke aus. Dafuer faerbt diese Klasse selbst: beim Oeffnen den
/// ganzen Text, beim Tippen den Absatz (NSTextStorageDelegate), bei Thema und
/// Schrift nur die Attribute.
@MainActor
final class TextKitEditor: NSView, EditorBaustein, NSTextStorageDelegate {
    let fassung = EditorFassung.text
    var view: NSView { self }
    let textView: EditorTextView
    let rollen: NSScrollView
    let speicher = NSTextStorage()
    let hervorheber: Hervorheber
    private var sprache: String?
    private var schriftPunkt: Double = NSFont.systemFontSize
    private let kopflos: Bool
    /// Wer auf die naechste Faerbung wartet (Messung, Oeffnen).
    private var gefaerbtFortsetzung: CheckedContinuation<Void, Never>?
    private var faerbungGeneration = 0
    /// Anstehende Faerbungen (Absaetze nach dem Tippen), nacheinander.
    private var faerbungLaeuft = false
    private var faerbungWunsch: NSRange?
    /// Die Teilzeiten des letzten Schriftwechsels (Attribute, endEditing, Layout), ms.
    private(set) var schriftPhasen: [Double] = []
    /// Was die letzte Faerbung tat (fuer `ui.editor`): Laeufe oder der Grund des Verwerfens.
    private(set) var letzteFaerbung = ""
    /// Der Mensch hat getippt (Auftrag 3.4): das Blatt macht daraus den
    /// Aenderungspunkt am Tab. Ein programmatisches Laden loest ihn NICHT aus.
    var beiAenderung: (() -> Void)?
    private var laedt = false

    init(zwischenablage: Zwischenablage, kopflos: Bool) {
        self.kopflos = kopflos
        // Highlightr laedt highlight.min.js in einen JSContext; ohne ihn keine Faerbung.
        hervorheber = Hervorheber()!
        // TextKit 2 von Hand zusammengesetzt: Inhalt -> Layout -> Container -> View.
        let inhalt = NSTextContentStorage()
        inhalt.textStorage = speicher
        let layout = NSTextLayoutManager()
        inhalt.addTextLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.textContainer = container
        textView = EditorTextView(frame: .zero, textContainer: container)
        rollen = NSScrollView(frame: .zero)
        super.init(frame: .zero)
        speicher.delegate = self
        textView.zwischenablage = zwischenablage
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.insertionPointColor = .textColor
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.setAccessibilityLabel("Editor")
        rollen.documentView = textView
        rollen.hasVerticalScroller = true
        rollen.hasHorizontalScroller = false
        rollen.autohidesScrollers = true
        rollen.drawsBackground = true
        rollen.backgroundColor = .textBackgroundColor
        rollen.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rollen)
        NSLayoutConstraint.activate([
            rollen.leadingAnchor.constraint(equalTo: leadingAnchor), rollen.trailingAnchor.constraint(equalTo: trailingAnchor),
            rollen.topAnchor.constraint(equalTo: topAnchor), rollen.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        themaAnwenden(dunkel: effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        themaAnwenden(dunkel: effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
    }

    private var schrift: NSFont { NSFont.monospacedSystemFont(ofSize: schriftPunkt, weight: .regular) }

    /// Das Farbschema der Token folgt dem Erscheinungsbild; Grund und Text
    /// bleiben Systemfarben (das Schema bringt eigene mit, die hier nicht gelten).
    private func themaAnwenden(dunkel: Bool) {
        hervorheber.thema(dunkel ? "xcode-dark" : "xcode", schrift: schrift)
        textView.font = schrift
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .textColor
        if sprache != nil { Task { @MainActor in await self.faerben(NSRange(location: 0, length: self.speicher.length)) } }
    }

    // MARK: Faerbung

    /// Einen Bereich (auf Absaetze geweitet) faerben; das Ergebnis gilt nur,
    /// wenn der Text dort noch derselbe ist.
    private func faerben(_ bereich: NSRange) async {
        guard let sprache else { faerbungFertig(); return }
        let s = speicher.string as NSString
        let r = s.paragraphRange(for: NSRange(location: min(bereich.location, s.length), length: min(bereich.length, s.length - min(bereich.location, s.length))))
        let stueck = s.substring(with: r)
        guard let ergebnis = await hervorheber.faerben(stueck, sprache: sprache) else { letzteFaerbung = "kein Ergebnis"; faerbungFertig(); return }
        let jetzt = speicher.string as NSString
        guard r.location + r.length <= jetzt.length, jetzt.substring(with: r) == ergebnis.string else {
            letzteFaerbung = "verworfen: Text \(ergebnis.length) gegen \(r.length) Zeichen"
            faerbungFertig(); return
        }
        var laeufe = 0
        speicher.beginEditing()
        ergebnis.enumerateAttributes(in: NSRange(location: 0, length: ergebnis.length)) { attrs, teil, _ in
            laeufe += 1
            speicher.setAttributes(attrs, range: NSRange(location: r.location + teil.location, length: teil.length))
        }
        speicher.endEditing()
        letzteFaerbung = "ok: \(laeufe) Laeufe, \(r.length) Zeichen"
        faerbungFertig()
    }

    private func faerbungFertig() {
        gefaerbtFortsetzung?.resume()
        gefaerbtFortsetzung = nil
    }

    /// `tun` ausfuehren und auf die Faerbung warten, die es ausloest -- hoechstens `frist`.
    private func faerbungAbwarten(frist: Duration = .seconds(30), _ tun: () -> Void) async {
        faerbungGeneration += 1
        let g = faerbungGeneration
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            gefaerbtFortsetzung = c
            tun()
            Task { @MainActor in
                try? await Task.sleep(for: frist)
                if self.faerbungGeneration == g { self.faerbungFertig() }
            }
        }
    }

    /// Nach jeder Aenderung des Textes: den Absatz neu faerben, nacheinander.
    nonisolated func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        MainActor.assumeIsolated {
            faerbungWunsch = faerbungWunsch.map { NSUnionRange($0, editedRange) } ?? editedRange
            if !laedt { beiAenderung?() }
            Task { @MainActor in await self.wunschAbarbeiten() }
        }
    }

    private func wunschAbarbeiten() async {
        guard !faerbungLaeuft, let w = faerbungWunsch else { return }
        faerbungWunsch = nil
        faerbungLaeuft = true
        await faerben(w)
        faerbungLaeuft = false
        if faerbungWunsch != nil { await wunschAbarbeiten() }
    }

    // MARK: Layout und Stellen

    private func layoutAbschliessen() {
        textView.layoutSubtreeIfNeeded()
        textView.textLayoutManager?.textViewportLayoutController.layoutViewport()
    }

    private func offset(zeile: Int, spalte: Int) -> Int {
        let s = speicher.string as NSString
        var z = 1, i = 0
        while z < zeile, i < s.length {
            let r = s.lineRange(for: NSRange(location: i, length: 0))
            i = r.location + r.length
            z += 1
        }
        let zeilenEnde = s.lineRange(for: NSRange(location: min(i, s.length), length: 0))
        let inhalt = s.substring(with: zeilenEnde).trimmingCharacters(in: .newlines)
        return min(i + max(0, spalte - 1), i + (inhalt as NSString).length)
    }

    private func zeileSpalte(offset o: Int) -> (Int, Int) {
        let s = speicher.string as NSString
        let vorher = s.substring(to: min(o, s.length)) as NSString
        let zeilen = vorher.components(separatedBy: "\n").count
        let letzter = vorher.range(of: "\n", options: .backwards)
        let start = letzter.location == NSNotFound ? 0 : letzter.location + 1
        return (zeilen, o - start + 1)
    }

    // MARK: EditorBaustein

    func bereit(frist: Duration) async -> Bool { true }

    func oeffnen(text: String, sprache neu: String) async -> (lesbarMs: Double, gefaerbtMs: Double) {
        let t0 = ContinuousClock.now
        // Erst der Text ohne Sprache (lesbar, in Systemschrift und -farbe), dann
        // die Sprache, die den ganzen Text im Hintergrund faerbt.
        sprache = nil
        laedt = true
        speicher.beginEditing()
        speicher.replaceCharacters(in: NSRange(location: 0, length: speicher.length), with: text)
        speicher.setAttributes([.font: schrift, .foregroundColor: NSColor.textColor], range: NSRange(location: 0, length: speicher.length))
        speicher.endEditing()
        laedt = false
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        layoutAbschliessen()
        let lesbar = ContinuousClock.now - t0
        sprache = neu
        await faerbungAbwarten { Task { @MainActor in await self.faerben(NSRange(location: 0, length: self.speicher.length)) } }
        return (ms(lesbar), ms(ContinuousClock.now - t0))
    }

    func cursorSetzen(zeile: Int, spalte: Int) async {
        let o = offset(zeile: zeile, spalte: spalte)
        textView.setSelectedRange(NSRange(location: o, length: 0))
        textView.scrollRangeToVisible(NSRange(location: o, length: 0))
        layoutAbschliessen()
    }

    func cursor() async -> (zeile: Int, spalte: Int) {
        zeileSpalte(offset: textView.selectedRange().location)
    }

    /// Zeilen wie `wc -l` sie zaehlt, plus eine letzte Zeile ohne Umbruch.
    func zeilen() async -> Int {
        let s = speicher.string
        if s.isEmpty { return 0 }
        return s.reduce(into: 0) { if $1 == "\n" { $0 += 1 } } + (s.hasSuffix("\n") ? 0 : 1)
    }

    func suchen(_ text: String) async -> (treffer: Int, ms: Double) {
        let t0 = ContinuousClock.now
        let s = speicher.string as NSString
        var n = 0
        var erster: NSRange?
        var von = 0
        while von < s.length {
            let r = s.range(of: text, options: [], range: NSRange(location: von, length: s.length - von))
            if r.location == NSNotFound { break }
            n += 1
            if erster == nil { erster = r }
            von = r.location + max(1, r.length)
        }
        if let e = erster {
            textView.setSelectedRange(e)
            textView.scrollRangeToVisible(e)
            layoutAbschliessen()
        }
        return (n, ms(ContinuousClock.now - t0))
    }

    func tippen(runden: Int) async -> [Double] {
        var werte: [Double] = []
        for i in 0..<runden {
            let zeichen = String(UnicodeScalar(UInt8(97 + i % 26)))
            // Der Absatz wird danach im Hintergrund gefaerbt; das abwarten, damit
            // kein Anschlag die Arbeit des vorigen mitbezahlt.
            await faerbungAbwarten(frist: .seconds(2)) {
                let t0 = ContinuousClock.now
                textView.insertText(zeichen, replacementRange: textView.selectedRange())
                layoutAbschliessen()
                werte.append(ms(ContinuousClock.now - t0))
            }
        }
        return werte
    }

    /// Ganze Zeilen markieren, wie ein Zug mit der Maus ueber den linken Rand.
    func auswahlSetzen(von: Int, bis: Int) async {
        let a = offset(zeile: von, spalte: 1)
        let s = speicher.string as NSString
        let endeZeile = s.lineRange(for: NSRange(location: offset(zeile: bis, spalte: 1), length: 0))
        // Ohne den Zeilenumbruch am Ende: markiert ist der Text, nicht die Leerzeile darunter.
        let ende = s.substring(with: endeZeile).hasSuffix("\n") ? endeZeile.location + endeZeile.length - 1 : endeZeile.location + endeZeile.length
        textView.setSelectedRange(NSRange(location: a, length: max(0, ende - a)))
        layoutAbschliessen()
    }

    func auswahl() async -> (text: String, von: Int, bis: Int) {
        let r = textView.selectedRange()
        guard r.length > 0 else { return ("", 0, 0) }
        let s = speicher.string as NSString
        return (s.substring(with: r), zeileSpalte(offset: r.location).0, zeileSpalte(offset: r.location + r.length).0)
    }

    func kopieren(von: Int, bis: Int) async -> String {
        let a = offset(zeile: von, spalte: 1)
        let s = speicher.string as NSString
        let endeZeile = s.lineRange(for: NSRange(location: offset(zeile: bis, spalte: 1), length: 0))
        let r = NSRange(location: a, length: endeZeile.location + endeZeile.length - a)
        textView.setSelectedRange(r)
        textView.copy(nil)
        return textView.zwischenablage?.lesen() ?? ""
    }

    func schrift(groesse: Double) async -> Double {
        let t0 = ContinuousClock.now
        schriftPunkt = groesse
        hervorheber.schrift(schrift)
        textView.font = schrift
        // Jede Schrift im Text auf die neue Groesse, Schnitt und Farben bleiben.
        let ganz = NSRange(location: 0, length: speicher.length)
        var schriften: [NSFont: NSFont] = [:]
        speicher.beginEditing()
        speicher.enumerateAttribute(.font, in: ganz) { wert, bereich, _ in
            let f = (wert as? NSFont) ?? schrift
            let neu = schriften[f] ?? (NSFont(descriptor: f.fontDescriptor, size: groesse) ?? f)
            schriften[f] = neu
            speicher.addAttribute(.font, value: neu, range: bereich)
        }
        let t1 = ContinuousClock.now
        speicher.endEditing()
        let t2 = ContinuousClock.now
        layoutAbschliessen()
        schriftPhasen = [ms(t1 - t0), ms(t2 - t1), ms(ContinuousClock.now - t2)]
        return ms(ContinuousClock.now - t0)
    }

    /// Die Groesse der Schrift IM TEXT (Attribut an der Cursorstelle), nicht die der Ansicht.
    func schriftGroesse() async -> Double {
        let o = min(textView.selectedRange().location, max(0, speicher.length - 1))
        guard speicher.length > 0, let f = speicher.attribute(.font, at: o, effectiveRange: nil) as? NSFont else { return schriftPunkt }
        return Double(f.pointSize)
    }

    func erscheinung(dunkel: Bool) async -> String {
        await faerbungAbwarten(frist: .seconds(5)) { themaAnwenden(dunkel: dunkel) }
        return await hintergrund()
    }

    func hintergrund() async -> String {
        var hex = ""
        effectiveAppearance.performAsCurrentDrawingAppearance {
            hex = EditorFarben.hex(textView.backgroundColor)
        }
        return hex
    }

    func textLesen() async -> String { speicher.string }

    private func ms(_ d: Duration) -> Double {
        let c = d.components
        return Double(c.seconds) * 1000 + Double(c.attoseconds) / 1e15
    }
}

enum EditorFarben {
    static func hex(_ farbe: NSColor) -> String {
        guard let c = farbe.usingColorSpace(.sRGB) else { return "" }
        return String(format: "#%02x%02x%02x", Int(round(c.redComponent * 255)), Int(round(c.greenComponent * 255)), Int(round(c.blueComponent * 255)))
    }
}

// MARK: - Der Baustein und sein Fenster

/// Der Baustein fuer das Editor-Blatt (3.4): eine Ansicht, die eine Datei haelt
/// und ueber `baustein` bedient wird. Merkt Pfad und Sprache, meldet `auskunft()`
/// als `ui.editor` (pfad, zeilen, cursor, fassung, schrift, dunkel, hintergrund).
@MainActor
final class EditorAnsicht: NSView {
    let baustein: any EditorBaustein
    let zwischenablage: Zwischenablage
    private(set) var pfad = ""
    private(set) var sprache = ""
    private(set) var ladeFehler = ""
    private(set) var zuletzt: (lesbarMs: Double, gefaerbtMs: Double) = (0, 0)

    init(fassung: EditorFassung, optionen: Laufoptionen) {
        zwischenablage = Zwischenablage(kopflos: optionen.kopflos)
        switch fassung {
        case .text: baustein = TextKitEditor(zwischenablage: zwischenablage, kopflos: optionen.kopflos)
        }
        super.init(frame: .zero)
        let v = baustein.view
        v.translatesAutoresizingMaskIntoConstraints = false
        addSubview(v)
        NSLayoutConstraint.activate([
            v.leadingAnchor.constraint(equalTo: leadingAnchor), v.trailingAnchor.constraint(equalTo: trailingAnchor),
            v.topAnchor.constraint(equalTo: topAnchor), v.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }

    var fassung: EditorFassung { baustein.fassung }

    /// Datei lesen und zeigen; Sprache aus der Endung. Zeiten in ms.
    func oeffnen(pfad: String) async throws -> (lesbarMs: Double, gefaerbtMs: Double) {
        let text = try String(contentsOfFile: pfad, encoding: .utf8)
        guard await baustein.bereit(frist: .seconds(20)) else {
            ladeFehler = "Editor nicht bereit"
            throw NSError(domain: "Werkbank", code: 10, userInfo: [NSLocalizedDescriptionKey: ladeFehler])
        }
        self.pfad = pfad
        sprache = EditorSprache.fuer(pfad: pfad)
        zuletzt = await baustein.oeffnen(text: text, sprache: sprache)
        return zuletzt
    }

    /// EINEN SCHON GELESENEN TEXT ZEIGEN (Auftrag 3.4). Das Editor-Blatt liest
    /// die Datei ueber den Kern (`awb:editor-read-file`, Ausschlussliste und
    /// Pfadsperre gelten dort) und legt den Text hier hinein; `oeffnen(pfad:)`
    /// daneben bleibt der Weg des Steuerkanals aus 3.3, der von der Platte liest.
    @discardableResult
    func zeigen(text: String, pfad: String) async -> (lesbarMs: Double, gefaerbtMs: Double) {
        self.pfad = pfad
        ladeFehler = ""
        sprache = EditorSprache.fuer(pfad: pfad)
        zuletzt = await baustein.oeffnen(text: text, sprache: sprache)
        return zuletzt
    }

    func auskunft() async -> [String: Any] {
        let c = await baustein.cursor()
        return [
            "gebaut": true,
            "fassung": baustein.fassung.rawValue,
            "pfad": pfad,
            "sprache": sprache,
            "zeilen": await baustein.zeilen(),
            "cursor": ["zeile": c.zeile, "spalte": c.spalte],
            "schrift": await baustein.schriftGroesse(),
            "hintergrund": await baustein.hintergrund(),
            "dunkel": effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua,
            "textkit": (baustein as? TextKitEditor)?.textView.textLayoutManager != nil ? 2 : 1,
            "oeffnenMs": ["lesbar": zuletzt.lesbarMs, "gefaerbt": zuletzt.gefaerbtMs],
            "faerbung": (baustein as? TextKitEditor)?.letzteFaerbung ?? "",
            "fehler": ladeFehler,
        ]
    }
}

/// Das Fenster des Steuerkanals fuer den Baustein: gebaut, nie gezeigt --
/// bis 3.4 den Baustein ins Hauptfenster legt. 900x600 wie das Sitzungsfenster.
@MainActor
final class EditorFenster {
    let fenster: NSWindow
    let ansicht: EditorAnsicht

    init(fassung: EditorFassung, optionen: Laufoptionen) {
        ansicht = EditorAnsicht(fassung: fassung, optionen: optionen)
        fenster = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable],
                           backing: .buffered, defer: false)
        fenster.title = "Editor"
        fenster.isReleasedWhenClosed = false
        fenster.contentView = ansicht
        fenster.layoutIfNeeded()
        ansicht.layoutSubtreeIfNeeded()
    }

    /// Ein Belegbild wie bei den Einstellungen: der Rahmen in eine Bitmap. Der
    /// NSTextView zeichnet auch ausserhalb des Bildschirms (gemessen 06.09.).
    func schuss(pfad: String) async throws -> (breite: Int, hoehe: Int) {
        guard let rahmen = fenster.contentView?.superview else { throw NSError(domain: "Werkbank", code: 1, userInfo: [NSLocalizedDescriptionKey: "kein Fensterrahmen"]) }
        fenster.layoutIfNeeded()
        rahmen.layoutSubtreeIfNeeded()
        guard let rep = rahmen.bitmapImageRepForCachingDisplay(in: rahmen.bounds) else {
            throw NSError(domain: "Werkbank", code: 2, userInfo: [NSLocalizedDescriptionKey: "keine Bitmap"])
        }
        if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = ctx
            fenster.effectiveAppearance.performAsCurrentDrawingAppearance {
                fenster.backgroundColor.setFill()
                NSRect(x: 0, y: 0, width: rep.pixelsWide, height: rep.pixelsHigh).fill()
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        rahmen.cacheDisplay(in: rahmen.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "Werkbank", code: 3, userInfo: [NSLocalizedDescriptionKey: "kein PNG"])
        }
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: pfad).deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: URL(fileURLWithPath: pfad))
        return (rep.pixelsWide, rep.pixelsHigh)
    }
}

// MARK: - Die Messung

/// Der Speicherbedarf des eigenen Prozesses (phys_footprint, wie Activity Monitor „Speicher“), MB.
func eigenerSpeicherMB() -> Double {
    var info = task_vm_info_data_t()
    var zaehler = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(zaehler)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &zaehler) }
    }
    guard kr == KERN_SUCCESS else { return -1 }
    return Double(info.phys_footprint) / 1_048_576
}

enum EditorMessung {
    /// Der ganze Messlauf einer Fassung an einer Datei: oeffnen, Cursor, tippen,
    /// suchen, kopieren, Schrift, Erscheinung, Speicher. Ergebnis als Woerterbuch
    /// fuer `awbmac-ctl editor-messung`.
    @MainActor
    static func laufen(_ e: EditorFenster, pfad: String, runden: Int, suchwort: String) async -> [String: Any] {
        var r: [String: Any] = ["fassung": e.ansicht.fassung.rawValue, "pfad": pfad, "runden": runden]
        let speicherVorher = eigenerSpeicherMB()
        let t0 = ContinuousClock.now
        let bereit = await e.ansicht.baustein.bereit(frist: .seconds(20))
        r["bereitMs"] = ms(ContinuousClock.now - t0)
        r["bereit"] = bereit
        guard bereit else { r["fehler"] = "nicht bereit"; return r }
        do {
            let z = try await e.ansicht.oeffnen(pfad: pfad)
            r["oeffnen"] = ["lesbarMs": z.lesbarMs, "gefaerbtMs": z.gefaerbtMs, "zeilen": await e.ansicht.baustein.zeilen()]
        } catch {
            r["fehler"] = error.localizedDescription
            return r
        }
        let b = e.ansicht.baustein
        await b.cursorSetzen(zeile: 4321, spalte: 7)
        let c = await b.cursor()
        r["cursor"] = ["gesetzt": [4321, 7], "gelesen": [c.zeile, c.spalte], "stimmt": c.zeile == 4321 && c.spalte == 7]
        // Tippen in der Mitte der Datei, wo Layout und Faerbung wirklich arbeiten.
        await b.cursorSetzen(zeile: 2500, spalte: 1)
        let werte = await b.tippen(runden: runden)
        let sortiert = werte.sorted()
        r["tippen"] = ["werteMs": werte,
                       "medianMs": sortiert.isEmpty ? -1 : sortiert[sortiert.count / 2],
                       "p95Ms": sortiert.isEmpty ? -1 : sortiert[min(sortiert.count - 1, Int(Double(sortiert.count) * 0.95))],
                       "maxMs": sortiert.last ?? -1]
        let s = await b.suchen(suchwort)
        r["suche"] = ["wort": suchwort, "treffer": s.treffer, "ms": s.ms]
        let kopie = await b.kopieren(von: 10, bis: 12)
        r["kopieren"] = ["zeilen": [10, 12], "zeichen": kopie.count, "zeilenImText": kopie.split(separator: "\n", omittingEmptySubsequences: false).count - 1]
        let alt = await b.schriftGroesse()
        let gross = await b.schrift(groesse: alt * 2)
        let grossGelesen = await b.schriftGroesse()
        let zurueck = await b.schrift(groesse: alt)
        r["schrift"] = ["vorher": alt, "doppeltMs": gross, "doppeltGelesen": grossGelesen, "zurueckMs": zurueck,
                        "phasenMs": (b as? TextKitEditor)?.schriftPhasen ?? []]
        // Das Erscheinungsbild am Fenster umstellen, wie `erscheinung` es an der App
        // tut; der Baustein folgt (viewDidChangeEffectiveAppearance bzw. Thema).
        let vorherA = e.fenster.appearance
        e.fenster.appearance = NSAppearance(named: .aqua)
        let hell = await b.erscheinung(dunkel: false)
        e.fenster.appearance = NSAppearance(named: .darkAqua)
        let dunkel = await b.erscheinung(dunkel: true)
        e.fenster.appearance = vorherA
        _ = await b.erscheinung(dunkel: e.fenster.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
        r["erscheinung"] = ["hell": hell, "dunkel": dunkel, "unterschieden": hell != dunkel]
        r["speicherMB"] = ["vorher": speicherVorher, "nachher": eigenerSpeicherMB(), "pid": Int(getpid())]
        return r
    }

    private static func ms(_ d: Duration) -> Double {
        let c = d.components
        return Double(c.seconds) * 1000 + Double(c.attoseconds) / 1e15
    }
}
