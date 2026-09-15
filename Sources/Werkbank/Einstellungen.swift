// Das Einstellungsfenster (Auftrag 2.6, ⌘,): ein eigenes Fenster in der Form
// der Systemeinstellungen -- links die Seitenleiste mit sieben Seiten und
// SF-Symbolen, rechts ein `Form` mit Gruppen aus Systemsteuerelementen
// (Schalter, Stepper, Aufklappmenues, Segmentleisten), unten die Fusszeile
// mit dem Wortlaut des letzten Schreibvorgangs. Inhalt und Kennungen kommen
// aus EinstellungenSeiten.swift, die Daten vom Kern (`awb:ein-daten`,
// `awb:ein-daten-neu`), die Texte ebenso (`awb:ein-texte`).
//
// DIE AUFLAGE AUS DIESEM HAUS, wie in der Electron-Fassung
// (einstellungsfenster.ts): das Fenster geht auf, weil ein MENSCH geklickt
// hat -- Zahnrad, Fuss, ⌘, --, nie weil ein Test oder ein Agent es anfordert.
// `bauen()` baut und liest ohne zu zeigen (der Weg des Steuerkanals),
// `zeigen()` ist der einzige Weg auf den Bildschirm und kopflos wirkungslos.
//
// NSSplitViewController statt NavigationSplitView, aus demselben Grund wie im
// Hauptfenster (mac/PLAN.md): in einem nie gezeigten Fenster baut SwiftUI die
// Seitenleisten-Spalte nicht auf, und jede Pruefung laeuft kopflos.
//
// Textstile, Systemfarben, Systemakzent, Systemmaterial der Seitenleiste;
// keine festen Punktgroessen fuer Text, keine fest verdrahteten Farben.
import AppKit
import SwiftUI
import WerkbankProtokoll

@MainActor
final class EinstellungenFenster: NSObject, NSWindowDelegate {
    let zustand: EinstellungenZustand
    let fenster: NSWindow
    private let split = NSSplitViewController()
    private let oberflaeche: Oberflaeche
    private let optionen: Laufoptionen
    private let kopflos: Bool
    private var geladen = false
    /// Der gemerkte Rahmen dieses Fensters. Im Betrieb macht das
    /// `setFrameAutosaveName`; in einer Pruefung nicht, denn AppKit schreibt
    /// dabei in die Ablage des MENSCHEN (Merker.swift).
    private static let rahmenSchluessel = "NSWindow Frame Einstellungen"
    /// Der Einzug, den AppKit jeder Bildlaufflaeche von sich aus gibt -- siehe
    /// `rahmenAuskunft()`. Bis hierher ist ein Ueberstand keiner.
    private static let scrollEinzug: CGFloat = 30

    init(kern: KernVerbindung, optionen: Laufoptionen, oberflaeche: Oberflaeche) {
        self.optionen = optionen
        self.kopflos = optionen.kopflos
        self.oberflaeche = oberflaeche
        zustand = EinstellungenZustand(kern: kern, kopflos: optionen.kopflos)
        // 1120 x 760 mit Mindestmass 820 x 560: die Masse der Electron-Fassung
        // (einstellungsfenster.ts, am Bild gemessen 03.09.: die Deckel-Tabelle
        // braucht die Breite neben der Seitenliste). Apple nennt fuer Fenster
        // keine Zahl; ein Fenster ist frei veraenderbar ohne Hoechstmass.
        fenster = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 760),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                           backing: .buffered, defer: false)
        super.init()
        fenster.title = "Einstellungen"
        fenster.minSize = NSSize(width: 820, height: 560)
        fenster.isReleasedWhenClosed = false
        fenster.toolbarStyle = .unified
        fenster.titlebarSeparatorStyle = .automatic
        if optionen.pruefmodus {
            // Von Hand ueber `Merker`: `setFrameAutosaveName` schreibt immer in
            // die Ablage des Menschen, auch mit Wegwerf-HOME (Merker.swift).
            if let t = Merker.text(datei: Merker.einstellungslage, schluessel: Self.rahmenSchluessel, optionen) {
                fenster.setFrame(from: t)
            }
        } else {
            fenster.setFrameAutosaveName("Einstellungen")
        }
        fenster.delegate = self
        fenster.identifier = NSUserInterfaceItemIdentifier("einstellungen")
        let leiste = NSHostingController(rootView: SeitenListe(zustand: zustand))
        leiste.sizingOptions = []
        let leisteItem = NSSplitViewItem(sidebarWithViewController: leiste)
        leisteItem.minimumThickness = 200
        leisteItem.maximumThickness = 280
        leisteItem.canCollapse = false
        split.addSplitViewItem(leisteItem)
        let inhalt = NSHostingController(rootView: SeiteAnsicht(zustand: zustand))
        inhalt.sizingOptions = []
        let inhaltItem = NSSplitViewItem(viewController: inhalt)
        inhaltItem.minimumThickness = 560
        split.addSplitViewItem(inhaltItem)
        fenster.contentViewController = split
        // `contentViewController` zieht das Fenster auf die Groesse der Controller-Views (gemessen: 820x580);
        // die Groesse steht danach noch einmal.
        fenster.setContentSize(NSSize(width: 1120, height: 760))
        // Die Symbolleiste traegt nur den Umschalter der Seitenleiste; sie gibt dem Titel die Hoehe der Systemeinstellungen.
        let toolbar = NSToolbar(identifier: "einstellungen")
        toolbar.displayMode = .iconOnly
        toolbar.delegate = self
        fenster.toolbar = toolbar
        zustand.aufRueckfrage = { [weak self] r in self?.rueckfrageZeigen(r) }
        zustand.aufSeitenNeu = { [weak self] in self?.leisteAnpassen() }
        kern.aufEinstellungenNeu = { [weak self] zeile in self?.zustand.datenAngekommen(zeile) }
    }

    /// Bauen und laden, OHNE zu zeigen -- der Weg des Steuerkanals. Mehrfach aufrufbar.
    func bauen() async {
        oberflaeche.einstellungenOffen = true
        fenster.layoutIfNeeded()
        if !geladen {
            geladen = true
            await zustand.laden()
        }
    }

    /// DER EINZIGE WEG AUF DEN BILDSCHIRM: nach einem Klick des Menschen. Kopflos ohne Wirkung.
    func zeigen() {
        Task { @MainActor in
            await bauen()
            guard !kopflos else { return }
            fenster.vorZeigen(ohneFokus: optionen.ohneFokus)
        }
    }

    var sichtbar: Bool { fenster.isVisible }

    /// In einer Pruefung merkt sich das Fenster seinen Rahmen selbst; im
    /// Betrieb tut das `setFrameAutosaveName`.
    private func rahmenMerken() {
        guard optionen.pruefmodus else { return }
        Merker.setzen(fenster.frameDescriptor, datei: Merker.einstellungslage,
                      schluessel: Self.rahmenSchluessel, optionen)
    }

    func windowDidResize(_ notification: Notification) { rahmenMerken() }
    func windowDidMove(_ notification: Notification) { rahmenMerken() }

    func windowWillClose(_ notification: Notification) {
        rahmenMerken()
        oberflaeche.einstellungenOffen = false
        zustand.rueckfrage = nil
        zustand.offenesInfo = ""
    }

    /// Die Rueckfrage der dritten Klasse als Sheet: der Satz nennt die Folge,
    /// der Knopf das Tun, Abbrechen ist die Vorgabe (Return loest nichts aus).
    /// Mit Grund: ein Textfeld, und leer heisst nicht tun -- das Sheet kommt
    /// dann mit dem Hinweis noch einmal.
    private func rueckfrageZeigen(_ r: Rueckfrage) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = r.text
        alert.informativeText = r.hinweis
        alert.addButton(withTitle: "Abbrechen")
        let tun = alert.addButton(withTitle: r.tun)
        tun.keyEquivalent = ""
        var feld: NSTextField?
        if r.mitGrund {
            let f = NSTextField(string: r.grund)
            f.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
            f.placeholderString = zustand.texte.t("platzhalter.musterGrund")
            f.setAccessibilityLabel("Grund")
            alert.accessoryView = f
            alert.window.initialFirstResponder = f
            feld = f
        }
        Task { @MainActor in
            let antwort = await alert.beginSheetModal(for: fenster)
            let ja = antwort == .alertSecondButtonReturn
            zustand.rueckfrageBeantworten(ja: ja, grund: feld?.stringValue, echt: true)
            if let wieder = zustand.rueckfrage, ja { rueckfrageZeigen(wieder) }
        }
    }

    /// Ein Belegbild des Fensters, auch kopflos -- derselbe Weg wie
    /// `Fenster.schuss`: der Rahmen in eine Bitmap, darueber die Seitenleiste
    /// und die Seite aus denselben SwiftUI-Views ueber `ImageRenderer`, weil
    /// Listenzeilen, Materialien und AppKit-Steuerelemente ausserhalb des
    /// Bildschirms nichts zeichnen (gemessen 06.09., mac/PLAN.md).
    func schuss(pfad: String) throws -> (breite: Int, hoehe: Int) {
        guard let rahmen = fenster.contentView?.superview else { throw NSError(domain: "Werkbank", code: 1, userInfo: [NSLocalizedDescriptionKey: "kein Fensterrahmen"]) }
        fenster.layoutIfNeeded()
        rahmen.layoutSubtreeIfNeeded()
        guard let rep = rahmen.bitmapImageRepForCachingDisplay(in: rahmen.bounds) else {
            throw NSError(domain: "Werkbank", code: 2, userInfo: [NSLocalizedDescriptionKey: "keine Bitmap"])
        }
        let dunkel = fenster.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
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
        func legen<V: View>(_ view: V, in ziel: NSRect, grund: NSColor) {
            guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return }
            let renderer = ImageRenderer(content: view.frame(width: ziel.width, height: ziel.height, alignment: .topLeading).environment(\.colorScheme, dunkel ? .dark : .light))
            renderer.scale = fenster.backingScaleFactor
            renderer.proposedSize = ProposedViewSize(width: ziel.width, height: ziel.height)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = ctx
            // Die dynamische Fenstergrundfarbe loest sich ausserhalb eines Zeichenzyklus nach
            // `NSAppearance.current` auf -- gemessen 06.09.: im hellen Bild blieb die Seitenleiste
            // dunkel. Also im Erscheinungsbild des Fensters fuellen.
            fenster.effectiveAppearance.performAsCurrentDrawingAppearance {
                grund.setFill()
                ziel.fill()
            }
            renderer.nsImage?.draw(in: ziel, from: .zero, operation: .sourceOver, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
        }
        if let leiste = split.splitViewItems.first?.viewController.view {
            legen(SeitenListeBeleg(zustand: zustand), in: leiste.convert(leiste.bounds, to: nil), grund: fenster.backgroundColor)
        }
        if split.splitViewItems.count > 1 {
            let inhalt = split.splitViewItems[1].viewController.view
            legen(SeiteAnsicht(zustand: zustand, beleg: true), in: inhalt.convert(inhalt.bounds, to: nil), grund: fenster.backgroundColor)
        }
        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "Werkbank", code: 3, userInfo: [NSLocalizedDescriptionKey: "kein PNG"])
        }
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: pfad).deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: URL(fileURLWithPath: pfad))
        return (rep.pixelsWide, rep.pixelsHigh)
    }

    /// WIE BREIT DIE SEITENLEISTE SEIN MUSS, DAMIT KEIN NAME ABGESCHNITTEN
    /// WIRD (08.09.2026). Sie stand fest auf 200 Punkten, und die zwei laengsten
    /// der sieben Seiten passten nicht hinein: im Fenster stand „Programme und
    /// Mod…" und „Aufsicht und Meldun…", in jeder Groesse, hell wie dunkel.
    ///
    /// Die noetige Breite ist keine Zahl im Code, sondern gemessen: der
    /// laengste Seitenname in der Schrift, die die Liste wirklich benutzt, plus
    /// das Beiwerk der Zeile. Das muss so sein, weil beides sich aendern kann,
    /// ohne dass jemand hier vorbeikommt -- die Namen mit der Sprache (englisch
    /// heisst die laengste Seite „Watch and notifications"), die Schrift mit der
    /// Textgroesse des Systems.
    ///
    /// Die 62 Punkte Beiwerk sind ebenfalls gemessen (08.09.2026): bei 200
    /// Punkten Leiste blieben 138 Punkte fuer den Text -- Symbol, sein Abstand
    /// zum Text und die Einzuege der Zeile machen zusammen 62. Vier Punkte Luft
    /// obendrauf, damit ein Rundungsschritt nicht wieder Punkte abschneidet.
    private static let leisteBeiwerk: CGFloat = 66
    /// Was der Inhalt mindestens braucht -- dieselbe Zahl wie beim Aufbau des
    /// Split-Views, hier als Summand der Fenster-Mindestbreite.
    private static let inhaltMindestbreite: CGFloat = 560

    /// Die noetige Breite, gemessen an den Namen, die WIRKLICH in der Liste
    /// stehen. Steht auch in der Auskunft (`rahmen.noetig`), damit eine Suite
    /// „breit genug" pruefen kann, ohne eine Zahl zu kennen -- die Namen
    /// wechseln mit der Sprache.
    var leisteNoetig: CGFloat {
        guard !zustand.seiten.isEmpty else { return 200 }
        let schrift = NSFont.preferredFont(forTextStyle: .body)
        let breiteste = zustand.seiten.reduce(CGFloat(0)) {
            max($0, ceil(NSAttributedString(string: $1.titel, attributes: [.font: schrift]).size().width))
        }
        return min(max(ceil(breiteste) + Self.leisteBeiwerk, 200), 340)
    }

    private func leisteAnpassen() {
        guard let item = split.splitViewItems.first, !zustand.seiten.isEmpty else { return }
        let noetig = leisteNoetig
        guard abs(item.minimumThickness - noetig) > 0.5 else { return }
        item.minimumThickness = noetig
        item.maximumThickness = max(noetig + 60, 280)
        // Die Mindestbreite des Fensters waechst mit: unter Leiste plus Inhalt
        // ueberlagert sich zwangslaeufig etwas.
        fenster.minSize = NSSize(width: max(820, noetig + Self.inhaltMindestbreite), height: fenster.minSize.height)
        if fenster.frame.width < fenster.minSize.width {
            groesseSetzen(breite: Int(fenster.minSize.width), hoehe: Int(fenster.frame.height))
        }
        // Der Teiler bleibt sonst stehen, wo er stand -- das Mindestmass allein
        // zieht ihn nicht nach (gemessen 08.09.2026).
        if split.splitView.subviews.count > 1, split.splitView.subviews[0].frame.width < noetig {
            split.splitView.setPosition(noetig, ofDividerAt: 0)
        }
        split.view.layoutSubtreeIfNeeded()
    }

    /// Die Groesse des Fensters setzen -- der Weg, auf dem eine Pruefung das
    /// KLEINSTE erlaubte Mass ansieht, ohne dass ein Mensch am Rand zieht.
    /// `NSWindow` haelt sich dabei von selbst an `minSize`; die Antwort nennt
    /// deshalb, was wirklich herausgekommen ist, nicht was gewuenscht war.
    @discardableResult
    func groesseSetzen(breite: Int, hoehe: Int) -> (breite: Int, hoehe: Int) {
        // Die gemessenen Spaltenbreiten gehoeren zur alten Fensterbreite.
        zustand.tabellenmass = [:]
        var f = fenster.frame
        f.size = NSSize(width: CGFloat(breite), height: CGFloat(hoehe))
        fenster.setFrame(f, display: true)
        fenster.layoutIfNeeded()
        split.view.layoutSubtreeIfNeeded()
        return (Int(fenster.frame.width), Int(fenster.frame.height))
    }

    /// WO SEITENLEISTE UND INHALT WIRKLICH LIEGEN (08.09.2026, des Nutzers
    /// Befund: „In den Einstellungen sieht man manches nicht, weil sich Dinge
    /// ueberlagern, vor allem mit der linken Seitenleiste").
    ///
    /// Gemessen wird an den Rahmen, die AppKit vergibt, nicht am Bild. Der
    /// `NSSplitView` teilt das Fenster in zwei Haelften; jede Ansicht darin
    /// gehoert in ihre Haelfte. Zwei Zahlen entscheiden:
    ///   `ueberschneidung` -- wie viele Punkte breit sich die beiden Haelften
    ///                        selbst ueberlappen (0, solange der Teiler sitzt).
    ///   `ueberstand`      -- jede Ansicht, die aus ihrer Haelfte herausragt,
    ///                        mit Klasse und Mass. Gemeldet wird nur die
    ///                        AEUSSERSTE: ihre Kinder ragen zwangslaeufig mit
    ///                        heraus und sagen nichts Neues.
    ///
    /// DIE 28 PUNKTE TOLERANZ SIND GEMESSEN, NICHT GERATEN. AppKit gibt jeder
    /// Bildlaufflaeche links und rechts einen Einzug fuer den elastischen
    /// Ueberzug; ihre Traegeransicht steht deshalb IMMER 28 Punkte weiter
    /// aussen als die Haelfte, in der sie sitzt, und der verborgene
    /// `NSScroller` 17. Gemessen am 08.09.2026 auf allen sieben Seiten in
    /// beiden Groessen: 28 und 17, ausnahmslos; bei ungerader Inhaltsbreite
    /// rundet AppKit auf 29. Gezeichnet wird darin nichts. Die Toleranz steht
    /// deshalb bei 30. Die echten Befunde desselben Laufs lagen bei 37, 66 und
    /// 160 Punkten -- alle weit darueber.
    ///
    /// WARUM NICHT UEBER DEN BARRIEREFREIHEITSBAUM (gemessen 08.09.2026): den
    /// baut AppKit erst auf, wenn ein Hilfsprogramm zusieht. Ohne VoiceOver
    /// oder Accessibility Inspector reicht `accessibilityChildren()` unterhalb
    /// des `NSHostingView` nichts heraus -- der Baum hatte neun Knoten, und der
    /// Ueberstand von 66 Punkten stand in keinem davon. Die Ansichtshierarchie
    /// steht immer.
    func rahmenAuskunft() -> [String: Any] {
        func inFenster(_ v: NSView) -> NSRect { v.convert(v.bounds, to: nil) }
        let leisteView = split.splitViewItems.first?.viewController.view
        let inhaltView = split.splitViewItems.count > 1 ? split.splitViewItems[1].viewController.view : nil
        let leiste = leisteView.map(inFenster) ?? .zero
        let inhalt = inhaltView.map(inFenster) ?? .zero
        var ueberstand: [[String: Any]] = []
        func suchen(_ v: NSView, _ heimat: NSRect, _ haelfte: String, _ tiefe: Int) {
            let r = inFenster(v)
            guard r.width > 0 else { return }
            let raus = max(heimat.minX - r.minX, r.maxX - heimat.maxX)
            if raus > Self.scrollEinzug {
                ueberstand.append(["haelfte": haelfte, "art": String(describing: type(of: v)),
                                   "punkte": Int(raus.rounded()), "x": Int(r.minX), "breite": Int(r.width)])
                return
            }
            guard tiefe > 0 else { return }
            for k in v.subviews { suchen(k, heimat, haelfte, tiefe - 1) }
        }
        if let v = leisteView { for k in v.subviews { suchen(k, leiste, "leiste", 20) } }
        if let v = inhaltView { for k in v.subviews { suchen(k, inhalt, "inhalt", 20) } }
        return [
            "leiste": [Int(leiste.minX), Int(leiste.width)],
            "inhalt": [Int(inhalt.minX), Int(inhalt.width)],
            "ueberschneidung": Int(max(0, leiste.maxX - inhalt.minX).rounded()),
            "ueberstand": ueberstand,
            "einzug": Int(Self.scrollEinzug),
            "noetig": Int(leisteNoetig),
            "mindestbreite": Int(fenster.minSize.width),
            "mindesthoehe": Int(fenster.minSize.height),
        ]
    }

    /// Die Auskunft fuer `awbmac-ctl` (`ui.einstellungen` und `einstellungen <seite>`),
    /// mit den Feldnamen von `awb-ctl einstellungen`.
    func auskunft() -> [String: Any] {
        var r: [String: Any] = [
            "offen": zustand.seite,
            "gebaut": oberflaeche.einstellungenOffen,
            "sichtbar": fenster.isVisible,
            "bereit": zustand.daten != nil && !zustand.texte.leer,
            "groesse": [Int(fenster.contentView?.frame.width ?? 0), Int(fenster.contentView?.frame.height ?? 0)],
            "seiten": zustand.seitenNamen,
            "sprache": zustand.texte.sprache,
            "status": zustand.status,
            "statusArt": zustand.statusArt,
            "zeichnungen": zustand.zeichnungen,
            "info": zustand.infoAuskunft(),
            "felder": zustand.felderAuskunft(),
            "text": zustand.seitenText(),
            "rahmen": rahmenAuskunft(),
            "tabellen": zustand.tabellenAuskunft(),
            "texte": zustand.textAuskunft(),
        ]
        if let f = zustand.rueckfrage {
            r["rueckfrage"] = ["offen": true, "text": f.text, "tun": f.tun, "mitGrund": f.mitGrund, "grund": f.grund, "hinweis": f.hinweis]
        } else {
            r["rueckfrage"] = ["offen": false]
        }
        return r
    }
}

extension EinstellungenFenster: NSToolbarDelegate {
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.toggleSidebar, .sidebarTrackingSeparator] }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.toggleSidebar, .sidebarTrackingSeparator] }
}

// MARK: Die Seitenleiste

struct SeitenListe: View {
    let zustand: EinstellungenZustand

    var body: some View {
        List(zustand.seiten, selection: Binding(get: { zustand.seite }, set: { if let s = $0 { zustand.seiteWaehlen(s) } })) { s in
            Label(s.titel, systemImage: s.symbol)
                .help(s.wofuer)
                .tag(s.id)
        }
        .listStyle(.sidebar)
        .accessibilityIdentifier("einstellungen-seiten")
    }
}

/// Dieselben Zeilen fuer das kopflose Bild: die Liste selbst zeichnet ausserhalb des Bildschirms nichts.
struct SeitenListeBeleg: View {
    let zustand: EinstellungenZustand

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(zustand.seiten) { s in
                Label(s.titel, systemImage: s.symbol)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(s.id == zustand.seite ? AnyShapeStyle(.selection) : AnyShapeStyle(.clear)))
                    .foregroundStyle(s.id == zustand.seite ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 52)
    }
}

// MARK: Die Seite

struct SeiteAnsicht: View {
    let zustand: EinstellungenZustand
    var beleg = false

    var body: some View {
        VStack(spacing: 0) {
            if let s = zustand.aktuelleSeite {
                if beleg {
                    VStack(alignment: .leading, spacing: 14) { inhalt(s) }
                        .padding(20)
                        .padding(.top, 40)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                } else {
                    Form { inhalt(s) }
                        .formStyle(.grouped)
                        .accessibilityIdentifier("einstellungen-seite")
                }
            } else {
                // Der Ladezustand: die Form der kommenden Seite, kein Raedchen ueber allem (abnahme.md, Merkmal 12).
                VStack(alignment: .leading, spacing: 10) {
                    Text("Einstellungen").font(.title2.weight(.semibold))
                    Text(zustand.kern.verbunden ? "Die Einstellungen werden vom Kern gelesen …" : "Kein Kern verbunden – die Einstellungen kommen, sobald er da ist.")
                        .foregroundStyle(.secondary)
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            Statuszeile(zustand: zustand)
        }
        .background(.background)
    }

    @ViewBuilder
    private func inhalt(_ s: Seite) -> some View {
        if beleg {
            Text(s.titel).font(.title2.weight(.semibold))
            MessText(id: "unterzeile:\(s.id)", text: s.unterzeile, zustand: zustand, beleg: true, schrift: .body, stil: .body)
            ForEach(s.gruppen) { g in
                VStack(alignment: .leading, spacing: 10) {
                    gruppenTitel(g)
                    ForEach(g.felder) { f in FeldAnsicht(feld: f, zustand: zustand, beleg: true) }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary.opacity(0.5)))
            }
        } else {
            Section {
                MessText(id: "unterzeile:\(s.id)", text: s.unterzeile, zustand: zustand, beleg: false, schrift: .body, stil: .body)
            } header: {
                Text(s.titel).font(.title2.weight(.semibold)).padding(.bottom, 4)
            }
            ForEach(s.gruppen) { g in
                Section {
                    ForEach(g.felder) { f in FeldAnsicht(feld: f, zustand: zustand, beleg: false) }
                } header: {
                    gruppenTitel(g)
                }
            }
        }
    }

    @ViewBuilder
    private func gruppenTitel(_ g: Gruppe) -> some View {
        if g.vorsicht {
            Label(g.titel, systemImage: "exclamationmark.triangle").font(.headline)
        } else {
            Text(g.titel).font(.headline)
        }
    }
}

/// Die Fusszeile: was zuletzt geschrieben wurde, wortwoertlich. Das Zeichen
/// davor traegt die Bedeutung, nicht nur die Farbe (abnahme.md, Merkmal 5).
private struct Statuszeile: View {
    let zustand: EinstellungenZustand

    var body: some View {
        HStack(spacing: 6) {
            if zustand.statusArt == "fehler" {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            } else if zustand.statusArt == "gut" {
                Image(systemName: "checkmark.circle").foregroundStyle(.secondary)
            }
            Text(zustand.status.isEmpty ? " " : zustand.status)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .accessibilityIdentifier("einstellungen-status")
    }
}

/// EIN FLIESSTEXT, DER UMBRICHT STATT ZU KUERZEN (08.09.2026) -- und der sagt,
/// was er dabei bekommen hat.
///
/// Ein `Text` in SwiftUI kuerzt, sobald die vorgeschlagene Breite unter seiner
/// einzeiligen liegt; umbrechen tut er erst mit
/// `fixedSize(horizontal: false, vertical: true)`. Ohne das stand auf der Seite
/// „Programme und Modelle" im Fenster „… welche Denkstufen e…", „… statt des
/// Terminalbil…" und „An tmux wie bisher, oder an einem Pseudo-T…" -- drei
/// abgeschnittene Saetze, deren Text im Modell vollstaendig steht.
///
/// GEMESSEN WIRD MIT, weil im Text nicht steht, ob er gekuerzt ist: die
/// Ansicht meldet ihre wirkliche Groesse an den Zustand (`textmass`), und
/// `textAuskunft()` rechnet nach -- braucht der Satz mehr Breite, als er hat,
/// und steht er trotzdem in einer Zeile, ist er abgeschnitten. Dasselbe
/// Verfahren wie bei den Spaltenueberschriften der Tabellen. Das Belegbild
/// misst nicht mit: es zeichnet dieselben Seiten ein zweites Mal und wuerde den
/// Stand des Fensters mit seiner eigenen Breite ueberschreiben.
struct MessText: View {
    let id: String
    let text: String
    let zustand: EinstellungenZustand
    let beleg: Bool
    var schrift: Font = .callout
    var stil: NSFont.TextStyle = .callout

    var body: some View {
        Text(text)
            .font(schrift)
            .foregroundStyle(.secondary)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { g in
                guard !beleg, !text.isEmpty, g.width > 0 else { return }
                zustand.textmass[id] = (text: text, stil: stil, breite: g.width, hoehe: g.height)
            }
    }
}

// MARK: Ein Einstellungsfeld

struct FeldAnsicht: View {
    let feld: Einstellungsfeld
    let zustand: EinstellungenZustand
    let beleg: Bool

    var body: some View {
        if feld.name.isEmpty {
            SteuerAnsicht(feld: feld, zustand: zustand, beleg: beleg)
        } else if feld.breit || breitVonSelbst {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(feld.name).fontWeight(.medium)
                    InfoKnopf(feld: feld, zustand: zustand, beleg: beleg)
                    Spacer()
                    Etikett(feld: feld)
                    ZurueckKnopf(feld: feld, zustand: zustand, beleg: beleg)
                }
                SteuerAnsicht(feld: feld, zustand: zustand, beleg: beleg)
                MessText(id: "wirkung:\(feld.id)", text: feld.wirkung, zustand: zustand, beleg: beleg)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("feld-\(feld.id)")
        } else {
            LabeledContent {
                HStack(spacing: 8) {
                    Etikett(feld: feld)
                    SteuerAnsicht(feld: feld, zustand: zustand, beleg: beleg)
                    ZurueckKnopf(feld: feld, zustand: zustand, beleg: beleg)
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(feld.name)
                    InfoKnopf(feld: feld, zustand: zustand, beleg: beleg)
                }
                MessText(id: "wirkung:\(feld.id)", text: feld.wirkung, zustand: zustand, beleg: beleg)
            }
            .accessibilityIdentifier("feld-\(feld.id)")
        }
    }

    /// Alles, was keine Zeile ist, steht ueber die ganze Breite.
    private var breitVonSelbst: Bool {
        switch feld.art {
        case .schalter, .zahl, .text, .wahl, .knopf: return false
        default: return true
        }
    }
}

/// Das Etikett „sofort" / „gilt fuer die naechste Sitzung" -- ruhig, in der Zweitfarbe.
private struct Etikett: View {
    let feld: Einstellungsfeld
    var body: some View {
        if !feld.etikett.isEmpty {
            // Eine Zeile, ganz oder gar nicht (08.09.2026): „gilt fuer die
            // naechste Sitzung" brach in der Zeile „Programm im Hauptfenster"
            // auf zwei Zeilen um und schob den Umschalter daneben zusammen.
            Text(feld.etikett)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(.quaternary.opacity(0.6)))
        }
    }
}

/// Das Infozeichen mit dem genauen Text: Hilfetext beim Zeigen, Popover beim Klick.
private struct InfoKnopf: View {
    let feld: Einstellungsfeld
    let zustand: EinstellungenZustand
    let beleg: Bool

    var body: some View {
        if beleg {
            Image(systemName: "info.circle").foregroundStyle(.secondary)
        } else {
            Button {
                zustand.offenesInfo = zustand.offenesInfo == feld.id ? "" : feld.id
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(feld.info)
            .accessibilityLabel("Erklärung: \(feld.name)")
            .accessibilityIdentifier("info-\(feld.id)")
            .popover(isPresented: Binding(get: { zustand.offenesInfo == feld.id }, set: { if !$0, zustand.offenesInfo == feld.id { zustand.offenesInfo = "" } })) {
                Text(feld.info)
                    .font(.callout)
                    .frame(width: 340, alignment: .leading)
                    .padding(14)
                    .textSelection(.enabled)
            }
        }
    }
}

/// Das Rueckstell-Zeichen: immer da, stumpf auf der Vorgabe -- sonst ruckte die Zeile.
private struct ZurueckKnopf: View {
    let feld: Einstellungsfeld
    let zustand: EinstellungenZustand
    let beleg: Bool

    var body: some View {
        if let s = feld.schluessel, let d = zustand.daten {
            let steht = d.stehtAufVorgabe(s)
            let vorgabe = d.vorgaben[s]
            if beleg {
                Image(systemName: "arrow.uturn.backward.circle").foregroundStyle(steht ? .quaternary : .secondary)
            } else {
                Button {
                    if let v = vorgabe { Task { await zustand.setze(s, v) } }
                } label: {
                    Image(systemName: "arrow.uturn.backward.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(steht || vorgabe == nil)
                .help(steht ? zustand.texte.t("satz.stehtAufVorgabe") : zustand.texte.t("satz.zurueckAufVorgabe", ["wert": SeitenBauer(zustand: zustand, d: d, t: zustand.texte).kurzWert(vorgabe)]))
                .accessibilityLabel(zustand.texte.t("wort.zuruecksetzen"))
                .accessibilityIdentifier("zurueck-\(s)")
            }
        }
    }
}

// MARK: Die Bedienelemente

struct SteuerAnsicht: View {
    let feld: Einstellungsfeld
    let zustand: EinstellungenZustand
    let beleg: Bool
    /// Ein Klick aus der sichtbaren Oberflaeche ist ein Mensch; kopflos nie (Zustand.werkzeug prueft es noch einmal).
    private var echt: Bool { !zustand.kopflos }

    var body: some View {
        switch feld.art {
        case .schalter(let an, let setzen):
            if beleg {
                Label(an ? zustand.texte.t("wort.an") : zustand.texte.t("wort.aus"), systemImage: an ? "checkmark.square.fill" : "square")
            } else {
                Toggle(isOn: Binding(get: { an }, set: { setzen($0, echt) })) { EmptyView() }
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .accessibilityLabel(feld.name)
                    .accessibilityIdentifier(feld.id)
            }
        case .zahl(let wert, let min, let max, let einheit, let setzen):
            if beleg {
                Kasten("\(wert) \(einheit)")
            } else {
                ZahlFeld(id: feld.id, name: feld.name, wert: wert, min: min, max: max, einheit: einheit) { setzen($0, echt) }
            }
        case .text(let wert, let platzhalter, let setzen):
            if beleg {
                Kasten(wert.isEmpty ? platzhalter : wert, blass: wert.isEmpty)
            } else {
                TextFeld(id: feld.id, name: feld.name, wert: wert, platzhalter: platzhalter) { setzen($0, echt) }
            }
        case .eingabe(let platzhalter, let geheim, let mehrzeilig):
            let bindung = Binding(get: { zustand.eingaben[feld.id] ?? "" }, set: { zustand.eingaben[feld.id] = $0 })
            if beleg {
                Kasten(geheim ? platzhalter : (bindung.wrappedValue.isEmpty ? platzhalter : bindung.wrappedValue), blass: geheim || bindung.wrappedValue.isEmpty, hoch: mehrzeilig)
            } else if mehrzeilig {
                TextEditor(text: bindung)
                    .font(.body.monospaced())
                    .frame(minHeight: 110)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
                    .accessibilityLabel(platzhalter)
                    .accessibilityIdentifier(feld.id)
            } else if geheim {
                SecureField(platzhalter, text: bindung)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 180)
                    .accessibilityIdentifier(feld.id)
            } else {
                TextField(platzhalter, text: bindung)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .frame(minWidth: 140)
                    .onChange(of: bindung.wrappedValue) { _, _ in if feld.id.hasPrefix("suche:") { zustand.neuBauen() } }
                    .accessibilityIdentifier(feld.id)
            }
        case .wahl(let wert, let optionen, let setzen):
            let gewaehlt = optionen.first { $0.wert == wert }
            let alsMenue = Wahlform.menue(optionen, feld: feld, leerEintrag: gewaehlt == nil)
            if beleg {
                if !alsMenue {
                    // DER BELEG DARF NICHT ENGER SEIN ALS DAS ECHTE ELEMENT
                    // (08.09.2026). Das Bedienelement im Fenster ist ein
                    // `Picker(.segmented)` mit `fixedSize()` -- es bekommt immer
                    // seine Eigenbreite und bricht nie um. Diese Nachbildung
                    // hatte beides nicht: im Bild stand „Clau…" und „pi (l…"
                    // auf der Seite „Sitzung", „geteilt unter dem Ha…" auf
                    // „Aussehen", und auf „Maschinen" brach „nur Postfach"
                    // mitten im Segment um. Das war ein Fehler des BILDES, nicht
                    // des Fensters -- und ein Bild, das schlechter aussieht als
                    // die Sache, taugt nicht als Beleg.
                    HStack(spacing: 0) {
                        ForEach(optionen) { o in
                            Text(o.label).font(.callout).lineLimit(1)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(o.wert == wert ? AnyShapeStyle(.selection) : AnyShapeStyle(.clear))
                                .foregroundStyle(o.wert == wert ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                        }
                    }
                    .fixedSize()
                    .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.6)))
                } else {
                    Kasten(gewaehlt?.label ?? "–", pfeil: true).fixedSize()
                }
            } else {
                // Anzahl, ausdrueckliche Ansage oder BREITE -- die Entscheidung
                // steht in `Wahlform` und gilt fuer Fenster und Belegbild gleich.
                WahlPicker(feld: feld, wert: gewaehlt?.wert, optionen: optionen, menue: alsMenue) { setzen($0, echt) }
                    .help(gewaehlt?.titel ?? gewaehlt?.label ?? "")
            }
        case .knopf(let titel, let warnend, let hervorgehoben, let klick):
            if beleg {
                Text(titel).font(.callout)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Capsule().fill(hervorgehoben ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary)))
                    .foregroundStyle(hervorgehoben ? Color.white : (warnend ? Color.red : Color.primary))
            } else if hervorgehoben {
                Button(titel) { klick(echt) }.buttonStyle(.borderedProminent).accessibilityIdentifier(feld.id)
            } else if warnend {
                Button(titel, role: .destructive) { klick(echt) }.buttonStyle(.bordered).accessibilityIdentifier(feld.id)
            } else {
                Button(titel) { klick(echt) }.buttonStyle(.bordered).accessibilityIdentifier(feld.id)
            }
        case .klartext(let text):
            MessText(id: "klartext:\(feld.id)", text: text, zustand: zustand, beleg: beleg)
                .help(feld.info)
        case .leitsatz(let fett, let rest):
            (Text(fett).bold() + Text(rest))
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.quaternary.opacity(0.4)))
        case .zeilen(let zeilen, let leer):
            VStack(alignment: .leading, spacing: 6) {
                if zeilen.isEmpty {
                    Text(leer).font(.callout).foregroundStyle(.secondary)
                }
                ForEach(zeilen) { z in ZeileAnsicht(zeile: z, zustand: zustand, beleg: beleg) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .chips(let werte, let leer, let weg):
            Fluss(abstand: 6) {
                if werte.isEmpty { Text(leer).font(.callout).foregroundStyle(.secondary) }
                ForEach(werte, id: \.self) { w in
                    HStack(spacing: 4) {
                        Text(w).font(.body.monospaced())
                        if beleg {
                            Image(systemName: "xmark").font(.caption)
                        } else {
                            Button { weg(w) } label: { Image(systemName: "xmark").font(.caption) }
                                .buttonStyle(.plain)
                                .accessibilityLabel(zustand.texte.t("wort.entfernen") + " " + w)
                                .accessibilityIdentifier("weg:\(feld.id):\(w)")
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(.quaternary.opacity(0.6)))
                }
            }
        case .modelle(let schluessel, let gewaehlt, let zeigen, let filter, let filterWahl, _, let keinTreffer, let waehlen):
            VStack(alignment: .leading, spacing: 8) {
                if !filter.isEmpty {
                    if beleg {
                        Text(filter.map(\.label).joined(separator: "   ")).font(.callout).foregroundStyle(.secondary)
                    } else {
                        Picker(selection: Binding(get: { filterWahl }, set: { _ = zustand.klick("filter:\(schluessel):\($0)") })) {
                            ForEach(filter) { o in Text(o.label).tag(o.wert) }
                        } label: { EmptyView() }
                        .pickerStyle(.segmented).labelsHidden().fixedSize()
                        .accessibilityLabel("Programm")
                    }
                }
                SteuerAnsicht(feld: Einstellungsfeld("suche:\(schluessel)", .eingabe(platzhalter: zustand.texte.t("platzhalter.modellsuche"), geheim: false, mehrzeilig: false)), zustand: zustand, beleg: beleg)
                if zeigen.isEmpty { Text(keinTreffer).font(.callout).foregroundStyle(.secondary) }
                ForEach(zeigen) { m in
                    let ist = m.id == gewaehlt
                    let inhalt = HStack(alignment: .top, spacing: 8) {
                        Image(systemName: ist ? "largecircle.fill.circle" : "circle").foregroundStyle(ist ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        VStack(alignment: .leading, spacing: 2) {
                            HStack { Text(m.label); Text(m.id).font(.callout.monospaced()).foregroundStyle(.secondary) }
                            HStack {
                                Text(([m.harnessLabel] + (m.kontext > 0 ? ["\(m.kontext / 1000)k Kontext"] : [])).joined(separator: " · ")).font(.callout).foregroundStyle(.secondary)
                                if !m.startbar {
                                    Label(zustand.texte.t("wort.nichtStartbar", ["maschine": zustand.daten?.machine ?? ""]), systemImage: "exclamationmark.triangle")
                                        .font(.caption).foregroundStyle(.red)
                                }
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(ist ? AnyShapeStyle(.tint.opacity(0.12)) : AnyShapeStyle(.clear)))
                    if beleg {
                        inhalt
                    } else {
                        Button { waehlen(m.id) } label: { inhalt }
                            .buttonStyle(.plain)
                            .accessibilityLabel(m.label)
                            .accessibilityAddTraits(ist ? .isSelected : [])
                            .accessibilityIdentifier("modell:\(schluessel):\(m.id)")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .kontext(let k):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(k.stufen) { s in
                    let ist = s.tokens == k.wert
                    let inhalt = HStack(alignment: .top, spacing: 8) {
                        Image(systemName: ist ? "largecircle.fill.circle" : "circle").foregroundStyle(ist ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(s.label)
                                if s.tokens == k.empfehlung { Text(zustand.texte.t("wort.kontextEmpfohlen")).font(.caption).padding(.horizontal, 5).background(Capsule().fill(.tint.opacity(0.15))) }
                                Text(zustand.texte.t("wort.kontextToken", ["tokens": String(s.tokens)])).font(.callout.monospaced()).foregroundStyle(.secondary)
                            }
                            Text(!s.passt && !s.hinweis.isEmpty ? s.hinweis : zustand.texte.t("satz.kontextBedarf", ["bedarf": String(format: "%.1f", s.bedarfGib)]))
                                .font(.callout).foregroundStyle(!s.passt && !s.hinweis.isEmpty ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(ist ? AnyShapeStyle(.tint.opacity(0.12)) : AnyShapeStyle(.clear)))
                    if beleg {
                        inhalt
                    } else {
                        Button { _ = zustand.klick("kontext:\(s.tokens)") } label: { inhalt }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("kontext:\(s.tokens)")
                    }
                }
                Label(k.fuss, systemImage: k.fussWarnt ? "exclamationmark.triangle" : "memorychip")
                    .font(.callout).foregroundStyle(k.fussWarnt ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
            }
        case .tabelle(let kopf, let zeilen, let leer):
            TabellenAnsicht(id: feld.id, kopf: kopf, zeilen: zeilen, leer: leer, zustand: zustand, beleg: beleg)
        case .farben(let farben, let setzen):
            HStack(spacing: 16) {
                ForEach(farben, id: \.zustand) { f in
                    if beleg {
                        HStack(spacing: 4) {
                            Circle().fill(Color(hex: f.hex) ?? .gray).frame(width: 14, height: 14)
                            Text(f.label); Text(f.hex).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    } else {
                        ColorPicker(f.label, selection: Binding(get: { Color(hex: f.hex) ?? .gray }, set: { if let h = $0.hex { setzen(f.zustand, h) } }), supportsOpacity: false)
                            .accessibilityIdentifier("farbe-\(f.zustand)")
                    }
                }
            }
        case .reihe(let felder):
            HStack(alignment: .top, spacing: 8) {
                ForEach(felder) { f in SteuerAnsicht(feld: f, zustand: zustand, beleg: beleg) }
            }
        case .stapel(let felder):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(felder) { f in SteuerAnsicht(feld: f, zustand: zustand, beleg: beleg) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// SPALTEN, DIE IHRE UEBERSCHRIFT TRAGEN (08.09.2026, Rest aus der Abnahme).
///
/// Bis hierher bekam jede Spalte denselben Anteil an der Breite, und wo die
/// Ueberschrift laenger war als dieser Anteil, wurde sie abgeschnitten: auf der
/// Seite „Programme und Modelle" stand im kleinsten erlaubten Fenster
/// (820 x 560) „Auf dieser Ma…". Ein halbes Wort in einer Ueberschrift ist ein
/// Befund (abnahme.md), und geraten wird die Breite nicht: sie haengt an der
/// Sprache („Auf dieser Maschine" gegen „On this machine") und an der
/// Textgroesse des Systems.
///
/// Jede Spalte bekommt deshalb ZUERST, was ihre Ueberschrift in der Schrift des
/// Kopfes wirklich braucht, und der Rest der Breite wird gleichmaessig verteilt.
/// Genommen wird nur den Spalten, die mehr haetten, als ihre Ueberschrift
/// braucht, und nur so viel, wie sie uebrig haben -- die Aufteilung bleibt
/// damit fast die alte, sie weicht nur dort aus, wo eine Ueberschrift es
/// verlangt. Reicht auch das nicht, bekommt jede Spalte ihren Anteil an dem,
/// was sie braucht, und die Ueberschriften umbrechen (`fixedSize`), statt ein
/// Wort zu verlieren -- so haelt es die Electron-Fassung ohnehin
/// (einstellungen/index.html: kein `white-space: nowrap` an `th`).
///
/// EIN EIGENES `Layout` UND KEIN `GeometryReader`, weil die Breite erst beim
/// Auslegen feststeht: ein GeometryReader braeuchte einen zweiten Durchgang,
/// und das Belegbild entsteht in EINEM (ImageRenderer, `schuss`) -- es haette
/// wieder gleiche Spalten gezeigt und damit etwas anderes als das Fenster.
struct Spaltenraster: Layout {
    /// Was jede Ueberschrift braucht, in der Reihenfolge der Spalten.
    let noetig: [CGFloat]
    var abstand: CGFloat = 8

    /// Die Breiten fuer eine gegebene Gesamtbreite. Steht auch der Auskunft zur
    /// Verfuegung (`tabellenAuskunft`), damit eine Suite „nichts abgeschnitten"
    /// pruefen kann, ohne eine Zahl zu kennen.
    static func breiten(noetig: [CGFloat], gesamt: CGFloat, abstand: CGFloat = 8) -> [CGFloat] {
        let n = noetig.count
        guard n > 0 else { return [] }
        let frei = max(0, gesamt - abstand * CGFloat(n - 1))
        let gleich = frei / CGFloat(n)
        var b = noetig.map { max($0, gleich) }
        let ueber = b.reduce(0, +) - frei
        guard ueber > 0.5 else { return b }
        let luft = zip(b, noetig).map { $0 - $1 }
        let summeLuft = luft.reduce(0, +)
        if summeLuft >= ueber {
            for i in b.indices { b[i] -= ueber * luft[i] / summeLuft }
            return b
        }
        let summe = noetig.reduce(0, +)
        return summe > 0 ? noetig.map { frei * $0 / summe } : Array(repeating: gleich, count: n)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let gesamt = proposal.width ?? subviews.reduce(CGFloat(0)) { $0 + $1.sizeThatFits(.unspecified).width }
        let b = Self.breiten(noetig: noetig, gesamt: gesamt, abstand: abstand)
        var hoehe: CGFloat = 0
        for (i, s) in subviews.enumerated() where i < b.count {
            hoehe = max(hoehe, s.sizeThatFits(ProposedViewSize(width: b[i], height: nil)).height)
        }
        return CGSize(width: gesamt, height: hoehe)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let b = Self.breiten(noetig: noetig, gesamt: bounds.width, abstand: abstand)
        var x = bounds.minX
        for (i, s) in subviews.enumerated() where i < b.count {
            s.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading, proposal: ProposedViewSize(width: b[i], height: nil))
            x += b[i] + abstand
        }
    }
}

/// Eine Tabelle einer Einstellungsseite. Keine `Grid`: sie sprengt im Beleg die
/// Spaltenbreite (gemessen, Statusfuss 2.5). Jede Zelle bricht in sich um.
struct TabellenAnsicht: View {
    let id: String
    let kopf: [String]
    let zeilen: [TabellenZeile]
    let leer: String
    let zustand: EinstellungenZustand
    let beleg: Bool

    /// Die Schrift des Kopfes als `NSFont` -- dieselbe, die `.caption.weight(.semibold)`
    /// unten zeichnet; nur so ist die gemessene Breite die wirkliche.
    static var kopfschrift: NSFont {
        NSFont.systemFont(ofSize: NSFont.preferredFont(forTextStyle: .caption1).pointSize, weight: .semibold)
    }

    static func noetig(_ kopf: [String]) -> [CGFloat] {
        kopf.map { ceil(NSAttributedString(string: $0, attributes: [.font: kopfschrift]).size().width) + 1 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !kopf.isEmpty {
                Spaltenraster(noetig: Self.noetig(kopf)) {
                    ForEach(Array(kopf.enumerated()), id: \.offset) { _, h in
                        Text(h).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Divider()
            }
            if zeilen.isEmpty { Text(leer).font(.callout).foregroundStyle(.secondary) }
            ForEach(zeilen) { z in
                zeile(z)
                Divider()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // WAS DIE TABELLE WIRKLICH BEKOMMEN HAT, damit eine Suite es nachrechnen
        // kann (`ui.einstellungen.tabellen`). Nur aus dem lebenden Fenster: das
        // Belegbild zeichnet dieselben Seiten ein zweites Mal und wuerde den
        // gemessenen Stand mit seiner eigenen Breite ueberschreiben.
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { breite in
            guard !beleg, !kopf.isEmpty else { return }
            zustand.tabellenmass[id] = (kopf: kopf, breite: breite)
        }
    }

    @ViewBuilder private func zeile(_ z: TabellenZeile) -> some View {
        let inhalt = Group {
            if kopf.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(Array(z.zellen.enumerated()), id: \.offset) { _, zelle in
                        ZelleAnsicht(zelle: zelle, zustand: zustand, beleg: beleg)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                Spaltenraster(noetig: Self.noetig(kopf)) {
                    ForEach(Array(z.zellen.enumerated()), id: \.offset) { _, zelle in
                        ZelleAnsicht(zelle: zelle, zustand: zustand, beleg: beleg)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        inhalt
            .foregroundStyle(z.warnung ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(z.id)
    }
}

/// Eine Zeile einer Liste: Schalter, Titel, Grund, rechts Code, Antwort und Knoepfe.
private struct ZeileAnsicht: View {
    let zeile: Zeile
    let zustand: EinstellungenZustand
    let beleg: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let s = zeile.schalter {
                    SteuerAnsicht(feld: s, zustand: zustand, beleg: beleg)
                    if !s.name.isEmpty { Text(s.name).font(.callout) }
                    if !s.info.isEmpty && !beleg {
                        Image(systemName: "info.circle").foregroundStyle(.secondary).help(s.info)
                    }
                }
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(zeile.titel)
                        if !zeile.marke.isEmpty {
                            Text(zeile.marke).font(.caption).padding(.horizontal, 5).background(Capsule().fill(.quaternary))
                        }
                    }
                    if !zeile.grund.isEmpty { Text(zeile.grund).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                }
                Spacer(minLength: 8)
                // DIE STEUERUNG BEKOMMT IHRE BREITE ZUERST (08.09.2026). Vorher
                // teilte die Zeile die Breite nach Bedarf, und der Erklaertext
                // links nahm sie sich: auf der Seite „Sitzung" stand dann
                // „Clau…" und „pi (l…" im Umschalter, auf „Aussehen"
                // „geteilt unter dem Ha…", auf „Maschinen" brach „nur Postfach"
                // mitten im Segment um. Ein halbes Wort in einem Bedienelement
                // ist ein Befund (abnahme.md). Der Erklaertext umbricht ohnehin
                // (`fixedSize(horizontal: false)`) und gibt die Breite her,
                // ohne etwas zu verlieren.
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if !zeile.code.isEmpty { Text(zeile.code).font(.callout.monospaced()).foregroundStyle(.secondary) }
                    if !zeile.antwort.isEmpty {
                        Label(zeile.antwort, systemImage: zeile.antwortArt == "gut" ? "checkmark.circle" : (zeile.antwortArt == "schlecht" ? "xmark.octagon" : "ellipsis.circle"))
                            .font(.callout)
                            .foregroundStyle(zeile.antwortArt == "gut" ? AnyShapeStyle(.green) : (zeile.antwortArt == "schlecht" ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary)))
                    }
                    ForEach(zeile.rechts) { f in SteuerAnsicht(feld: f, zustand: zustand, beleg: beleg).controlSize(.small) }
                }
                .layoutPriority(1)
            }
            if !zeile.unten.isEmpty { Text(zeile.unten).font(.callout).foregroundStyle(.secondary).padding(.leading, 4) }
        }
        .opacity(zeile.abgeschaltet ? 0.6 : 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(zeile.id)
    }
}

private struct ZelleAnsicht: View {
    let zelle: Zelle
    let zustand: EinstellungenZustand
    let beleg: Bool

    var body: some View {
        switch zelle {
        case .text(let t, let sekundaer, let titel):
            Text(t).font(.callout).foregroundStyle(sekundaer ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .fixedSize(horizontal: false, vertical: true).help(titel)
        case .zwei(let a, let b):
            VStack(alignment: .leading, spacing: 1) {
                Text(a).font(.callout)
                Text(b).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
        case .feld(let f):
            SteuerAnsicht(feld: f, zustand: zustand, beleg: beleg).controlSize(.small)
        case .felder(let fs):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(fs) { f in
                    HStack(spacing: 6) {
                        SteuerAnsicht(feld: f, zustand: zustand, beleg: beleg).controlSize(.small)
                        if !f.info.isEmpty, !beleg { Image(systemName: "info.circle").foregroundStyle(.secondary).help(f.info) }
                    }
                }
            }
        }
    }
}

/// Ein Zahlenfeld mit Stepper: getippt wird lokal, geschrieben beim Verlassen oder
/// Bestaetigen; der Stepper schreibt sofort. Ausserhalb von min/max wird nichts
/// geschrieben und der alte Wert bleibt stehen (test-app-einstellungen 13).
private struct ZahlFeld: View {
    let id: String
    let name: String
    let wert: Int
    let min: Int
    let max: Int
    let einheit: String
    let setzen: (Int) -> Void
    @State private var text = ""
    @FocusState private var fokus: Bool

    var body: some View {
        HStack(spacing: 6) {
            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 64)
                .multilineTextAlignment(.trailing)
                .focused($fokus)
                .onSubmit(uebernehmen)
                .onChange(of: fokus) { _, hat in if !hat { uebernehmen() } }
                .onAppear { text = String(wert) }
                .onChange(of: wert) { _, neu in text = String(neu) }
                .accessibilityLabel(name)
                .accessibilityIdentifier(id)
            Stepper(value: Binding(get: { wert }, set: { setzen(Swift.min(max, Swift.max(min, $0))) }), in: min...max) { EmptyView() }
                .labelsHidden()
                .accessibilityLabel(name)
            if !einheit.isEmpty { Text(einheit).font(.callout).foregroundStyle(.secondary) }
        }
    }

    private func uebernehmen() {
        guard let n = Int(text.trimmingCharacters(in: .whitespaces)) else { text = String(wert); return }
        guard n >= min, n <= max else { text = String(wert); return }
        if n != wert { setzen(n) }
    }
}

/// Eine Zeile Text, geschrieben beim Verlassen -- nicht bei jedem Tastendruck
/// (sonst stuende nach „~/A" schon ein halber Pfad in der geteilten Datei).
private struct TextFeld: View {
    let id: String
    let name: String
    let wert: String
    let platzhalter: String
    let setzen: (String) -> Void
    @State private var text = ""
    @FocusState private var fokus: Bool

    var body: some View {
        TextField(platzhalter, text: $text)
            .textFieldStyle(.roundedBorder)
            .autocorrectionDisabled()
            .frame(minWidth: 220)
            .focused($fokus)
            .onSubmit(uebernehmen)
            .onChange(of: fokus) { _, hat in if !hat { uebernehmen() } }
            .onAppear { text = wert }
            .onChange(of: wert) { _, neu in text = neu }
            .accessibilityLabel(name)
            .accessibilityIdentifier(id)
    }

    private func uebernehmen() {
        let neu = text.trimmingCharacters(in: .whitespaces)
        if neu != wert { setzen(neu) }
    }
}

/// Der Beleg eines Eingabefelds: der Wert in einem Kasten, ohne AppKit.
private struct Kasten: View {
    let text: String
    var blass = false
    var pfeil = false
    var hoch = false

    init(_ text: String, blass: Bool = false, pfeil: Bool = false, hoch: Bool = false) {
        self.text = text; self.blass = blass; self.pfeil = pfeil; self.hoch = hoch
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(text).font(.callout).foregroundStyle(blass ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary)).lineLimit(hoch ? 6 : 1)
            if pfeil { Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .frame(minWidth: 60, minHeight: hoch ? 110 : 0, alignment: hoch ? .topLeading : .leading)
        .background(RoundedRectangle(cornerRadius: 5).fill(.background))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.quaternary))
    }
}

/// Eintraege, die in Zeilen umbrechen (die Chips der Ausschlusslisten).
private struct Fluss: Layout {
    var abstand: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let breite = proposal.width ?? 600
        var x: CGFloat = 0, y: CGFloat = 0, zeilenHoehe: CGFloat = 0
        for s in subviews {
            let g = s.sizeThatFits(.unspecified)
            if x > 0, x + g.width > breite { x = 0; y += zeilenHoehe + abstand; zeilenHoehe = 0 }
            x += g.width + abstand
            zeilenHoehe = Swift.max(zeilenHoehe, g.height)
        }
        return CGSize(width: breite, height: y + zeilenHoehe)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, zeilenHoehe: CGFloat = 0
        for s in subviews {
            let g = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + g.width > bounds.maxX { x = bounds.minX; y += zeilenHoehe + abstand; zeilenHoehe = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(g))
            x += g.width + abstand
            zeilenHoehe = Swift.max(zeilenHoehe, g.height)
        }
    }
}

/// WANN SEGMENTLEISTE, WANN AUFKLAPPMENUE -- EINE STELLE (08.09.2026).
///
/// Bis heute entschied allein die ANZAHL: bis sechs Eintraege eine
/// Segmentleiste, darueber ein Menue (dieselbe Schwelle wie `segmente()` in
/// einstellungen.ts). Die Anzahl ist aber nicht das, was ueberlaeuft, sondern
/// die BREITE. Gemessen am 08.09.2026 auf der Seite „Erlaubnisse": sechs
/// Eintraege, laengster „Änderungen annehmen" (141 pt) -- SwiftUI gibt jedem
/// Segment die Breite des laengsten, macht also 6 x 161 = 966 Punkte daraus.
/// Mit `fixedSize()` laesst sich das nicht zusammenschieben, und weil die
/// Zeile damit breiter war als das Fenster, rutschte der ganze Seiteninhalt
/// nach links unter die Seitenleiste und rechts aus dem Fenster hinaus: Titel
/// und Absatz waren angeschnitten, das letzte Segment gar nicht mehr da. Das
/// ist Befund des Nutzers „in den Einstellungen sieht man manches nicht, weil
/// sich Dinge ueberlagern, vor allem mit der linken Seitenleiste".
///
/// Deshalb entscheidet ab jetzt auch die Breite. Das Budget von 460 Punkten
/// ist das, was im KLEINSTEN erlaubten Fenster in eine Zeile passt: 820 Punkte
/// Fenster, davon 200 die Seitenleiste, bleiben 620 fuer den Inhalt; abzueglich
/// der Einzuege des gruppierten `Form` und der Gruppenraender bleibt eine Zeile
/// von rund 500 Punkten. Die vorhandenen Leisten liegen alle darunter -- die
/// breiteste ist „geteilt unter dem Hauptfenster | eigenes Fenster" mit 414 --,
/// nur die Erlaubnisstufe geht darueber und wird zum Aufklappmenue. Apples
/// Vorgabe sagt dasselbe: lange Beschriftungen gehoeren in ein Aufklappmenue,
/// nicht in eine Segmentleiste.
@MainActor
enum Wahlform {
    /// Wie viele Punkte eine Segmentleiste breit WUERDE. SwiftUI gibt jedem
    /// Segment die Breite des laengsten Eintrags; die 20 Punkte Innenabstand je
    /// Segment sind am gezeichneten Element gemessen (966 / 6 - 141 = 20).
    static func segmentbreite(_ optionen: [Option], leerEintrag: Bool) -> CGFloat {
        guard !optionen.isEmpty else { return 0 }
        let schrift = NSFont.preferredFont(forTextStyle: .body)
        let breiteste = optionen.reduce(CGFloat(0)) {
            max($0, ceil(NSAttributedString(string: $1.label, attributes: [.font: schrift]).size().width))
        }
        return CGFloat(optionen.count + (leerEintrag ? 1 : 0)) * (breiteste + 20)
    }

    /// Was in eine Zeile des kleinsten erlaubten Fensters passt.
    static let budget: CGFloat = 460

    /// Aufklappmenue statt Segmentleiste? Die Stelle, die Fenster UND Belegbild
    /// gleich beantworten -- ein Bild, das anders entscheidet als das Fenster,
    /// taugt nicht als Beleg.
    static func menue(_ optionen: [Option], feld: Einstellungsfeld, leerEintrag: Bool) -> Bool {
        optionen.count > 6 || feld.menue || segmentbreite(optionen, leerEintrag: leerEintrag) > budget
    }
}

/// Die Wahl: Segmentleiste oder Aufklappmenue, beides Systemsteuerelemente.
/// Ein gespeicherter Wert, der nicht in der Liste steht, waehlt NICHTS aus --
/// sonst behauptete das Menue eine Wahl, die niemand getroffen hat.
private struct WahlPicker: View {
    let feld: Einstellungsfeld
    let wert: String?
    let optionen: [Option]
    let menue: Bool
    let setzen: (String) -> Void
    private static let keiner = "\u{0}"

    var body: some View {
        let bindung = Binding(get: { wert ?? Self.keiner }, set: { if $0 != Self.keiner { setzen($0) } })
        Group {
            if menue {
                Picker(selection: bindung) { eintraege } label: { EmptyView() }.pickerStyle(.menu)
            } else {
                Picker(selection: bindung) { eintraege } label: { EmptyView() }.pickerStyle(.segmented)
            }
        }
        .labelsHidden()
        .fixedSize()
        .accessibilityLabel(feld.name)
        .accessibilityIdentifier(feld.id)
    }

    @ViewBuilder private var eintraege: some View {
        if wert == nil { Text("–").tag(Self.keiner) }
        ForEach(optionen) { o in Text(o.label).tag(o.wert).help(o.titel ?? "") }
    }
}

extension Color {
    /// `#rrggbb` (auch `#rgb`) -- die Form der Zustandsfarben in settings.json.
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        guard s.hasPrefix("#") else { return nil }
        s.removeFirst()
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, let n = UInt32(s, radix: 16) else { return nil }
        self.init(red: Double((n >> 16) & 0xFF) / 255, green: Double((n >> 8) & 0xFF) / 255, blue: Double(n & 0xFF) / 255)
    }

    var hex: String? {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return String(format: "#%02x%02x%02x", Int(round(c.redComponent * 255)), Int(round(c.greenComponent * 255)), Int(round(c.blueComponent * 255)))
    }
}
