// Das Fenster: Seitenleiste (SwiftUI in einem NSSplitViewController), eine
// Symbolleiste im Titel mit dem Kopf (Name als Titel, Herkunft als Untertitel,
// Pille „N laufen“, Umschalter Orchestrator/Worker, Zahnrad -- Kopf.swift),
// und der Inhaltsbereich mit den Terminal-Panes. Menueleiste mit den
// Standardmenues. Hell und dunkel kommen vom System.
//
// WARUM NSSplitViewController UND NICHT NavigationSplitView (gemessen am
// 06.09.2026, mac/PLAN.md): in einem Fenster, das nie auf dem Bildschirm war,
// baut SwiftUI die Seitenleisten-Spalte von NavigationSplitView nicht auf --
// die Spalte blieb im Sichtbaum leer (kein NSHostingView darin), auch nach vier
// Sekunden und mit `columnVisibility: .all`. Jede Pruefung laeuft aber kopflos.
// NSSplitViewController mit einem `sidebar`-Item hostet die SwiftUI-Liste
// sofort, bringt Seitenleisten-Material, Umschalten (⌃⌘S) und die
// Symbolleisten-Trennung von selbst mit, und ist auf dem Mac ohnehin die
// native Bauart hinter NavigationSplitView.
import AppKit
import SwiftUI
import WerkbankProtokoll

enum Ansicht: String, Sendable {
    case orchestrator, worker
}

/// WELCHE BUEHNE STEHT (Auftrag macagents, 08.09.2026; seit dem 14.09.2026
/// Auftrag agentsui Nr. 6). Der Umschalter `Code | Agents` in der Mitte der
/// Symbolleiste: `code` ist die gewaehlte Sitzung mit Terminal, Gespraech und
/// Editor, `agents` die Welten der Agents (WeltenBlatt.swift). Im Zustand
/// Agents wechselt nicht nur die Mitte: die Leiste der Welt ersetzt links die
/// Seitenleiste mit Projekten und Sitzungen, rechts steht der Inspektor der
/// Welt, und Zaehler und Pausenschalter der Welt stehen in der Symbolleiste.
///
/// Die Wahl gehoert dem Fenster und nicht dem Kern: `ui.json` hat keinen
/// Schluessel dafuer. Sie ueberlebt deshalb den Neustart nicht -- die Werkbank
/// geht immer mit der Sitzung auf.
enum Buehnenmodus: String, Sendable {
    case code, agents
}

@MainActor
@Observable
final class Oberflaeche {
    /// Die WAHL des Umschalters (womit die Sitzung aufgeht); was er zeigt, sagt die Buehne (Kopf.swift).
    var ansicht: Ansicht = .orchestrator
    /// Welche Buehne steht: die Sitzung (`code`) oder das Agents-Blatt.
    var modus: Buehnenmodus = .code
    var einstellungenOffen = false
    /// Das Sitzungsfenster (⌘N, Sitzungsblatt.swift) ist gebaut -- kopflos nur als Zustand.
    var sitzungenOffen = false
    /// Die Worker-Liste hinter der Pille ist offen (kopflos nur als Zustand).
    var workerListeOffen = false
    /// Das offene Namensfeld (`awb:umbenennen`): kopflos nur als Zustand, sichtbar als Sheet.
    var umbenennen: UmbenennenNutzlast?
    /// Die letzte Rueckfrage (Titel) und ihre Antwort -- fuer `awbmac-ctl ui`.
    var letzteRueckfrage = ""
    var letzteRueckfrageAntwort = ""
    /// Die Maschinenkarte, deren Popover offen ist (Name; leer = keines). Als
    /// Name, nicht als View: der Fuss wird im Takt neu gezeichnet (Lehre aus
    /// fuss-status.ts, 05.09.).
    var offeneKarte = ""
    /// Welches Blatt der Inspektor zeigt (Auftraege 3.5/3.6, Inspektor.swift) -- im Zustand Code.
    var blatt: BlattWahl = .freigaben
    /// Die letzte Ergebnismeldung (`awb:ergebnis`) und bis wann sie steht.
    var ergebnis: ErgebnisNutzlast?
    var ergebnisBis = Date.distantPast

    // MARK: Zugeklappte Projekte (Politur 08.09.)

    /// Die Ordner der Projekte, deren Abschnitt in der Seitenleiste zu ist.
    /// GEMERKT WIRD DAS ZUGEKLAPPTE, nicht das offene: ein Projekt, das die
    /// Werkbank noch nie gesehen hat, geht damit offen auf -- so wie die
    /// Electron-Fassung es tut, solange niemand ein Projekt angefasst hat
    /// (renderer.ts `projektOffen`, `baumBeruehrt`).
    ///
    /// Anders als dort ueberlebt die Wahl hier den Neustart. Der Kern fuehrt
    /// sie nicht (in `ui.json` gibt es keinen Schluessel dafuer, nachgesehen am
    /// 08.09.), also liegt sie da, wo der Mantel schon die Fensterlage haelt --
    /// und aus demselben Grund kopflos in einer Datei statt in den
    /// Voreinstellungen: eine Pruefung fasst die Live-Konfiguration nie an
    /// (regeln/tests-und-eingriffe.md).
    var zugeklappteProjekte: Set<String> = []
    /// Wohin die Wahl geschrieben wird. Kopflos eine Datei im Laufverzeichnis,
    /// sichtbar die Voreinstellungen; leer heisst „nirgends".
    /// Wie diese App laeuft -- Merker.swift entscheidet daran, wohin die Wahl geht.
    var optionen = Laufoptionen()
    static let klappSchluessel = "werkbank.zugeklappteProjekte"

    /// Ein Projekt auf- oder zuklappen und die Wahl sofort festhalten.
    func projektKlappen(_ id: String, offen: Bool) {
        guard !id.isEmpty else { return }
        if offen { zugeklappteProjekte.remove(id) } else { zugeklappteProjekte.insert(id) }
        klappMerken()
    }

    /// Beim Start einmal holen, was zuletzt zugeklappt war.
    func klappHerstellen() {
        zugeklappteProjekte = Set(Merker.liste(datei: Merker.zugeklappteProjekte,
                                               schluessel: Self.klappSchluessel, optionen))
    }

    private func klappMerken() {
        Merker.setzen(zugeklappteProjekte.sorted(), datei: Merker.zugeklappteProjekte,
                      schluessel: Self.klappSchluessel, optionen)
    }
}

@MainActor
final class Fenster: NSObject, NSToolbarDelegate, NSWindowDelegate, NSMenuItemValidation, NSMenuDelegate, Sitzungshandlungen, Freigabehandlungen, Fusshandlungen {
    let optionen: Laufoptionen
    let kern: KernVerbindung
    let oberflaeche = Oberflaeche()
    let fenster: NSWindow
    let splitController = Aufteilung()
    let terminal: TerminalBereich
    /// Die Chat-Buehne (Auftrag 3.2, ChatBuehne.swift): der Zustand der Sitzung,
    /// die liegt, und ihre Ansicht an der Stelle der Kacheln.
    let chat: ChatZustand
    private let chatBuehne: NSHostingView<ChatBuehne>
    /// DIE WELTEN IM TAB „AGENTS" (Auftrag agentsui Nr. 6): EIN Zustand fuer den
    /// Tab und fuer das Fenster „Agents-Welten …", und die drei Teile der Ansicht
    /// an den drei Stellen des Fensters -- die Leiste neben der Seitenleiste, die
    /// Mitte auf der Buehne, der Inspektor neben dem Inspektor der Blaetter. Sie
    /// entstehen sofort (sie lesen nur, was der Kern schickt) und liegen
    /// versteckt, solange der Umschalter auf Code steht.
    let weltenZustand: WeltenZustand
    private let weltenMitte: NSHostingView<WeltenMitteSpalte>
    private var weltenLeiste: NSHostingView<WeltenLeisteSpalte>!
    private var weltenInspektor: NSHostingView<WeltenInspektorSpalte>!
    /// Die Seitenleiste mit Projekten und Sitzungen und das Blatt des Inspektors --
    /// die Ansichten, die im Zustand Agents den Welten weichen.
    private var seitenleisteHost: NSView!
    private var inspektorHost: NSView!
    /// Ob der Inspektor offen war, als der Umschalter auf Agents ging -- der Rueckweg stellt es her.
    private var codeInspektorOffen = false
    /// Was `weltenInspektorNachfuehren` zuletzt hergestellt hat (nil: der Tab steht nicht).
    private var weltenInspektorGesetzt: Bool?
    /// Die Breite der Seitenleiste, als der Umschalter auf Agents ging, und die Mindestbreite der
    /// Leiste der Welt (die ideale Breite ihrer Spalte im Fenster „Agents-Welten …“).
    private var codeSeitenBreite = 0
    static let weltenLeisteBreite = 290
    /// Kopf: Titel, Pille, Umschalter (Kopf.swift). Nach `super.init` gebaut, weil er `self` haelt.
    private(set) var kopf: Kopf!
    private let leerHinweis: NSHostingView<LeerAnsicht> = {
        let v = NSHostingView(rootView: LeerAnsicht())
        v.sizingOptions = []
        return v
    }()
    /// Der Klick, der einen lang stehenden Hinweis im Fuss wegraeumt (wie
    /// Electron: ab 4 s jeder Klick, Statusfuss.swift).
    private var klickBeobachter: Any?
    // Freigaben (Auftrag 2.4): die Leiste unter der Symbolleiste, das Blatt im
    // Inspektor rechts, der Zustand, den beide und der Steuerkanal teilen.
    let freigabenZustand = FreigabenZustand()
    private var freigabeLeiste: NSHostingView<FreigabeLeiste>!
    /// Der Tab-Streifen unter der Symbolleiste (Auftrag 2.3), nur ab zwei Tabs.
    private var tabStreifen: NSHostingView<TabStreifen>!
    /// Das Editor-Blatt (Auftrag 3.4): sein Zustand entsteht sofort (billig),
    /// der Baustein erst beim ersten Oeffnen (Highlightr laedt einen JSContext).
    let editorZustand: EditorBlattZustand
    private var editorLeiste: NSHostingView<EditorTabLeiste>!
    private var editorBlatt: EditorBlatt?

    /// Die drei uebrigen Blaetter des Inspektors (Auftraege 3.5/3.6) und der
    /// eine Weg, auf dem ein angeklickter Pfad aufgeht.
    let ordnerZustand: OrdnerZustand
    let aktivitaetZustand: AktivitaetZustand
    let protokolleZustand: ProtokolleZustand
    let pfadOeffner: Pfadoeffner
    /// Die Buehne selbst -- der Editor kommt erst spaeter an ihre Stelle.
    private var buehneView: NSView!
    private var letzteMarken: [TabMarke] = []
    private var letzterTab = -1
    /// Die vier Einzuege links an der Buehne (siehe `buehnenEinzugNachfuehren`).
    private var buehnenEinzuege: [NSLayoutConstraint] = []
    private var inspektorItem: NSSplitViewItem?
    private var seitenItem: NSSplitViewItem!
    // Seitenleisten- und Inspektorbreite (Auftrag 2.8): der Kern merkt beide
    // in ui.json (`sidebarWidth`, `blattBreite`, wie die Electron-Fassung);
    // der Mantel stellt sie beim Start einmal her und meldet danach, was der
    // Mensch am Teiler zieht -- nie das, was er selbst gerade einstellt.
    private var breitenAngewandt = false
    private var stelleBreitenEin = false
    private var gemeldeteBreiten: (seite: Int, blatt: Int) = (0, 0)
    private var breitenTimer: Timer?
    private var teilerBeobachter: Any?
    /// Erst nach dem Herstellen der Lage wird sie gemerkt: die Vorgabegroesse
    /// beim Bau loeste sonst `windowDidResize` aus und ueberschrieb den
    /// gemerkten Rahmen, bevor er gelesen war (gemessen 06.09.).
    private var lageBereit = false
    /// Ein Start laeuft gerade -- ein zweiter Klick auf ein Plus soll keine
    /// zweite Sitzung anlegen (derselbe Schutz wie im Sitzungsfenster).
    private var sitzungLaeuftAn = false
    static let rahmenName = "Werkbank.Hauptfenster"
    private var freigabenItem: NSToolbarItem?
    private var letzteOffene = -1
    /// Das Einstellungsfenster (Einstellungen.swift), gebaut beim ersten Bedarf.
    private(set) var einstellungen: EinstellungenFenster?
    /// Das Sitzungsfenster (Sitzungsblatt.swift, Auftrag 2.7), gebaut beim ersten Bedarf.
    private(set) var sitzungen: SitzungsFenster?
    /// Der gefuehrte erste Start (Erststart.swift, Auftrag 3.8) als Sheet.
    private(set) var erststart: ErststartSheet?
    /// Die Verbrauchsseite (Verbrauchsfenster.swift, Auftrag 3.8) als eigenes Fenster.
    private(set) var verbrauch: VerbrauchsFenster?
    /// Das Vorschau-Blatt der Agentenfiguren (AgentenfigurenFenster.swift), gebaut beim ersten Bedarf.
    private(set) var figuren: AgentenfigurenFenster?
    /// Das Vorab-Blatt der Agents nach Fassung 28 (WeltenFenster.swift), gebaut beim ersten Bedarf.
    private(set) var welten: WeltenFenster?
    private var beobachtung: Any?
    private var letzteSitzung = ""
    /// Ein Worker-Pane, der gezeigt werden soll, sobald seine Sitzung gewaehlt ist.
    private var wunschPane: (sitzung: String, pane: String)?
    /// Derselbe Wunsch, bis die Lage des Kerns ihn zeigt: das `select` haengt
    /// den Kern an und zeichnet den Orchestrator -- kommt diese Lage NACH dem
    /// `show-pane`, ueberschreibt sie ihn (gemessen 06.09., test-mac-sitzungsbaum
    /// Zusage 10, einmal in drei Laeufen). Also wird der Pane so lange
    /// nachgefordert, bis eine Lage der Sitzung ihn traegt, hoechstens 3 s.
    private var wunschOffen: (sitzung: String, pane: String, bis: Date)?

    init(optionen: Laufoptionen, kern: KernVerbindung) {
        self.optionen = optionen
        self.kern = kern
        self.terminal = TerminalBereich(art: optionen.terminal, kern: kern, optionen: optionen, kopflos: optionen.kopflos)
        chat = ChatZustand(kern: kern)
        chatBuehne = NSHostingView(rootView: ChatBuehne(zustand: chat))
        chatBuehne.sizingOptions = []
        weltenZustand = WeltenZustand()
        weltenZustand.kern = kern
        weltenMitte = NSHostingView(rootView: WeltenMitteSpalte(kern: kern, zustand: weltenZustand))
        weltenMitte.sizingOptions = []
        editorZustand = EditorBlattZustand(kern: kern, optionen: optionen)
        ordnerZustand = OrdnerZustand(kern: kern)
        aktivitaetZustand = AktivitaetZustand(kern: kern, editor: editorZustand)
        protokolleZustand = ProtokolleZustand(kern: kern, editor: editorZustand)
        pfadOeffner = Pfadoeffner(kern: kern, editor: editorZustand)
        let haupt = Hauptfenster(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        haupt.groesserAlsBildschirm = optionen.pruefmodus
        fenster = haupt
        super.init()
        // Zugeklappte Projekte (Politur 08.09.): kopflos in einer Datei im
        // Laufverzeichnis, sichtbar in den Voreinstellungen -- derselbe Weg wie
        // die Fensterlage, aus demselben Grund (siehe `lageDatei`).
        oberflaeche.optionen = optionen
        oberflaeche.klappHerstellen()
        freigabeLeiste = NSHostingView(rootView: FreigabeLeiste(kern: kern, zustand: freigabenZustand, handlungen: self))
        // Nur die Eigengroesse, keine Min-/Max-Zwaenge (siehe Seitenleiste unten):
        // die Leiste ist so hoch wie ihr Inhalt, das Fenster bleibt frei.
        freigabeLeiste.sizingOptions = [.intrinsicContentSize]
        kopf = Kopf(fenster: self, kern: kern)
        tabStreifen = NSHostingView(rootView: TabStreifen(marken: [], gewaehlt: 0, waehlen: { [weak self] i in self?.kopf.tabWaehlen(i) }))
        tabStreifen.sizingOptions = [.intrinsicContentSize]
        editorLeiste = NSHostingView(rootView: EditorTabLeiste(zustand: editorZustand))
        editorLeiste.sizingOptions = [.intrinsicContentSize]
        editorZustand.fragen = { [weak self] titel, text, knopf in
            await self?.rueckfrage(titel, text, knopf: knopf) ?? false
        }
        editorZustand.beiWechsel = { [weak self] in self?.editorNachfuehren() }
        terminal.aufZoom = { [weak self] p in self?.kopf.kachelZoomen(p) }
        terminal.aufZurueck = { [weak self] in self?.kopf.kachelnZurueck() }
        terminal.kopfZuPane = { [weak self] p in self?.kopfZuPane(p) ?? KachelKopfDaten() }
        // Die Lage geht zuerst an die Buehne (TerminalBereich hat den Haken
        // gesetzt), dann an den Kopf, der seine Wahl daran prueft.
        let anBuehne = kern.aufLage
        kern.aufLage = { [weak self] l in
            anBuehne?(l)
            self?.kopf.lageAngekommen(l)
        }
        fensterEinrichten()
        symbolleisteEinrichten()
        beobachten()
        kern.aufUmbenennen = { [weak self] u in self?.umbenennenFragen(u) }
        // Der Waechter des Kerns ueber die offenen Dateien (`awb:datei-geaendert`,
        // `name: editor`): das Blatt macht daraus den Hinweis am Tab.
        kern.aufDateiGeaendert = { [weak self] name, pfad in
            guard name == "editor", !pfad.isEmpty else { return }
            self?.editorZustand.aufPlatteGeaendert(pfad)
        }
        // Die drei Blaetter (3.5/3.6): die Antworten des Kerns an ihren Zustand,
        // der Pfad-Klick an den einen Weg, der ihn oeffnet.
        // HELL ODER DUNKEL FOLGT DER EINSTELLUNG (08.09.2026). Bis dahin folgte
        // die Mac-Fassung immer dem System, waehrend die Electron-Fassung die
        // Einstellung „Aussehen, Hell oder dunkel" umsetzt -- wer dort „dunkel"
        // waehlte, bekam zwei verschiedene Werkbaenke. Dazu kam, dass der Kern
        // die Zustandsfarben gegen den Grund SEINES Erscheinungsbildes prueft:
        // ohne diesen Schritt haette der Mac-Punkt die Farbe fuer den anderen
        // Grund getragen. 'system' heisst: das Programm entscheidet nichts und
        // laesst dem Betriebssystem den Vortritt.
        kern.aufThema = { [weak self] t in self?.erscheinungAnwenden(t) }
        kern.aufOrdner = { [weak self] o in self?.ordnerZustand.angekommen(o) }
        kern.aufSuche = { [weak self] s in self?.ordnerZustand.sucheAngekommen(s) }
        kern.aufAktivitaet = { [weak self] a in self?.aktivitaetZustand.angekommen(a) }
        kern.aufErgebnis = { [weak self] e in self?.ergebnisGemeldet(e) }
        ordnerZustand.dateiOeffnen = { [weak self] p in
            Task { await self?.pfadOeffner.oeffnen(p) }
        }
        pfadOeffner.ordnerZeigen = { [weak self] p in
            self?.blattZeigen(.ordner)
            self?.ordnerZustand.zeigen(p)
        }
        pfadOeffner.melden = { [weak self] text in self?.editorZustand.melden(text) }
        // Der Kern taktet die Welten nur schnell, solange sie stehen (Befund M4);
        // nach einem neuen Kern erfaehrt er es beim Handschlag.
        kern.aufHallo = { [weak self] in
            self?.aufgabenSichtbarMelden()
        }
        // Baum oder Liste wird gemerkt wie jede andere Lage des Fensters; der
        // Lesestand liegt in der Welt selbst (Auftrag Nr. 2).
        if let d = Merker.text(datei: WeltenZustand.merkerDatei, schluessel: WeltenZustand.merkerSchluessel, optionen)
            .flatMap(WeltenZustand.Darstellung.init(rawValue:)) { weltenZustand.darstellung = d }
        weltenZustand.darstellungMerken = { [optionen] wert in
            Merker.setzen(wert, datei: WeltenZustand.merkerDatei, schluessel: WeltenZustand.merkerSchluessel, optionen)
        }
        // Ein Pfad im Gespraech ist angeklickt worden: derselbe Weg wie aus dem
        // Ordner-Blatt und aus dem Terminal.
        chat.aufPfad = { [weak self] t in
            Task { await self?.pfadOeffner.oeffnen(t.zeile > 0 ? "\(t.abs):\(t.zeile):\(max(1, t.spalte))" : t.abs, geprueft: true) }
        }
        // Und ⌘-Klick im Terminal (Auftrag 3.6, TerminalBereich.swift).
        terminal.aufPfadKlick = { [weak self] pane, wortlaut in
            Task { await self?.pfadOeffner.oeffnen(wortlaut, pane: pane) }
        }
    }

    private func fensterEinrichten() {
        fenster.title = "Werkbank"
        fenster.subtitle = ""
        fenster.toolbarStyle = .unified
        fenster.titlebarSeparatorStyle = .automatic
        fenster.minSize = NSSize(width: 640, height: 400)
        fenster.delegate = self
        fenster.isReleasedWhenClosed = false
        fenster.tabbingMode = .disallowed
        // Vollbild ueber den gruenen Knopf und Darstellung, Vollbild (⌃⌘F).
        fenster.collectionBehavior.insert(.fullScreenPrimary)

        // Seitenleiste: SwiftUI-Liste in einem Sidebar-Item.
        let seite = NSHostingController(rootView: Seitenleiste(kern: kern, handlungen: self, oberflaeche: oberflaeche, fuss: self, kopflos: optionen.kopflos))
        // KEINE Groessenzwaenge aus SwiftUI (gemessen 06.09.): mit der Vorgabe
        // legt der Hosting-Controller Min-/Max-Zwaenge aus der idealen Groesse der
        // Liste an, und das Fenster schrumpfte auf 828x171 -- `setFrame` blieb
        // danach wirkungslos. Die Groesse gehoert dem Fenster, nicht der Liste.
        seite.sizingOptions = []
        // IM ZUSTAND AGENTS STEHT AN DIESER STELLE DIE LEISTE DER WELT (Auftrag
        // agentsui Nr. 6). Beide liegen in einem Traeger, der die Spalte fuellt;
        // der Umschalter blendet die eine aus und die andere ein. So bleiben
        // Breite, Material und Einklappen die der einen Seitenleiste.
        let seitenTraeger = NSViewController()
        seitenTraeger.view = NSView()
        seitenTraeger.addChild(seite)
        weltenLeiste = NSHostingView(rootView: WeltenLeisteSpalte(kern: kern, zustand: weltenZustand))
        weltenLeiste.sizingOptions = []
        weltenLeiste.isHidden = true
        seitenleisteHost = seite.view
        for v in [seite.view, weltenLeiste as NSView] { Self.fuellen(v, in: seitenTraeger.view) }
        let seitenItem = NSSplitViewItem(sidebarWithViewController: seitenTraeger)
        seitenItem.minimumThickness = 200
        seitenItem.maximumThickness = 420
        seitenItem.canCollapse = true
        splitController.addSplitViewItem(seitenItem)
        self.seitenItem = seitenItem

        // Inhalt: oben die Freigabeleiste (nur, solange etwas offen ist), darunter
        // die Buehne mit der Terminal-Pane und dem Leerzustand, solange nichts
        // gewaehlt ist. Ein senkrechter Stapel, damit eine versteckte Leiste
        // keinen Platz laesst (NSStackView nimmt versteckte Views aus dem Layout).
        let inhalt = NSViewController()
        let traeger = NSView()
        inhalt.view = traeger
        let stapel = NSStackView()
        stapel.orientation = .vertical
        stapel.alignment = .width
        stapel.spacing = 0
        stapel.distribution = .fill
        stapel.translatesAutoresizingMaskIntoConstraints = false
        traeger.addSubview(stapel)
        NSLayoutConstraint.activate([
            stapel.leadingAnchor.constraint(equalTo: traeger.leadingAnchor),
            stapel.trailingAnchor.constraint(equalTo: traeger.trailingAnchor),
            stapel.topAnchor.constraint(equalTo: traeger.safeAreaLayoutGuide.topAnchor),
            stapel.bottomAnchor.constraint(equalTo: traeger.bottomAnchor),
        ])
        freigabeLeiste.isHidden = true
        freigabeLeiste.setContentHuggingPriority(.required, for: .vertical)
        freigabeLeiste.setContentCompressionResistancePriority(.required, for: .vertical)
        stapel.addArrangedSubview(freigabeLeiste)
        // Der Tab-Streifen: wie die Leiste nur so hoch wie sein Inhalt, und aus
        // dem Layout, solange er nichts zu schalten hat.
        tabStreifen.isHidden = true
        tabStreifen.setContentHuggingPriority(.required, for: .vertical)
        tabStreifen.setContentCompressionResistancePriority(.required, for: .vertical)
        stapel.addArrangedSubview(tabStreifen)
        // Die Tab-Zeile des Editors steht wie die beiden Leisten ueber ihm im
        // Stapel und bleibt auch eingeklappt stehen (editor-view.ts: `#ed-tabs`
        // liegt in `#mitte`, nicht in der Buehne).
        editorLeiste.isHidden = true
        editorLeiste.setContentHuggingPriority(.required, for: .vertical)
        editorLeiste.setContentCompressionResistancePriority(.required, for: .vertical)
        stapel.addArrangedSubview(editorLeiste)
        let buehne = NSView()
        buehne.setContentHuggingPriority(.defaultLow, for: .vertical)
        stapel.addArrangedSubview(buehne)
        terminal.translatesAutoresizingMaskIntoConstraints = false
        leerHinweis.translatesAutoresizingMaskIntoConstraints = false
        chatBuehne.translatesAutoresizingMaskIntoConstraints = false
        // Die Chat-Buehne liegt als eigene Ansicht AN DER STELLE der Kacheln
        // (Auftrag 3.2; Electron: `#chatbuehne` ueber dem Gitter). Welche der
        // drei Ansichten steht, entscheidet `leerzustandNachfuehren` aus dem
        // Modell: Chat (`chatGezeigt`), Kacheln (Sitzung gewaehlt), Leerzustand.
        chatBuehne.isHidden = true
        // Die Mitte der Welten liegt als vierte Ansicht an derselben Stelle und
        // schlaegt die drei anderen, solange der Umschalter auf Agents steht
        // (`leerzustandNachfuehren`).
        weltenMitte.translatesAutoresizingMaskIntoConstraints = false
        weltenMitte.isHidden = true
        buehne.addSubview(terminal)
        buehne.addSubview(chatBuehne)
        buehne.addSubview(weltenMitte)
        buehne.addSubview(leerHinweis)
        // DER EINZUG LINKS, WENN DIE SEITENLEISTE EINGEKLAPPT IST (08.09.2026,
        // Befund des Nutzers: „dann ist das Terminal vom Agenten zu weit links
        // ohne Abstand, da muss mehr Abstand hin"). Alle vier Ansichten der
        // Buehne haengen an derselben Zahl -- was fuer die Kacheln gilt, gilt
        // auch fuer Gespraech, Welten und Leerzustand; sie stehen an
        // derselben Stelle. Gefuehrt wird sie in `buehnenEinzugNachfuehren`.
        let einzuege = [
            weltenMitte.leadingAnchor.constraint(equalTo: buehne.leadingAnchor),
            terminal.leadingAnchor.constraint(equalTo: buehne.leadingAnchor),
            chatBuehne.leadingAnchor.constraint(equalTo: buehne.leadingAnchor),
            leerHinweis.leadingAnchor.constraint(equalTo: buehne.leadingAnchor),
        ]
        buehnenEinzuege = einzuege
        NSLayoutConstraint.activate(einzuege + [
            weltenMitte.trailingAnchor.constraint(equalTo: buehne.trailingAnchor),
            weltenMitte.topAnchor.constraint(equalTo: buehne.topAnchor),
            weltenMitte.bottomAnchor.constraint(equalTo: buehne.bottomAnchor),
            terminal.trailingAnchor.constraint(equalTo: buehne.trailingAnchor),
            terminal.topAnchor.constraint(equalTo: buehne.topAnchor),
            terminal.bottomAnchor.constraint(equalTo: buehne.bottomAnchor),
            chatBuehne.trailingAnchor.constraint(equalTo: buehne.trailingAnchor),
            chatBuehne.topAnchor.constraint(equalTo: buehne.topAnchor),
            chatBuehne.bottomAnchor.constraint(equalTo: buehne.bottomAnchor),
            leerHinweis.trailingAnchor.constraint(equalTo: buehne.trailingAnchor),
            leerHinweis.topAnchor.constraint(equalTo: buehne.topAnchor),
            leerHinweis.bottomAnchor.constraint(equalTo: buehne.bottomAnchor),
        ])
        buehneView = buehne
        // JEDER STREIFEN SO BREIT WIE DER STAPEL (gemessen am Belegbild, 06.09.):
        // ein NSHostingView mit `sizingOptions = [.intrinsicContentSize]` bringt
        // eine Eigenbreite mit, und die Ausrichtung `.width` des NSStackView
        // ueberstimmt sie nicht -- die Editor-Tabzeile stand 707 von 860 Punkten
        // breit am rechten Rand, und ihre Breite wanderte mit der Laenge der
        // Notiz darin. Eine Breite gleich der des Stapels bindet alle drei.
        for streifen in [freigabeLeiste, tabStreifen, editorLeiste] as [NSView] {
            streifen.widthAnchor.constraint(equalTo: stapel.widthAnchor).isActive = true
        }
        let inhaltItem = NSSplitViewItem(viewController: inhalt)
        inhaltItem.minimumThickness = 400
        splitController.addSplitViewItem(inhaltItem)

        // Der Inspektor rechts (Auftrag 2.4, um die Blaetter aus 3.5/3.6
        // erweitert): eingeklappt, bis das Abzeichen, die Leiste oder das Menue
        // ihn oeffnen. Welches der vier Blaetter er zeigt, sagt `oberflaeche.blatt`.
        let blatt = NSHostingController(rootView: InspektorBlatt(
            kern: kern, oberflaeche: oberflaeche, freigaben: freigabenZustand,
            ordner: ordnerZustand, aktivitaet: aktivitaetZustand, protokolle: protokolleZustand,
            handlungen: self))
        blatt.sizingOptions = []
        // Derselbe Traeger wie links: im Zustand Agents steht hier der Inspektor der Welt.
        let inspektorTraeger = NSViewController()
        inspektorTraeger.view = NSView()
        inspektorTraeger.addChild(blatt)
        weltenInspektor = NSHostingView(rootView: WeltenInspektorSpalte(kern: kern, zustand: weltenZustand))
        weltenInspektor.sizingOptions = []
        weltenInspektor.isHidden = true
        inspektorHost = blatt.view
        for v in [blatt.view, weltenInspektor as NSView] { Self.fuellen(v, in: inspektorTraeger.view) }
        let inspektor = NSSplitViewItem(inspectorWithViewController: inspektorTraeger)
        inspektor.minimumThickness = 300
        inspektor.maximumThickness = 560
        inspektor.canCollapse = true
        inspektor.isCollapsed = true
        splitController.addSplitViewItem(inspektor)
        inspektorItem = inspektor

        fenster.contentViewController = splitController
        fenster.setContentSize(NSSize(width: 1100, height: 700))
        // Die Fensterlage ueber den Neustart: erst die Vorgabegroesse, dann der
        // gemerkte Rahmen; nur ohne gemerkten Rahmen wird zentriert -- vorher
        // ueberschrieb `center()` den eben hergestellten Rahmen.
        if !lageHerstellen() { fenster.center() }
        lageBereit = true
        leerzustandNachfuehren()
        // Der Teiler: was der Mensch zieht, geht an den Kern (Auftrag 2.8).
        // DER ZUG AN DER SEITENLEISTE (08.09.2026): `toggleSidebar` kommt aus
        // dem Menue, aus der Symbolleiste und von der Tastatur -- die Unterklasse
        // faengt alle drei Wege an einer Stelle.
        splitController.animiert = !optionen.kopflos
        splitController.aufUmschalten = { [weak self] in
            self?.terminal.flaecheSpaeterMelden(ruhe: TerminalBereich.bewegungsruhe)
        }
        // Und was der Mantel messen will, wird vorher zu Ende gelegt.
        terminal.vorDemMelden = { [weak self] in self?.aufteilungNachziehen() }
        teilerBeobachter = NotificationCenter.default.addObserver(
            forName: NSSplitView.didResizeSubviewsNotification, object: splitController.splitView, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.teilerBewegt()
                self?.buehnenEinzugNachfuehren()
                // JEDER SCHRITT DER BEWEGUNG SETZT DIE UHR NEU (08.09.2026).
                // Das Ein- und Ausklappen ist animiert; die Groesse geht erst
                // an den Kern, wenn die Leiste steht (TerminalBereich,
                // `meldungAnstossen`) -- einmal, nicht je Zwischenwert.
                self?.terminal.flaecheSpaeterMelden()
            }
        }
    }

    // MARK: Fensterlage ueber den Neustart (Auftrag 2.8)

    /// Wo die Lage liegt, entscheidet `Merker.swift`: im Betrieb die
    /// Voreinstellungen unter demselben Schluessel, den `setFrameAutosaveName`
    /// benutzt (NSWindow Frame <Name>), mit demselben Rahmen-Text
    /// (`frameDescriptor`); in einer PRUEFUNG eine Datei im Laufverzeichnis.
    /// Gemessen 06.09. (test-mac-fenster): mit `setFrameAutosaveName` schrieb
    /// die kopflose Suite in die Voreinstellungen des MENSCHEN
    /// (~/Library/Preferences), obwohl HOME auf ein Wegwerfverzeichnis zeigte --
    /// cfprefsd folgt HOME nicht. Seit dem 08.09. gilt das nicht mehr nur
    /// kopflos, sondern in jeder Pruefung (auch `--ohne-fokus`).
    private static let lageSchluessel = "NSWindow Frame \(rahmenName)"

    private func lageHerstellen() -> Bool {
        guard let t = Merker.text(datei: Merker.fensterlage, schluessel: Self.lageSchluessel, optionen) else { return false }
        fenster.setFrame(from: t)
        return true
    }

    private func lageMerken() {
        guard lageBereit else { return }
        Merker.setzen(fenster.frameDescriptor, datei: Merker.fensterlage,
                      schluessel: Self.lageSchluessel, optionen)
    }

    // MARK: Seitenleisten- und Inspektorbreite (Auftrag 2.8)

    /// Die Breite der Seitenleiste, wie sie steht (0: eingeklappt).
    var seitenleisteBreite: Int {
        guard seitenleisteSichtbar else { return 0 }
        return Int(seitenItem.viewController.view.frame.width.rounded())
    }

    /// Die Breite des Inspektors, wie er steht (0: eingeklappt).
    var inspektorBreite: Int {
        guard let item = inspektorItem, !item.isCollapsed else { return 0 }
        return Int(item.viewController.view.frame.width.rounded())
    }

    /// Ob das Fenster im Vollbild steht.
    var vollbild: Bool { fenster.styleMask.contains(.fullScreen) }

    /// Beim ersten Modell des Kerns die gemerkten Breiten herstellen -- einmal.
    private func breitenHerstellen() {
        guard !breitenAngewandt, kern.verbunden, (kern.ereignisse["awb:model"] ?? 0) > 0 else { return }
        breitenAngewandt = true
        gemeldeteBreiten = (kern.modell.ui.sidebarWidth, kern.modell.ui.blattBreite)
        // KOMMEN DIE BREITEN DES KERNS ERST, WENN AGENTS SCHON VORN LIEGT (gesehen 14.09.,
        // agentsux Nr. 1: im Belegbild stand die Leiste der Welt wieder bei 232 pt, abgeschnitten),
        // gehoert die gemeldete Breite der Code-Ansicht; die Leiste der Welt behaelt ihre Mindestbreite.
        if oberflaeche.modus == .agents {
            codeSeitenBreite = kern.modell.ui.sidebarWidth
            teilerSetzen(seite: max(kern.modell.ui.sidebarWidth, Self.weltenLeisteBreite), blatt: kern.modell.ui.blattBreite)
            return
        }
        teilerSetzen(seite: kern.modell.ui.sidebarWidth, blatt: kern.modell.ui.blattBreite)
    }

    /// Die Teiler stellen, beschnitten auf die Grenzen der Spalten. Mit
    /// `melden` geht die neue Breite wie ein Zug des Menschen an den Kern
    /// (der Steuerbefehl `teiler`); ohne bleibt sie ein Herstellen.
    func teilerSetzen(seite: Int? = nil, blatt: Int? = nil, melden: Bool = false) {
        stelleBreitenEin = !melden
        defer { stelleBreitenEin = false }
        let sv = splitController.splitView
        // Die Position eines Teilers und die Breite der Spalte dahinter sind
        // nicht dieselbe Zahl (gemessen 06.09.: Position 300 gab eine
        // Seitenleiste von 292, der Inspektor stand 1 pt breiter als gesetzt).
        // Deshalb: setzen, nachmessen, um die Abweichung nachsetzen -- die
        // Breite der SPALTE ist, was gemeldet und hergestellt wird.
        if let s = seite, seitenleisteSichtbar {
            let w = min(max(CGFloat(s), seitenItem.minimumThickness), seitenItem.maximumThickness)
            sv.setPosition(w, ofDividerAt: 0)
            sv.layoutSubtreeIfNeeded()
            let ist = seitenItem.viewController.view.frame.width
            if ist != w { sv.setPosition(w + (w - ist), ofDividerAt: 0) }
        }
        if let b = blatt, let item = inspektorItem, !item.isCollapsed {
            let w = min(max(CGFloat(b), item.minimumThickness), item.maximumThickness)
            let position = { sv.bounds.width - w - sv.dividerThickness }
            sv.setPosition(position(), ofDividerAt: 1)
            sv.layoutSubtreeIfNeeded()
            let ist = item.viewController.view.frame.width
            if ist != w { sv.setPosition(position() + (ist - w), ofDividerAt: 1) }
        }
        sv.layoutSubtreeIfNeeded()
        if melden { teilerBewegt(sofort: true) }
    }

    /// Der Teiler hat sich bewegt: eine Breite, die vom Stand des Kerns
    /// abweicht, geht nach 300 ms Ruhe an ihn (`sidebar-width`, `blatt-breite`)
    /// -- nicht bei jedem Bildpunkt des Ziehens.
    private func teilerBewegt(sofort: Bool = false) {
        // Im Zustand Agents stehen andere Ansichten in den Spalten: ihre Breite aendert die gemerkte nicht.
        guard breitenAngewandt, !stelleBreitenEin, oberflaeche.modus == .code else { return }
        let s = seitenleisteBreite
        let b = inspektorBreite
        let seiteNeu = s > 0 && s != gemeldeteBreiten.seite
        let blattNeu = b > 0 && b != gemeldeteBreiten.blatt
        guard seiteNeu || blattNeu else { return }
        breitenTimer?.invalidate()
        if sofort { breitenMelden(); return }
        breitenTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.breitenMelden() }
        }
    }

    private func breitenMelden() {
        let s = seitenleisteBreite
        let b = inspektorBreite
        if s > 0, s != gemeldeteBreiten.seite { gemeldeteBreiten.seite = s; kern.bedienung("sidebar-width", s) }
        if b > 0, b != gemeldeteBreiten.blatt { gemeldeteBreiten.blatt = b; kern.bedienung("blatt-breite", b) }
    }

    /// Eine Ansicht fuellt ihren Traeger ganz.
    private static func fuellen(_ v: NSView, in traeger: NSView) {
        v.translatesAutoresizingMaskIntoConstraints = false
        traeger.addSubview(v)
        NSLayoutConstraint.activate([
            v.leadingAnchor.constraint(equalTo: traeger.leadingAnchor),
            v.trailingAnchor.constraint(equalTo: traeger.trailingAnchor),
            v.topAnchor.constraint(equalTo: traeger.topAnchor),
            v.bottomAnchor.constraint(equalTo: traeger.bottomAnchor),
        ])
    }

    private func symbolleisteEinrichten() {
        let leiste = NSToolbar(identifier: "Werkbank.Symbolleiste")
        leiste.delegate = self
        leiste.displayMode = .iconOnly
        leiste.allowsUserCustomization = false
        fenster.toolbar = leiste
    }

    private func beobachten() {
        // Aenderungen am Modell nachziehen: Auswahl, Titel, Leerzustand, Terminal.
        beobachtung = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.nachziehen() }
        }
    }

    /// DER ABSTAND LINKS AN DER BUEHNE (08.09.2026).
    ///
    /// Steht die Seitenleiste, laesst der Teiler zwischen ihr und der Buehne
    /// eine Fuge; die erste Kachel faengt dahinter an. Ist die Leiste
    /// eingeklappt, faengt sie am Fensterrand an -- und genau das war des Nutzers
    /// Befund. Die Buehne bekommt deshalb eingeklappt denselben Abstand, den
    /// bei sichtbarer Leiste der Teiler laesst.
    ///
    /// GEMESSEN, NICHT GERATEN (08.09.2026, an der laufenden App): zwischen
    /// Seitenleiste und Buehne steht gar keine Fuge -- die Buehne faengt genau
    /// dort an, wo die Leiste aufhoert (Leiste bei x = 8, 300 breit, Buehne bei
    /// x = 308). Der Abstand, den das Fenster wirklich haelt, ist ein anderer:
    /// die SEITENLEISTE selbst steht acht Punkte vom Fensterrand entfernt --
    /// so setzt macOS sie ein. Acht Punkte sind damit der Abstand, den der
    /// jeweils linke Nachbar des Fensterrandes hier hat, und den bekommt die
    /// Buehne, wenn sie selbst dieser Nachbar wird.
    static let buehnenEinzug: CGFloat = 8

    /// Den Einzug an den Stand der Seitenleiste anpassen. Billig genug, um im
    /// Takt zu laufen: vier Zahlen vergleichen, und nur bei einer Aenderung
    /// wird ueberhaupt neu gelegt.
    private func buehnenEinzugNachfuehren() {
        let soll = seitenleisteSichtbar ? 0 : Self.buehnenEinzug
        guard let erste = buehnenEinzuege.first, erste.constant != soll else { return }
        for c in buehnenEinzuege { c.constant = soll }
        buehneView?.layoutSubtreeIfNeeded()
    }

    /// DIE AUFTEILUNG ZU ENDE LEGEN (08.09.2026). Nach `toggleSidebar` steht
    /// `isCollapsed` sofort um; die Frames der Spalten folgen aber erst, wenn
    /// AppKit das naechste Mal von sich aus legt -- und das kann ausbleiben,
    /// bis der Mensch das Fenster zieht (Befund des Nutzers vom 08.09.). Gerufen
    /// wird das hier am Ende der Bewegung, nicht bei jedem Zwischenwert.
    private func aufteilungNachziehen() {
        splitController.view.needsLayout = true
        splitController.view.layoutSubtreeIfNeeded()
        buehnenEinzugNachfuehren()
    }

    /// Der gesetzte Einzug links an der Buehne -- fuer `awbmac-ctl ui`.
    var buehnenEinzugJetzt: CGFloat { buehnenEinzuege.first?.constant ?? 0 }

    /// Wo die erste Kachel im FENSTER steht (x, von links). Das ist die Zahl,
    /// an der sich Befund des Nutzers nachmessen laesst: mit und ohne
    /// Seitenleiste soll sie denselben Abstand vom Rand der jeweils linken
    /// Nachbarin haben.
    var buehnenXImFenster: Int {
        guard let b = buehneView else { return 0 }
        return Int(b.convert(b.bounds, to: nil).minX.rounded()) + Int(buehnenEinzugJetzt.rounded())
    }

    var buehnenXRoh: Int {
        guard let b = buehneView else { return 0 }
        return Int(b.convert(b.bounds, to: nil).minX.rounded())
    }

    var seitenleisteXImFenster: [Int] {
        guard let v = seitenItem?.viewController.view else { return [] }
        let r = v.convert(v.bounds, to: nil)
        return [Int(r.minX.rounded()), Int(r.width.rounded())]
    }

    private func nachziehen() {
        breitenHerstellen()
        buehnenEinzugNachfuehren()
        weltenInspektorNachfuehren()
        let s = kern.gewaehlteSitzung
        let kennung = s?.id ?? ""
        if kennung != letzteSitzung {
            letzteSitzung = kennung
            terminal.sitzungGewechselt(s)
            if let w = wunschPane, w.sitzung == kennung {
                // Der Klick auf einen Worker einer ANDEREN Sitzung: erst waehlen
                // (der Kern haengt sich an), dann seinen Pane zeigen.
                wunschPane = nil
                wunschOffen = (w.sitzung, w.pane, Date().addingTimeInterval(3))
                kopf.sitzungGewechselt(nil)
                kopf.workerPaneZeigen(w.pane)
            } else {
                kopf.sitzungGewechselt(s)
            }
        }
        wunschNachfordern(s)
        chatNachziehen()
        editorZustand.nachModell()
        editorNachfuehren()
        kopf.nachziehen()
        leerzustandNachfuehren()
        freigabenNachfuehren()
        blaetterNachfuehren()
        hinweisKlickNachfuehren()
        streifenNachfuehren()
        terminal.kopfzeilenNachziehen()
    }

    /// Solange der gewuenschte Worker-Pane nicht auf der Buehne ist, aber schon
    /// eine Lage DIESER Sitzung steht, den Pane noch einmal anfordern (Takt 0,25 s).
    private func wunschNachfordern(_ s: SitzungsEintrag?) {
        guard let w = wunschOffen else { return }
        guard let s, s.id == w.sitzung, Date() < w.bis else { wunschOffen = nil; return }
        guard let l = kern.lage else { return }
        let gezeichnet = Set(l.panes.map(\.paneId) + [l.aktiv]).filter { !$0.isEmpty }
        if gezeichnet.contains(w.pane) { wunschOffen = nil; return }
        let eigene = s.workerPanesMitSubagenten.union(s.orchestratorPane.isEmpty ? [] : [s.orchestratorPane])
        guard !gezeichnet.isDisjoint(with: eigene) else { return }   // noch die alte Sitzung
        kern.paneZeigen(w.pane)
    }

    // MARK: Statusfuss (Auftrag 2.5; die Views in Statusfuss.swift und Maschinenkarte.swift)

    func karteUmschalten(_ maschine: String) {
        oberflaeche.offeneKarte = oberflaeche.offeneKarte == maschine ? "" : maschine
    }

    func maschineLaden(_ maschine: String, _ laden: Bool) {
        kern.maschineLaden(maschine, laden)
    }

    func hinweisWeg() {
        kern.meldungWeg()
    }

    func einstellungenZeigen() {
        einstellungenZeigen(nil)
    }

    /// Ein Hinweis, der laenger als 4 s steht (der Absturzhinweis: 30 s), geht
    /// beim naechsten Klick irgendwo im Fenster -- wie in Electron
    /// (renderer.ts `notiz`). Kurze Hinweise laufen einfach ab.
    private func hinweisKlickNachfuehren() {
        let lang = !kern.meldung.isEmpty && kern.meldungBis.timeIntervalSinceNow > 4
        if lang, klickBeobachter == nil {
            klickBeobachter = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] e in
                Task { @MainActor in self?.hinweisWeg() }
                return e
            }
        } else if !lang, let b = klickBeobachter {
            NSEvent.removeMonitor(b)
            klickBeobachter = nil
        }
    }

    // MARK: Tab-Streifen und Kachelkoepfe

    /// Der Streifen folgt der Buehne und der Kapazitaet: ab zwei Tabs, und nur
    /// mit Worker-Kacheln auf der Buehne (renderer.ts `zeichneStreifen`).
    private func streifenNachfuehren() {
        let marken = kopf.tabMarken()
        let da = kopf.streifenDa
        let tab = kern.gewaehlteSitzung.map { kopf.gewaehlterTab($0) } ?? 0
        if marken != letzteMarken || tab != letzterTab {
            letzteMarken = marken
            letzterTab = tab
            tabStreifen.rootView = TabStreifen(marken: marken, gewaehlt: tab, waehlen: { [weak self] i in self?.kopf.tabWaehlen(i) })
        }
        if tabStreifen.isHidden == da { tabStreifen.isHidden = !da }
    }

    /// Die Hoehe des Streifens, wie er steht (0, wenn er nicht da ist).
    var streifenHoehe: CGFloat {
        // Gemeldet wird, was steht -- und wenn der Streifen gerade erst faellig
        // ist (naechster Takt), schon seine Eigenhoehe, damit eine Auskunft
        // zwischen zwei Takten nicht „0" sagt.
        if tabStreifen.isHidden { return kopf.streifenDa ? tabStreifen.intrinsicContentSize.height : 0 }
        return max(tabStreifen.frame.height, tabStreifen.intrinsicContentSize.height)
    }

    /// Was in der Kopfzeile eines Panes steht: der Worker, der Subagent, der
    /// Orchestrator -- sonst die rohe Kennung (renderer.ts `kopfZuPane`).
    ///
    /// NUR, SOLANGE DIE LAGE ZUR GEWAEHLTEN SITZUNG GEHOERT (08.09.2026). Eine
    /// Pane-Kennung gilt je tmux-Server, und jede Maschine hat einen eigenen:
    /// zwischen `select` und der ersten Lage der neuen Sitzung stehen noch die
    /// Kacheln der ALTEN auf der Buehne, und trifft eine ihrer Kennungen
    /// zufaellig einen Worker der neuen (`%2` gibt es hier wie drueben), traegt
    /// die Kachel fuer einen Takt einen fremden Namen. `kopf.buehne` ist genau
    /// die Frage „gehoert die gezeichnete Lage dieser Sitzung?"; steht sie auf
    /// nil, bleibt die Kopfzeile lieber leer.
    func kopfZuPane(_ pane: String) -> KachelKopfDaten {
        guard let s = kern.gewaehlteSitzung, kopf.buehne != nil else { return KachelKopfDaten() }
        if let w = s.workers.first(where: { $0.paneId == pane }) {
            return KachelKopfDaten(name: w.name, zustand: w.state, modell: w.model, tokens: w.tokensKurz)
        }
        for w in s.workers {
            if let sub = w.subagents.first(where: { $0.paneId == pane }) {
                return KachelKopfDaten(name: sub.anzeigename, zustand: "running", modell: sub.type, tokens: "")
            }
        }
        if let os = s.orphanSubagents.first(where: { $0.paneId == pane }) {
            return KachelKopfDaten(name: os.anzeigename, zustand: "running", modell: os.type, tokens: "")
        }
        if pane == s.orchestratorPane {
            return KachelKopfDaten(name: "Orchestrator", zustand: s.state == "running" ? "running" : (s.state == "attention" ? "blocked" : ""), modell: s.model, tokens: "")
        }
        return KachelKopfDaten()
    }

    @objc func kachelZoomUmschalten(_ sender: Any?) { kopf.kachelZoomUmschalten() }

    /// Die Tastatur von Kachel zu Kachel (⌘] / ⌘[), in Lage-Reihenfolge, mit Umlauf.
    @objc func naechsteKachel(_ sender: Any?) { kachelWechseln(1) }
    @objc func vorigeKachel(_ sender: Any?) { kachelWechseln(-1) }

    private func kachelWechseln(_ schritt: Int) {
        let panes = terminal.gezeigtePanes
        guard panes.count > 1 else { return }
        let i = panes.firstIndex(of: terminal.gezeigterPane) ?? 0
        let n = panes.count
        terminal.fokusSetzen(panes[((i + schritt) % n + n) % n], tastatur: true)
    }

    /// Von Tab zu Tab (⌘⇧] / ⌘⇧[), mit Umlauf -- derselbe Weg wie der Streifen.
    @objc func naechsterTab(_ sender: Any?) { tabWechseln(1) }
    @objc func vorigerTab(_ sender: Any?) { tabWechseln(-1) }

    private func tabWechseln(_ schritt: Int) {
        guard let s = kern.gewaehlteSitzung else { return }
        let n = s.tabs(perTab: kern.modell.capacity.perTab)
        guard n > 1 else { return }
        kopf.tabWaehlen(((kopf.gewaehlterTab(s) + schritt) % n + n) % n)
    }

    /// Den Hinweis im Fuss ohne Maus wegraeumen.
    @objc func hinweisAusblenden(_ sender: Any?) { hinweisWeg() }

    /// Eine Maschinenkarte aus dem Menue: ihr Feld auf oder zu.
    @objc func maschineGewaehlt(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        karteUmschalten(name)
    }

    /// „Sitzungen laden“ einer fernen Maschine aus dem Menue umlegen.
    @objc func maschineLadenUmschalten(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String,
              let m = kern.modell.maschinenKarten.first(where: { $0.name == name }), !m.eigen else { return }
        maschineLaden(name, m.pausiert)
    }

    /// Das Untermenue „Maschinen“ entsteht beim Aufklappen aus dem Modell
    /// (NSMenuDelegate): je Maschine ein Punkt fuer ihr Feld und, wenn sie
    /// fern ist, einer fuer „Sitzungen laden“ -- jede Handlung des Fusses
    /// auch ohne Maus (abnahme.md, Merkmal 11).
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu.title == "Maschinen" else { return }
        menu.removeAllItems()
        let karten = kern.modell.maschinenKarten
        if karten.isEmpty {
            let leer = NSMenuItem(title: "Keine Maschine gemeldet", action: nil, keyEquivalent: "")
            leer.isEnabled = false
            menu.addItem(leer)
            return
        }
        for k in karten {
            let feld = NSMenuItem(title: "\(k.name): Einzelheiten", action: #selector(maschineGewaehlt(_:)), keyEquivalent: "")
            feld.representedObject = k.name
            feld.target = self
            feld.state = oberflaeche.offeneKarte == k.name ? .on : .off
            menu.addItem(feld)
            if !k.eigen {
                let laden = NSMenuItem(title: "\(k.name): Sitzungen laden", action: #selector(maschineLadenUmschalten(_:)), keyEquivalent: "")
                laden.representedObject = k.name
                laden.target = self
                laden.state = k.pausiert ? .off : .on
                menu.addItem(laden)
            }
        }
    }

    // MARK: Freigaben (Leiste, Abzeichen, Blatt)

    /// Leiste und Abzeichen folgen der Ablage des Kerns: die Leiste steht nur,
    /// solange etwas offen ist; das Abzeichen zaehlt, und bei null traegt es
    /// KEINEN Ring in der Wartefarbe (Lehre aus `pruefer`, 04.09.).
    private func freigabenNachfuehren() {
        let offene = kern.freigaben.offene.count
        guard offene != letzteOffene else { return }
        letzteOffene = offene
        freigabeLeiste.isHidden = offene == 0
        if offene == 0 { freigabenZustand.nr = 0 }
        if let item = freigabenItem {
            item.badge = offene > 0 ? NSItemBadge.count(offene) : nil
            // Das Hilfeschildchen nennt weiter alle vier Blaetter -- die Zahl
            // kommt davor, sie ist der Grund, jetzt hinzusehen.
            item.toolTip = offene > 0 ? "\(offene) offene Freigaben — \(Self.inspektorHilfe)" : Self.inspektorHilfe
        }
    }

    var offeneFreigaben: [OffeneFreigabe] { kern.freigaben.offene }

    /// Die Blaetter des Inspektors stehen nur im Zustand Code; im Zustand Agents zeigt er die Welt.
    var freigabenBlattSichtbar: Bool { oberflaeche.modus == .code && !(inspektorItem?.isCollapsed ?? true) }

    func entscheiden(_ f: OffeneFreigabe, annehmen: Bool, grund: String) {
        switch f.art {
        case .antrag:
            kern.antragEntscheiden(pfad: f.pfad, annehmen: annehmen, grund: grund)
        case .rueckfrage:
            // `echt`: ein Mensch hat im Fenster geklickt -- kopflos gibt es
            // keinen, und der Kern erteilt dann nicht (Ablehnen darf jeder).
            kern.musterEntscheiden(schluessel: f.schluessel, annehmen: annehmen, grund: grund, echt: !optionen.kopflos)
        }
        freigabenZustand.melden(annehmen ? "Freigabe für \(f.wer) erteilt." : "Freigabe für \(f.wer) abgelehnt.")
    }

    func freigabenBlattZeigen() {
        modusSetzen(.code)
        oberflaeche.blatt = .freigaben
        guard let item = inspektorItem, item.isCollapsed else { return }
        blattSetzen(item, offen: true)
    }

    /// Eines der vier Blaetter zeigen (Menue „Blätter", Steuerkanal, Pfad-Klick
    /// auf ein Verzeichnis): den Inspektor aufklappen, wenn er zu ist, und das
    /// Blatt waehlen. Ein zweiter Ruf auf dasselbe, schon sichtbare Blatt
    /// klappt ihn wieder ein -- wie jeder Reiter, der sein eigenes Kuerzel hat.
    func blattZeigen(_ wahl: BlattWahl) {
        guard let item = inspektorItem else { return }
        // Die Blaetter gehoeren zur Code-Buehne: wer eines verlangt, bekommt sie zurueck.
        let warAgents = oberflaeche.modus == .agents
        modusSetzen(.code)
        if !warAgents, !item.isCollapsed, oberflaeche.blatt == wahl {
            blattSetzen(item, offen: false)
            return
        }
        oberflaeche.blatt = wahl
        if item.isCollapsed { blattSetzen(item, offen: true) }
        blaetterNachfuehren()
    }

    @objc func blattFreigaben(_ sender: Any?) { blattZeigen(.freigaben) }
    @objc func blattOrdner(_ sender: Any?) { blattZeigen(.ordner) }
    @objc func blattAktivitaet(_ sender: Any?) { blattZeigen(.aktivitaet) }
    @objc func blattProtokolle(_ sender: Any?) { blattZeigen(.protokolle) }

    /// Was sichtbar ist, sieht nach; was nicht sichtbar ist, fragt nicht --
    /// die pruefbare Fassung der Hausregel, dass nichts auf Vorrat laeuft
    /// (`beobachtet` in `ui.ordner` bleibt bei geschlossenem Blatt null).
    private func blaetterNachfuehren() {
        let offen = freigabenBlattSichtbar
        ordnerZustand.sichtbarSetzen(offen && oberflaeche.blatt == .ordner)
        aktivitaetZustand.sichtbarSetzen(offen && oberflaeche.blatt == .aktivitaet)
        protokolleZustand.sichtbarSetzen(offen && oberflaeche.blatt == .protokolle)
        ordnerZustand.suchTakt()
        ordnerZustand.takt()
        aktivitaetZustand.takt()
        protokolleZustand.takt()
    }

    /// Eine Ergebnisdatei ist fertig (`awb:ergebnis`, V2). Kein Dauerplatz im
    /// Fenster: eine Zeile im Fuss, die von selbst wieder geht -- mit dem Weg
    /// zum Ergebnis daneben (Statusfuss.swift, `Ergebniszeile`).
    private func ergebnisGemeldet(_ e: ErgebnisNutzlast) {
        oberflaeche.ergebnis = e
        oberflaeche.ergebnisBis = Date().addingTimeInterval(30)
    }

    /// Der Knopf „Öffnen“ an der Ergebnismeldung: die Datei in den Editor.
    func ergebnisOeffnen() {
        guard let e = oberflaeche.ergebnis else { return }
        oberflaeche.ergebnisBis = .distantPast
        Task { await pfadOeffner.oeffnen(e.path) }
    }

    func ergebnisWeg() {
        oberflaeche.ergebnisBis = .distantPast
    }

    var ergebnisSichtbar: ErgebnisNutzlast? {
        oberflaeche.ergebnisBis > Date() ? oberflaeche.ergebnis : nil
    }

    @objc func freigabenUmschalten(_ sender: Any?) {
        guard let item = inspektorItem else { return }
        // Im Zustand Agents schaltet derselbe Knopf den Inspektor der Welt.
        if oberflaeche.modus == .agents {
            weltenZustand.inspektorOffen = item.isCollapsed
            // Ein Klick ist kein Zug am Teiler: der Abgleich soll ihn nicht als solchen lesen.
            weltenInspektorGesetzt = weltenZustand.inspektorOffen
        }
        blattSetzen(item, offen: item.isCollapsed)
    }

    /// Den Inspektor im Zustand Agents mit `weltenZustand.inspektorOffen` abgleichen, in beide
    /// Richtungen: aendert der Zustand sich (`agents inspektor an|aus`, Knopf im Fenster der
    /// Welten), folgt die Spalte; zieht der Mensch die Spalte am Teiler zu oder auf, folgt der
    /// Zustand. `weltenInspektorGesetzt` ist, was dieser Abgleich zuletzt hergestellt hat.
    private func weltenInspektorNachfuehren() {
        guard oberflaeche.modus == .agents, let item = inspektorItem else { weltenInspektorGesetzt = nil; return }
        let offen = !item.isCollapsed
        if let g = weltenInspektorGesetzt, g != offen, g == weltenZustand.inspektorOffen {
            weltenZustand.inspektorOffen = offen
        }
        if offen != weltenZustand.inspektorOffen { blattSetzen(item, offen: weltenZustand.inspektorOffen) }
        weltenInspektorGesetzt = weltenZustand.inspektorOffen
    }

    /// Kopflos ohne Animator (gemessen 06.09.: `animator().isCollapsed.toggle()`
    /// las in einem nie gezeigten Fenster den alten Wert und blieb zu). Dasselbe
    /// gilt ohne Fokus hinter anderen Fenstern (gemessen 16.09., vorschau-mac.sh):
    /// `agents inspektor an` blieb zu, der Abgleich las die ausbleibende Bewegung
    /// als Zug am Teiler und nahm den Zustand zurueck.
    private func blattSetzen(_ item: NSSplitViewItem, offen: Bool) {
        if optionen.pruefmodus { item.isCollapsed = !offen } else { item.animator().isCollapsed = !offen }
        // Dieselbe Bewegung wie an der Seitenleiste, dieselbe Nachsorge.
        terminal.flaecheSpaeterMelden(ruhe: TerminalBereich.bewegungsruhe)
        // Das Blatt geht in der gemerkten Breite auf (`blattBreite` des Kerns).
        if offen, breitenAngewandt {
            let b = gemeldeteBreiten.blatt
            DispatchQueue.main.async { [weak self] in self?.teilerSetzen(blatt: b) }
        }
    }

    /// Menuepunkte fuer die Leiste, damit jede Handlung ohne Maus geht (abnahme.md, Merkmal 11).
    @objc func freigabeFreigeben(_ sender: Any?) { leisteEntscheiden(true) }
    @objc func freigabeAblehnen(_ sender: Any?) { leisteEntscheiden(false) }
    @objc func freigabeVor(_ sender: Any?) { blaettern(1) }
    @objc func freigabeZurueck(_ sender: Any?) { blaettern(-1) }

    private func leisteEntscheiden(_ annehmen: Bool) {
        guard let f = freigabenZustand.vorne(offeneFreigaben) else { return }
        entscheiden(f, annehmen: annehmen, grund: freigabenZustand.grund.trimmingCharacters(in: .whitespacesAndNewlines))
        freigabenZustand.grund = ""
    }

    func blaettern(_ schritt: Int) {
        let n = offeneFreigaben.count
        guard n > 0 else { return }
        freigabenZustand.nr = ((freigabenZustand.nr + schritt) % n + n) % n
    }

    // MARK: Sitzungshandlungen (die Leiste und die Menueleiste enden hier)

    /// Ein Punkt des Kontextmenues. Das Loeschen fragt VORHER hier nach (Sheet
    /// am Fenster; kopflos entscheidet AWB_RUECKFRAGE wie im Kern) und sagt
    /// dem Kern mit `bestaetigt`, dass die Frage gestellt ist -- sonst fragte
    /// er ein zweites Mal ueber einen Electron-Dialog an seinem versteckten
    /// Fenster. Alle anderen Punkte gehen sofort an den Kern.
    func menuePunkt(_ sitzungsId: String, _ punkt: String) {
        guard let vorlage = MenuePunkt.alle.first(where: { $0.id == punkt }) else { return }
        // Eine Chat-Sitzung hat dasselbe Menue mit denselben Kennungen (main.ts
        // `menuePunktAusfuehren` kennt beide Sorten); Name und Ordner kommen aus `chats`.
        let name: String
        let ort: String
        if let s = kern.modell.sessions.first(where: { $0.id == sitzungsId }) {
            name = s.name
            ort = s.dir + (s.fern(eigene: kern.modell.machine) ? " auf \(s.machine)" : "")
        } else if let c = kern.modell.chats.first(where: { $0.id == sitzungsId }) {
            guard MenuePunkt.chat.contains(where: { $0.id == punkt }) else { return }
            name = c.name
            ort = c.ordner
        } else {
            return
        }
        let echt = !optionen.kopflos
        if vorlage.rueckfrage {
            Task { @MainActor in
                let ja = await rueckfrage(
                    "„\(name)“ endgültig löschen?",
                    "Die Sitzung in \(ort) wird beendet und ihre Zustandsdatei entfernt. Danach lässt sie sich nicht mehr fortsetzen.",
                    knopf: "Löschen")
                guard ja else { return }
                kern.menuePunkt(sitzungsId, punkt, echt: echt, bestaetigt: true)
            }
            return
        }
        kern.menuePunkt(sitzungsId, punkt, echt: echt)
    }

    func workerZeigen(sitzung: String, pane: String) {
        if kern.modell.selected == sitzung {
            kopf.workerPaneZeigen(pane)
        } else {
            oberflaeche.ansicht = .worker
            wunschPane = (sitzung, pane)
            kern.waehlen(sitzung)
        }
    }

    /// Die Rueckfrage vor etwas Unwiderruflichem. Kopflos entscheidet die
    /// Attrappe `AWB_RUECKFRAGE` ('ja'/'nein', sonst nein) -- dieselbe Variable,
    /// die der Kern liest, damit eine Suite beide Fassungen gleich steuert.
    func rueckfrage(_ titel: String, _ text: String, knopf: String) async -> Bool {
        oberflaeche.letzteRueckfrage = titel
        if optionen.kopflos {
            let antwort = ProcessInfo.processInfo.environment["AWB_RUECKFRAGE"] == "ja"
            oberflaeche.letzteRueckfrageAntwort = antwort ? "ja" : "nein"
            return antwort
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = titel
        alert.informativeText = text
        // Abbrechen ist die Vorgabe: die Eingabetaste darf nichts Unwiderrufliches ausloesen.
        alert.addButton(withTitle: "Abbrechen")
        let loeschen = alert.addButton(withTitle: knopf)
        loeschen.hasDestructiveAction = true
        loeschen.keyEquivalent = ""
        let antwort = await alert.beginSheetModal(for: fenster)
        let ja = antwort == .alertSecondButtonReturn
        oberflaeche.letzteRueckfrageAntwort = ja ? "ja" : "nein"
        return ja
    }

    /// Der Kern bittet um einen neuen Namen (`awb:umbenennen`). Sichtbar: ein
    /// Sheet mit Textfeld; kopflos: der Zustand, den `awbmac-ctl umbenennen`
    /// beantwortet. Beide enden in `umbenennenBestaetigen`.
    func umbenennenFragen(_ u: UmbenennenNutzlast) {
        oberflaeche.umbenennen = u
        guard !optionen.kopflos else { return }
        let alert = NSAlert()
        alert.messageText = "Namen ändern"
        alert.informativeText = "Der neue Name der Sitzung in \(u.dir). Erlaubt sind Buchstaben, Ziffern, Leerzeichen, Punkt, Strich und Unterstrich."
        let feld = NSTextField(string: u.name)
        feld.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        feld.placeholderString = "Name der Sitzung"
        feld.setAccessibilityLabel("Neuer Name")
        alert.accessoryView = feld
        alert.window.initialFirstResponder = feld
        alert.addButton(withTitle: "Umbenennen")
        alert.addButton(withTitle: "Abbrechen")
        Task { @MainActor in
            let antwort = await alert.beginSheetModal(for: fenster)
            if antwort == .alertFirstButtonReturn {
                await umbenennenBestaetigen(u.id, feld.stringValue)
            } else {
                oberflaeche.umbenennen = nil
            }
        }
    }

    @discardableResult
    func umbenennenBestaetigen(_ id: String, _ name: String) async -> (ok: Bool, meldung: String) {
        let r = await kern.umbenennen(id, name)
        oberflaeche.umbenennen = nil
        return r
    }

    // MARK: Menueleiste: die Handlungen an der gewaehlten Sitzung

    @objc func sitzungFortsetzen(_ sender: Any?) { menuePunktGewaehlt("fortsetzen") }
    @objc func sitzungUmbenennen(_ sender: Any?) { menuePunktGewaehlt("umbenennen") }
    @objc func sitzungOrdnerZeigen(_ sender: Any?) { menuePunktGewaehlt("ordner-zeigen") }
    @objc func sitzungSchliessen(_ sender: Any?) { menuePunktGewaehlt("schliessen") }
    @objc func sitzungLoeschen(_ sender: Any?) { menuePunktGewaehlt("loeschen") }

    private func menuePunktGewaehlt(_ punkt: String) {
        guard let s = kern.gewaehlteSitzung else { return }
        menuePunkt(s.id, punkt)
    }

    @objc func beendeteUmschalten(_ sender: Any?) {
        kern.beendeteZeigen(!kern.modell.ui.showStopped)
    }

    @objc func sortierungWaehlen(_ sender: NSMenuItem) {
        guard let schluessel = sender.representedObject as? String else { return }
        kern.sortierung(schluessel)
    }

    /// Menuepunkte grau, wenn sie nicht gehen; Haken, wo ein Zustand gilt
    /// (plattformen.md, macOS: „Menueeintraege aendern ihren Zustand mit dem Kontext“).
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(sitzungFortsetzen(_:)), #selector(sitzungUmbenennen(_:)), #selector(sitzungOrdnerZeigen(_:)),
             #selector(sitzungSchliessen(_:)), #selector(sitzungLoeschen(_:)):
            return kern.gewaehlteSitzung != nil
        case #selector(beendeteUmschalten(_:)):
            item.state = kern.modell.ui.showStopped ? .on : .off
            return kern.verbunden
        case #selector(sortierungWaehlen(_:)):
            item.state = (item.representedObject as? String) == kern.modell.ui.sort ? .on : .off
            return kern.verbunden
        case #selector(orchestratorZeigen(_:)), #selector(workerZeigen(_:)):
            return kern.gewaehlteSitzung != nil && !chatGezeigt && oberflaeche.modus == .code
        // Die Welten gehen immer: sie haengen an keiner gewaehlten Sitzung.
        case #selector(agentsUmschalten(_:)):
            item.state = oberflaeche.modus == .agents ? .on : .off
            return true
        case #selector(freigabenUmschalten(_:)):
            item.state = freigabenBlattSichtbar ? .on : .off
            return true
        case #selector(freigabeFreigeben(_:)), #selector(freigabeAblehnen(_:)):
            return !offeneFreigaben.isEmpty
        case #selector(freigabeVor(_:)), #selector(freigabeZurueck(_:)):
            return offeneFreigaben.count > 1
        case #selector(workerListeUmschalten(_:)):
            item.state = oberflaeche.workerListeOffen ? .on : .off
            // Die Pille steht im Zustand Agents nicht in der Symbolleiste; ihre Liste geht dann auch nicht auf.
            return kern.gewaehlteSitzung != nil && oberflaeche.modus == .code
        // Eine neue Welt geht immer, auch ohne Welt; einen Agenten nur in einer gewaehlten Welt, die laeuft.
        case #selector(weltNeuImOrdner(_:)):
            return kern.verbunden && !weltenZustand.laufend.contains("neu")
        case #selector(agentAnlegenMenue(_:)):
            guard let n = kern.welten, let w = weltenZustand.welt(n) else { return false }
            item.title = WeltenZustand.anlegenLage(w).titel + " …"
            return WeltenZustand.anlegenLage(w).aktiv
        // Kachel und Tab-Streifen ordnen die Code-Buehne: sie waeren sonst
        // Handgriffe an einer Buehne, die gerade niemand sieht.
        case #selector(kachelZoomUmschalten(_:)):
            item.state = terminal.lageArt == "pane" ? .on : .off
            return kern.gewaehlteSitzung != nil && optionen.terminal == .strom && !terminal.gezeigterPane.isEmpty && oberflaeche.modus == .code
        case #selector(naechsteKachel(_:)), #selector(vorigeKachel(_:)):
            return terminal.gezeigtePanes.count > 1 && oberflaeche.modus == .code
        case #selector(naechsterTab(_:)), #selector(vorigerTab(_:)):
            return kopf.tabMarken().count > 1 && oberflaeche.modus == .code
        case #selector(hinweisAusblenden(_:)):
            return !kern.meldung.isEmpty && kern.meldungBis > Date()
        case #selector(maschineGewaehlt(_:)), #selector(maschineLadenUmschalten(_:)):
            return kern.verbunden
        case #selector(seitenleisteUmschalten(_:)):
            item.state = seitenleisteSichtbar ? .on : .off
            return true
        // Klappen geht nur, solange eine Zeile gewaehlt ist -- sie sagt, welches
        // Projekt gemeint ist. Grau statt wirkungslos (plattformen.md, macOS).
        case #selector(projektEinklappen(_:)):
            return !gewaehltesProjekt.isEmpty && !oberflaeche.zugeklappteProjekte.contains(gewaehltesProjekt)
        case #selector(projektAufklappen(_:)):
            return !gewaehltesProjekt.isEmpty && oberflaeche.zugeklappteProjekte.contains(gewaehltesProjekt)
        case #selector(alleProjekteAufklappen(_:)):
            return !oberflaeche.zugeklappteProjekte.isEmpty
        // Der Haken sagt, welches Blatt der Inspektor gerade zeigt.
        case #selector(blattFreigaben(_:)):
            item.state = freigabenBlattSichtbar && oberflaeche.blatt == .freigaben ? .on : .off
            return true
        case #selector(blattOrdner(_:)):
            item.state = freigabenBlattSichtbar && oberflaeche.blatt == .ordner ? .on : .off
            return true
        case #selector(blattAktivitaet(_:)):
            item.state = freigabenBlattSichtbar && oberflaeche.blatt == .aktivitaet ? .on : .off
            return true
        case #selector(blattProtokolle(_:)):
            item.state = freigabenBlattSichtbar && oberflaeche.blatt == .protokolle ? .on : .off
            return true
        case #selector(dateiSpeichern(_:)):
            return editorZustand.aktiverTab.map { $0.art == .datei && !$0.nurLesen } ?? false
        case #selector(auswahlSenden(_:)):
            return editorZustand.aktiv >= 0 && !(kern.gewaehlteSitzung?.orchestratorPane ?? "").isEmpty
        case #selector(editorKlappen(_:)):
            item.state = editorZustand.eingeklappt ? .on : .off
            return editorZustand.aktiv >= 0
        case #selector(editorNeuLaden(_:)):
            return editorZustand.aktiverTab?.aufPlatte ?? false
        case #selector(dateiOderFensterSchliessen(_:)):
            // Der Titel sagt, was ⌘W jetzt trifft: die Datei oder das Fenster.
            item.title = editorZustand.aktiv >= 0 ? "Datei schließen" : "Schließen"
            return true
        case #selector(chatHalt(_:)):
            return chatGezeigt && chat.verlauf.haltMoeglich
        case #selector(chatNeustart(_:)):
            return chatGezeigt && chat.verlauf.neustartMoeglich && !chat.verlauf.laeuft
        case #selector(chatModusWeiter(_:)):
            return chatGezeigt && chat.verlauf.laeuft && !chat.verlauf.kopf.modi.isEmpty
        case #selector(chatFreigabeErlauben(_:)), #selector(chatFreigabeAblehnen(_:)):
            return chatGezeigt && chatOffeneFrage != nil
        default:
            return true
        }
    }

    /// Chat, Kacheln oder Leerzustand -- nach dem Modell (renderer.ts `buehneZeigt`):
    /// ein Gespraech auf der Buehne (`chatGezeigt`) schlaegt die gewaehlte Sitzung.
    private func leerzustandNachfuehren() {
        // DIE WELTEN SCHLAGEN ALLE DREI (Auftrag macagents, seit Nr. 6 die Welten).
        // Sie sind kein vierter Zweig derselben Wahl, sondern die andere Buehne:
        // solange der Umschalter `Code | Agents` auf Agents steht, liegen sie vorn,
        // und Terminal, Gespraech, Editor und Leerzustand bleiben, wo sie sind.
        let agentsDa = oberflaeche.modus == .agents
        if weltenMitte.isHidden == agentsDa { weltenMitte.isHidden = !agentsDa }
        // Links und rechts dasselbe: die Leiste der Welt statt Projekten und Sitzungen,
        // der Inspektor der Welt statt der Blaetter.
        if weltenLeiste.isHidden == agentsDa { weltenLeiste.isHidden = !agentsDa }
        if seitenleisteHost.isHidden != agentsDa { seitenleisteHost.isHidden = agentsDa }
        if weltenInspektor.isHidden == agentsDa { weltenInspektor.isHidden = !agentsDa }
        if inspektorHost.isHidden != agentsDa { inspektorHost.isHidden = agentsDa }
        // DER EDITOR IST DER DRITTE ZWEIG DESSELBEN UMSCHALTERS (Auftrag 3.4).
        // Er schlaegt Gespraech und Kacheln, solange eine Datei aufgeklappt in
        // der Mitte steht -- dieselbe Reihenfolge wie in editor-view.ts, wo
        // `zeigen()` die Buehne versteckt, sobald ein Dateitab gewaehlt ist.
        // Eingeklappt zaehlt er nicht: dann hat die Buehne ihren Platz zurueck.
        let editorDa = !agentsDa && editorZustand.offen
        let chatDa = !agentsDa && !editorDa && chatGezeigt
        let leer = !agentsDa && !editorDa && !chatDa && kern.gewaehlteSitzung == nil
        if chatBuehne.isHidden == chatDa { chatBuehne.isHidden = !chatDa }
        leerHinweis.isHidden = !leer
        terminal.isHidden = agentsDa || leer || chatDa || editorDa
        editorBlatt?.isHidden = !editorDa
    }

    /// Der Umschalter `Code | Agents`: die Buehne wechseln. Der Takt zieht
    /// alles Weitere nach; die vier Aufrufe hier sind nur dafuer da, dass der
    /// Wechsel sofort steht statt nach einem Viertel einer Sekunde.
    func modusSetzen(_ neu: Buehnenmodus) {
        guard oberflaeche.modus != neu else { return }
        // Der Inspektor gehoert der Buehne: Code merkt sich, ob er offen war, und
        // Agents oeffnet ihn nach dem Zustand der Welten (`inspektorOffen`).
        let offen = neu == .agents ? weltenZustand.inspektorOffen : codeInspektorOffen
        if neu == .agents, let item = inspektorItem { codeInspektorOffen = !item.isCollapsed }
        // DIE LEISTE DER WELT BRAUCHT IHRE BREITE (gesehen 14.09. am Belegbild: bei 232 pt
        // standen Zustand und Spezialgebiet nur noch als „braucht d… · Nimmt A…“). Im Zustand
        // Agents steht die Spalte mindestens so breit wie im Fenster „Agents-Welten …“; der
        // Rueckweg stellt die Breite der Seitenleiste her, die der Mensch gezogen hat. Beides
        // ist ein Herstellen, keine Meldung an den Kern (`teilerSetzen` ohne `melden`).
        if neu == .agents {
            codeSeitenBreite = seitenleisteBreite
            oberflaeche.modus = neu
            if codeSeitenBreite > 0, codeSeitenBreite < Self.weltenLeisteBreite { teilerSetzen(seite: Self.weltenLeisteBreite) }
        } else {
            oberflaeche.modus = neu
            if codeSeitenBreite > 0, seitenleisteBreite > 0, seitenleisteBreite != codeSeitenBreite { teilerSetzen(seite: codeSeitenBreite) }
        }
        weltenZustand.tabSichtbar = neu == .agents
        if let item = inspektorItem, item.isCollapsed == offen { blattSetzen(item, offen: offen) }
        weltenInspektorGesetzt = neu == .agents ? weltenZustand.inspektorOffen : nil
        aufgabenSichtbarMelden()
        blaetterNachfuehren()
        editorNachfuehren()
        leerzustandNachfuehren()
        streifenNachfuehren()
        kopf.nachziehen()
    }

    @objc func agentsUmschalten(_ sender: Any?) {
        modusSetzen(oberflaeche.modus == .agents ? .code : .agents)
    }

    /// Ablage, Neue Welt in einem Projektordner … (⌃⌥⌘N): die Welten nach vorn, dann der Ordnerdialog als Sheet.
    @objc func weltNeuImOrdner(_ sender: Any?) {
        modusSetzen(.agents)
        Task { await weltenZustand.ordnerWaehlenUndAnlegen(echt: !optionen.kopflos) }
    }

    /// Ablage, Agent anlegen … (⌥⇧⌘N): das Anlege-Menue in der gewaehlten Welt.
    @objc func agentAnlegenMenue(_ sender: Any?) {
        guard let n = kern.welten, let w = weltenZustand.welt(n) else { return }
        modusSetzen(.agents)
        weltenZustand.anlegenStarten(n, w)
    }

    /// Ob die Welten gerade die Mitte fuellen -- fuer `awbmac-ctl ui`.
    var agentsSichtbar: Bool { !weltenMitte.isHiddenOrHasHiddenAncestor }

    /// Die Auskunft des Tabs „Agents": die der Welten (dieselbe wie `welten`, mit
    /// `sichtbar` fuer den Tab) und darunter `tab`, wie er im Fenster liegt.
    func agentsAuskunft() -> [String: Any] {
        // Titel und Symbolleiste folgen sonst erst im naechsten Takt; die Auskunft soll sagen, was jetzt steht.
        kopf.nachziehen()
        var raus = weltenZustand.auskunft(kern: kern, sichtbar: agentsSichtbar)
        raus["tab"] = agentsLage()
        return raus
    }

    /// Wie der Tab „Agents" im Fenster liegt -- fuer `awbmac-ctl agents` und `ui.agents`:
    /// welche Ansicht die Seitenleiste, die Buehne und der Inspektor gerade zeigen,
    /// und ob Zaehler und Pausenschalter in der Symbolleiste stehen.
    func agentsLage() -> [String: Any] {
        func rahmen(_ v: NSView) -> [Int] {
            let r = v.convert(v.bounds, to: nil)
            return [Int(r.minX.rounded()), Int(r.minY.rounded()), Int(r.width.rounded()), Int(r.height.rounded())]
        }
        let leiste = fenster.toolbar?.items ?? []
        func sichtbar(_ id: NSToolbarItem.Identifier) -> Bool { leiste.first { $0.itemIdentifier == id }.map { !$0.isHidden } ?? false }
        return [
            "seitenleiste": !seitenleisteSichtbar ? "zu" : (weltenLeiste.isHiddenOrHasHiddenAncestor ? "sitzungen" : "welt"),
            "buehne": agentsSichtbar ? "welt" : "code",
            "inspektor": inspektorItem?.isCollapsed ?? true ? "zu" : (weltenInspektor.isHiddenOrHasHiddenAncestor ? "blaetter" : "welt"),
            "leisteRahmen": rahmen(weltenLeiste), "mitteRahmen": rahmen(weltenMitte), "inspektorRahmen": rahmen(weltenInspektor),
            "zaehlerInSymbolleiste": sichtbar(Kopf.weltenZaehlerKennung), "pauseInSymbolleiste": sichtbar(Kopf.weltenPauseKennung),
            "pilleInSymbolleiste": sichtbar(Kopf.pilleKennung), "umschalterInSymbolleiste": sichtbar(Kopf.umschalterKennung),
            "fuss": AgentsWorte.fuss(kern.aufgaben).map(\.text),
            "titel": fenster.title, "untertitel": fenster.subtitle,
        ]
    }

    /// Die Tab-Zeile des Editors und sein Koerper nach dem Zustand des Blatts.
    /// Der Koerper entsteht beim ersten Mal -- vorher gibt es keinen Baustein.
    private func editorNachfuehren() {
        // Die Tabzeile gehoert zur Code-Buehne: steht das Agents-Blatt, hat sie
        // dort nichts zu suchen -- und ist sofort wieder da, wenn er zurueckschaltet.
        let leisteDa = editorZustand.leisteDa && oberflaeche.modus == .code
        if editorLeiste.isHidden == leisteDa { editorLeiste.isHidden = !leisteDa }
        if editorZustand.offen, editorBlatt == nil {
            let blatt = EditorBlatt(zustand: editorZustand)
            blatt.translatesAutoresizingMaskIntoConstraints = false
            buehneView.addSubview(blatt)
            NSLayoutConstraint.activate([
                blatt.leadingAnchor.constraint(equalTo: buehneView.leadingAnchor),
                blatt.trailingAnchor.constraint(equalTo: buehneView.trailingAnchor),
                blatt.topAnchor.constraint(equalTo: buehneView.topAnchor),
                blatt.bottomAnchor.constraint(equalTo: buehneView.bottomAnchor),
            ])
            editorBlatt = blatt
        }
        leerzustandNachfuehren()
    }

    /// Ob der Editor gerade die Mitte fuellt -- fuer `awbmac-ctl ui`.
    var editorSichtbar: Bool { !(editorBlatt?.isHiddenOrHasHiddenAncestor ?? true) }

    /// Die Hoehe der Editor-Tabzeile in Punkten (0, wenn sie nicht steht).
    var editorLeisteHoehe: CGFloat { editorLeiste.isHidden ? 0 : editorLeiste.frame.height }

    // MARK: Menue „Ablage“: Speichern, Auswahl senden, Einklappen, Schliessen (Auftrag 3.4)

    @objc func dateiSpeichern(_ sender: Any?) { Task { await editorZustand.speichern() } }

    @objc func auswahlSenden(_ sender: Any?) {
        // Der Knopf im Fenster IST der Mensch (main.ts, „Der Steuerkanal tippt
        // nicht in einen Orchestrator-Pane"): `echt` gilt hier, kopflos nie.
        Task { _ = await editorZustand.auswahlSenden(echt: !optionen.kopflos) }
    }

    @objc func editorKlappen(_ sender: Any?) { editorZustand.klappUmschalten() }

    @objc func editorNeuLaden(_ sender: Any?) { Task { await editorZustand.neuLaden() } }

    /// ⌘W: auf dem Mac schliesst es das Fenster -- steht aber eine Datei offen,
    /// schliesst es zuerst sie (wie Xcode und jeder Editor dieses Hauses).
    @objc func dateiOderFensterSchliessen(_ sender: Any?) {
        if editorZustand.aktiv >= 0 {
            let i = editorZustand.aktiv
            Task { await editorZustand.schliessen(i) }
            return
        }
        fenster.performClose(sender)
    }

    /// Liegt ein Gespraech auf der Buehne (nicht sein Worker)?
    var chatGezeigt: Bool { !kern.modell.chatGezeigt.isEmpty }

    /// Der Zustand der Chat-Buehne folgt dem Modell: welche Sitzung liegt,
    /// welche Worker sie hat (ChatBuehne.swift, Dateikopf).
    private func chatNachziehen() {
        let m = kern.modell
        let id = m.chatGezeigt
        let worker = id.isEmpty ? [] : (m.chats.first { $0.id == id }?.worker ?? [])
        chat.nachModell(gezeigt: id, worker: worker)
    }

    /// Eine Chat-Sitzung aus der Leiste: der echte Klick legt sie auf die
    /// Buehne, ein unechter (kopflos) startet sie nur (KernVerbindung.chatZeigen).
    func chatZeigen(_ id: String) {
        kern.chatZeigen(id, echt: !optionen.kopflos)
    }

    // Die Handlungen des Gespraechs aus der Menueleiste (abnahme.md, Merkmal 11).
    @objc func chatHalt(_ sender: Any?) { chat.halt() }
    @objc func chatNeustart(_ sender: Any?) { chat.neustart() }
    @objc func chatModusWeiter(_ sender: Any?) { chat.modusWeiter() }
    @objc func chatFreigabeErlauben(_ sender: Any?) { chatOffeneFreigabe(true) }
    @objc func chatFreigabeAblehnen(_ sender: Any?) { chatOffeneFreigabe(false) }

    /// Die erste offene Freigabefrage des Gespraechs.
    var chatOffeneFrage: ChatFreigabeBlock? {
        for b in chat.verlauf.bloecke { if case .freigabe(let f) = b, f.offen, !f.defekt { return f } }
        return nil
    }

    private func chatOffeneFreigabe(_ erlauben: Bool) {
        guard let f = chatOffeneFrage else { return }
        chat.freigabe(f.anfrageId, erlauben: erlauben)
    }

    /// Orchestrator oder Worker zeigen -- der Kopf richtet die Buehne (Kopf.swift).
    func ansichtSetzen(_ neu: Ansicht) {
        kopf.ansichtSetzen(neu)
    }

    @objc func workerListeUmschalten(_ sender: Any?) {
        kopf.workerListeUmschalten()
    }

    /// Das Einstellungsfenster BAUEN und laden, ohne es zu zeigen -- der Weg
    /// des Steuerkanals (`awbmac-ctl einstellungen`), wie `einstellungen-bauen`
    /// im Kern. Zeigen tut nur `einstellungenZeigen`.
    func einstellungenBauen() async -> EinstellungenFenster {
        let e = einstellungenHerstellen()
        await e.bauen()
        return e
    }

    /// ⌘, / Zahnrad / Fuss: der Weg des Menschen. Kopflos nur der Zustand.
    @objc func einstellungenZeigen(_ sender: Any?) {
        einstellungenHerstellen().zeigen()
    }

    /// Eine Stelle, an der das Einstellungsfenster entsteht -- sonst haengt der
    /// Weg zum ersten Start (3.8) nur an einem der beiden Zugaenge.
    @discardableResult
    private func einstellungenHerstellen() -> EinstellungenFenster {
        if let e = einstellungen { return e }
        let e = EinstellungenFenster(kern: kern, optionen: optionen, oberflaeche: oberflaeche)
        e.zustand.erststartZeigen = { [weak self] echt in
            guard let self else { return }
            if echt { self.erststartZeigen() } else { Task { @MainActor in _ = await self.erststartBauen() } }
        }
        einstellungen = e
        return e
    }

    /// Das Sitzungsfenster BAUEN und laden, ohne es zu zeigen -- der Weg des
    /// Steuerkanals (`awbmac-ctl sitzung`), wie `sitzung-bauen` im Kern.
    func sitzungBauen() async -> SitzungsFenster {
        if sitzungen == nil {
            sitzungen = SitzungsFenster(kern: kern, optionen: optionen, oberflaeche: oberflaeche)
        }
        await sitzungen!.bauen()
        return sitzungen!
    }

    /// Die Verbrauchsseite BAUEN und lesen, ohne sie zu zeigen -- der Weg des
    /// Steuerkanals (`awbmac-ctl verbrauch`).
    func verbrauchBauen() async -> VerbrauchsFenster {
        if verbrauch == nil {
            verbrauch = VerbrauchsFenster(kern: kern, optionen: optionen)
        }
        await verbrauch!.bauen()
        return verbrauch!
    }

    /// Die Verbrauchszeile im Fuss und der Menuepunkt (⌥⌘V): der Weg des
    /// Menschen. Kopflos wird nur gebaut.
    func verbrauchZeigen() {
        if verbrauch == nil {
            verbrauch = VerbrauchsFenster(kern: kern, optionen: optionen)
        }
        verbrauch?.zeigen()
    }

    @objc func verbrauchZeigen(_ sender: Any?) { verbrauchZeigen() }

    /// Das Vorschau-Blatt der Agentenfiguren -- gebaut und gelesen, kopflos nie gezeigt.
    func figurenBauen() -> AgentenfigurenFenster {
        if figuren == nil { figuren = AgentenfigurenFenster(optionen: optionen) }
        return figuren!
    }

    @objc func figurenZeigen(_ sender: Any?) { figurenBauen().zeigen() }

    /// Das Fenster „Agents-Welten …" -- gebaut und gelesen, kopflos nie gezeigt. Es
    /// zeigt dieselbe Ansicht mit demselben Zustand wie der Tab „Agents".
    func weltenBauen() -> WeltenFenster {
        if let w = welten { return w }
        let w = WeltenFenster(kern: kern, zustand: weltenZustand, optionen: optionen)
        w.beiSichtbarkeit = { [weak self] in self?.aufgabenSichtbarMelden() }
        welten = w
        return w
    }

    @objc func weltenZeigen(_ sender: Any?) { weltenBauen().zeigen() }

    /// Der Kern taktet `awb:aufgaben` schnell, solange der Tab Agents ODER das Fenster der Welten steht (Befund M4).
    func aufgabenSichtbarMelden() {
        kern.send("awb:aufgaben-sichtbar", [oberflaeche.modus == .agents || welten?.sichtbar == true])
    }

    /// Der gefuehrte erste Start (Auftrag 3.8), gebaut und gelesen -- nie gezeigt.
    func erststartBauen() async -> ErststartSheet {
        if erststart == nil {
            erststart = ErststartSheet(kern: kern, kopflos: optionen.kopflos, haupt: fenster)
        }
        await erststart!.bauen()
        return erststart!
    }

    /// Der Weg des Menschen: der Knopf „Ersten Start erneut zeigen“ der
    /// Einstellungen (2.6) und der erste sichtbare Start. Kopflos wird nur
    /// gebaut -- derselbe Griff wie im Kern (`zeigeAutomatisch`).
    func erststartZeigen() {
        Task { @MainActor in
            let s = await erststartBauen()
            s.zeigen()
        }
    }

    /// „Beim ersten Start, und danach nie wieder von selbst": gebaut wird immer
    /// (damit eine Pruefung ohne einen einzigen echten Klick sieht, ob der Weg
    /// anlaeuft), gezeigt nur, wenn der Kern den Weg noch nicht als erledigt
    /// kennt und dieses Fenster wirklich sichtbar ist.
    func erststartPruefen() {
        Task { @MainActor in
            // Erst die Verbindung: `laden()` ohne sie brächte ein leeres Blatt,
            // und die Frage „schon erledigt?" beantwortet nur der Kern.
            for _ in 0..<100 where !kern.verbunden {
                try? await Task.sleep(for: .milliseconds(50))
            }
            let s = await erststartBauen()
            guard s.zustand.daten?.erledigt == false, !optionen.kopflos, fenster.isVisible else { return }
            s.zeigen()
        }
    }

    /// ⌘N (Ablage, Neue Sitzung …): der Weg des Menschen. Kopflos nur der Zustand.
    @objc func sitzungenZeigen(_ sender: Any?) {
        if sitzungen == nil {
            sitzungen = SitzungsFenster(kern: kern, optionen: optionen, oberflaeche: oberflaeche)
        }
        sitzungen?.zeigen()
    }

    @objc func seitenleisteUmschalten(_ sender: Any?) {
        splitController.toggleSidebar(sender)
        // Sofort und nicht erst im naechsten Takt: das Umschalten ist auf dem
        // Mac animiert, und die Buehne soll den Abstand mit der Bewegung
        // bekommen und nicht eine Viertelsekunde danach.
        buehnenEinzugNachfuehren()
    }

    /// Von Hand gesetzt (`awbmac-ctl erscheinung`, nur fuer Belegbilder): dann
    /// bleibt die Einstellung des Kerns aussen vor, bis die App neu startet.
    var erscheinungVonHand = false

    func erscheinungAnwenden(_ t: ThemaNutzlast) {
        guard !erscheinungVonHand else { return }
        let neu: NSAppearance?
        switch t.thema {
        case "hell": neu = NSAppearance(named: .aqua)
        case "dunkel": neu = NSAppearance(named: .darkAqua)
        default: neu = nil
        }
        erscheinungErzwingen(neu)
    }

    /// Hell, dunkel oder System fuer App, Fenster und jede Spalte -- der Weg der Einstellung
    /// und von `agents erscheinung`.
    func erscheinungErzwingen(_ neu: NSAppearance?) {
        NSApp.appearance = neu
        // DIE SEITENLEISTE ZEICHNET IHR MATERIAL NICHT VON SELBST NEU
        // (gesehen 08.09.2026 am Belegbild: Symbolleiste und Buehne standen
        // dunkel, die Spalte links blieb hell). Ein Wechsel an `NSApp`
        // erreicht die Spalten eines NSSplitViewController nicht zuverlaessig,
        // solange das Fenster nicht vorn ist -- und beim Belegbild ist es das
        // nie. Das Fenster bekommt das Erscheinungsbild deshalb selbst, und
        // jede Spalte wird angewiesen, sich neu zu zeichnen.
        fenster.appearance = neu
        for item in splitController.splitViewItems {
            item.viewController.view.appearance = neu
            item.viewController.view.needsDisplay = true
        }
        splitController.splitView.needsDisplay = true
    }

    @objc func orchestratorZeigen(_ sender: Any?) { ansichtSetzen(.orchestrator) }
    @objc func workerZeigen(_ sender: Any?) { ansichtSetzen(.worker) }

    // MARK: Projekte zu- und aufklappen (Politur 08.09.)

    /// Das Projekt, in dem die gewaehlte Zeile liegt -- der Ordner ist die
    /// Kennung des Abschnitts (ModellNutzlast.Projekt.id).
    var gewaehltesProjekt: String {
        if let c = kern.modell.gezeigterChat { return c.ordner }
        return kern.gewaehlteSitzung?.dir ?? ""
    }

    /// Die Liste hoert selbst auf `oberflaeche` (@Observable); der Layoutlauf
    /// steht nur hier, damit ein kopfloses Fenster die neue Zeilenzahl noch im
    /// selben Takt melden kann.
    func projektKlappen(_ id: String, offen: Bool) {
        oberflaeche.projektKlappen(id, offen: offen)
        seitenleisteHost.layoutSubtreeIfNeeded()
    }

    /// EINE NEUE SITZUNG AUS DER LEISTE (08.09.2026, Nachtrag des Nutzers).
    ///
    /// Ein Weg fuer beide Plusknoepfe: leerer `ordner` heisst „erst fragen"
    /// (NSOpenPanel, nur Ordner, neue Ordner erlaubt), ein gesetzter heisst
    /// „hier, ohne Dialog". Beide gehen danach durch DENSELBEN Kanal wie die
    /// Electron-Fassung und wie das Sitzungsfenster (`awb:sitz-neu`, main.ts
    /// `sessionAnlegen`) -- ohne eigene Wahl, also mit dem Orchestrator aus den
    /// Einstellungen. Ein zweiter Startweg waere eine zweite Stelle, an der
    /// Ausschlussliste, Doppelklick-Schutz und Schluesselvergabe auseinander
    /// laufen koennen.
    func neueSitzung(ordner: String, echt: Bool) {
        guard !sitzungLaeuftAn else { return }
        sitzungLaeuftAn = true
        Task { @MainActor in
            defer { sitzungLaeuftAn = false }
            var pfad = ordner
            if pfad.isEmpty {
                guard echt, !optionen.kopflos else {
                    kern.melden("Ohne echten Klick wird kein Ordner-Dialog geöffnet.")
                    return
                }
                pfad = await ordnerWaehlen()
                guard !pfad.isEmpty else {
                    kern.melden("Abgebrochen – es wurde nichts gestartet.")
                    return
                }
            }
            let bekannt = Set(kern.modell.sessions.map(\.id))
            let a = await kern.invoke("awb:sitz-neu", ["", "", "", echt && !optionen.kopflos, pfad])
            let j = a.wertJSON.map(JSONWert.lesen) ?? .null
            let ok = j["ok"].bool ?? false
            let meldung = j["meldung"].text ?? (a.fehler ?? "")
            kern.melden(meldung.isEmpty ? (ok ? "Sitzung gestartet." : "Die Sitzung ist nicht gestartet.") : meldung)
            guard ok else { return }
            // Die neue Sitzung ist die gewaehlte: der Kern schickt sein Modell
            // gleich nach. Gewaehlt wird nur eine Zeile, die es VOR dem Start
            // noch nicht gab -- sonst spraenge die Wahl auf die alte Sitzung
            // desselben Ordners, die ja weiterlaeuft.
            neueSitzungWaehlen(ordner: pfad, ausser: bekannt)
        }
    }

    /// Die eben entstandene Sitzung waehlen, sobald der Kern sie meldet. Warten
    /// mit Frist: bleibt sie aus, wird nichts gewaehlt (und nichts blockiert).
    private func neueSitzungWaehlen(ordner: String, ausser bekannt: Set<String>) {
        Task { @MainActor in
            let frist = Date().addingTimeInterval(10)
            while Date() < frist {
                if let neu = kern.modell.sessions
                    .filter({ $0.dir == ordner && !bekannt.contains($0.id) })
                    .max(by: { $0.lastActive < $1.lastActive }) {
                    if neu.id != kern.modell.selected { kern.waehlen(neu.id) }
                    return
                }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
    }

    /// Der Ordnerdialog des Systems als Sheet am Hauptfenster -- derselbe wie im
    /// Sitzungsfenster (Sitzungsblatt.swift).
    private func ordnerWaehlen() async -> String {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Ordner für die neue Sitzung"
        panel.prompt = "Sitzung hier starten"
        let r = await panel.beginSheetModal(for: fenster)
        return r == .OK ? (panel.url?.path ?? "") : ""
    }

    /// Ablage, Neue Sitzung in einem Ordner … (⇧⌘N).
    @objc func neueSitzungImOrdner(_ sender: Any?) { neueSitzung(ordner: "", echt: true) }

    /// Ablage, Neue Sitzung in diesem Projekt (⌥⌘N) -- das Projekt der gewaehlten Zeile.
    @objc func neueSitzungImProjekt(_ sender: Any?) {
        guard let dir = projektDerWahl else { return }
        neueSitzung(ordner: dir, echt: true)
    }

    /// Der Ordner des Projekts, in dem die gewaehlte Zeile steht.
    var projektDerWahl: String? {
        let gewaehlt = kern.modell.selected
        guard !gewaehlt.isEmpty else { return kern.modell.projekte.first?.dir }
        return kern.modell.projekte.first { $0.zeilen.contains { $0.kennung == gewaehlt } }?.dir
            ?? kern.modell.projekte.first?.dir
    }

    @objc func projektEinklappen(_ sender: Any?) {
        guard !gewaehltesProjekt.isEmpty else { return }
        projektKlappen(gewaehltesProjekt, offen: false)
    }

    @objc func projektAufklappen(_ sender: Any?) {
        guard !gewaehltesProjekt.isEmpty else { return }
        projektKlappen(gewaehltesProjekt, offen: true)
    }

    // MARK: Von Hand gezogene Reihenfolge (Auftrag macleiste, 08.09.2026)

    /// Die Zeilen aller Projekte hintereinander -- die flache Liste, die der
    /// Kern als `order` fuehrt. Die Zeilen eines Projekts stehen darin
    /// VOLLSTAENDIG beieinander; genau daran scheitert das Zurueckspringen,
    /// das die Electron-Fassung am 04.09. gekostet hat (renderer.ts,
    /// `flacheReihenfolge`): die Leiste gruppiert nach Ordner, und eine Liste,
    /// in der zwei Zeilen eines Projekts durch eine fremde getrennt sind,
    /// kommt aus der Gruppierung anders wieder heraus, als sie hineinging.
    private func flacheReihenfolge(_ bloecke: [ModellNutzlast.Projekt]) -> [String] {
        bloecke.flatMap { $0.zeilen.map(\.kennung) }
    }

    /// Beide Listen an den Kern: die Ordner in ihrer Folge und die Zeilen in
    /// ihrer. Sie gehoeren zusammen -- der Kern stellt die Bloecke nach der
    /// ersten und laesst ihre innere Folge, wie die zweite sie sagt.
    private func reihenfolgeMelden(_ bloecke: [ModellNutzlast.Projekt]) {
        kern.projektReihenfolge(bloecke.map(\.dir))
        kern.reihenfolge(flacheReihenfolge(bloecke))
    }

    /// Eine Zeile VOR eine andere Zeile desselben Projekts. Ein Zug auf ein
    /// fremdes Projekt wird nicht angenommen: der Ordner bestimmt das Projekt,
    /// nicht die Reihenfolge (dieselbe Regel wie renderer.ts `zeileVerschieben`).
    func zeileZiehen(_ gezogen: String, auf ziel: String) {
        guard gezogen != ziel else { return }
        var bloecke = kern.modell.projekte
        guard let bi = bloecke.firstIndex(where: { $0.zeilen.contains { $0.kennung == gezogen } }),
              let von = bloecke[bi].zeilen.firstIndex(where: { $0.kennung == gezogen }),
              bloecke[bi].zeilen.contains(where: { $0.kennung == ziel }) else { return }
        var zeilen = bloecke[bi].zeilen
        let z = zeilen.remove(at: von)
        guard let nach = zeilen.firstIndex(where: { $0.kennung == ziel }) else { return }
        zeilen.insert(z, at: nach)
        bloecke[bi] = ModellNutzlast.Projekt(dir: bloecke[bi].dir, zeilen: zeilen)
        reihenfolgeMelden(bloecke)
    }

    /// Ein ganzer Projektblock vor einen anderen.
    func projektZiehen(_ gezogen: String, auf ziel: String) {
        guard gezogen != ziel else { return }
        var bloecke = kern.modell.projekte
        guard let von = bloecke.firstIndex(where: { $0.dir == gezogen }),
              bloecke.contains(where: { $0.dir == ziel }) else { return }
        let block = bloecke.remove(at: von)
        guard let nach = bloecke.firstIndex(where: { $0.dir == ziel }) else { return }
        bloecke.insert(block, at: nach)
        reihenfolgeMelden(bloecke)
    }

    /// Eine Zeile um EINEN Platz. Nicht ueber `zeileZiehen`, sondern mit den
    /// Stellen der urspruenglichen Liste: nimmt man die Zeile erst heraus und
    /// legt sie dann an die Stelle des Nachbarn, landet sie beim Weg nach unten
    /// genau dort, wo sie herkam.
    func zeileSchieben(_ kennung: String, hoch: Bool) {
        var bloecke = kern.modell.projekte
        guard let bi = bloecke.firstIndex(where: { $0.zeilen.contains { $0.kennung == kennung } }),
              let i = bloecke[bi].zeilen.firstIndex(where: { $0.kennung == kennung }) else { return }
        var zeilen = bloecke[bi].zeilen
        let j = hoch ? i - 1 : i + 1
        guard j >= 0, j < zeilen.count else { return }
        let z = zeilen.remove(at: i)
        zeilen.insert(z, at: j)
        bloecke[bi] = ModellNutzlast.Projekt(dir: bloecke[bi].dir, zeilen: zeilen)
        reihenfolgeMelden(bloecke)
    }

    /// Ein Projekt um EINEN Platz -- dieselbe Rechnung wie `zeileSchieben`.
    func projektSchieben(_ dir: String, hoch: Bool) {
        var bloecke = kern.modell.projekte
        guard let i = bloecke.firstIndex(where: { $0.dir == dir }) else { return }
        let j = hoch ? i - 1 : i + 1
        guard j >= 0, j < bloecke.count else { return }
        let block = bloecke.remove(at: i)
        bloecke.insert(block, at: j)
        reihenfolgeMelden(bloecke)
    }

    @objc func alleProjekteAufklappen(_ sender: Any?) {
        guard !oberflaeche.zugeklappteProjekte.isEmpty else { return }
        for id in oberflaeche.zugeklappteProjekte { oberflaeche.projektKlappen(id, offen: true) }
        seitenleisteHost.layoutSubtreeIfNeeded()
    }

    /// Wie viele Zeilen die Seitenleiste WIRKLICH gebaut hat (NSTableRowView im
    /// Sichtbaum) -- die Auskunft ueber das Gezeichnete, nicht ueber das Modell.
    var seitenleisteZeilen: Int {
        guard let v = seitenleisteHost else { return 0 }
        var zaehler = 0
        func gehen(_ x: NSView) {
            if x is NSTableRowView { zaehler += 1 }
            for k in x.subviews { gehen(k) }
        }
        gehen(v)
        return zaehler
    }

    /// Die Hoehen der gezeichneten Zeilen, absteigend nach Haeufigkeit -- die
    /// Gegenprobe zu Zahl des Nutzers vom 05.09. (Sitzungszeile 44 pt,
    /// Projektzeile 32; werkbank.css `--zeilenhoehe`, `--projektzeile`).
    /// Gemessen am Sichtbaum, nicht am Entwurf.
    var seitenleisteZeilenhoehen: [Int] {
        guard let v = seitenleisteHost else { return [] }
        var hoehen: [Int] = []
        func gehen(_ x: NSView) {
            if x is NSTableRowView { hoehen.append(Int(x.frame.height.rounded())) }
            for k in x.subviews { gehen(k) }
        }
        gehen(v)
        return hoehen.sorted()
    }

    /// DIE INHALTSFLAECHE DER GEWAEHLTEN ZEILE (08.09.2026, Vorgabe des Nutzers
    /// „32 pt behalten, optisch schlanker").
    ///
    /// Die Zeile selbst misst 32 Punkte und laesst sich nicht kleiner machen
    /// (`Leistenmasse` in Seitenleiste.swift). Schlanker wird, was DARIN liegt:
    /// der Inhalt der Zeile -- Text, Punkt und Zusatz sitzen jetzt in 22 statt
    /// 24 Punkten, mit fuenf Punkten Luft oben und unten.
    ///
    /// NICHT GEMESSEN WIRD HIER DIE GEZEICHNETE AUSWAHL: die gehoert der
    /// Plattform, wird ueber den Zeilenhintergrund gelegt und fuellt die ganzen
    /// 32 Punkte (am Belegbild nachgewiesen, siehe Seitenleiste.swift). Diese
    /// Zahl sagt, wie viel Platz der Inhalt einnimmt -- die eine Groesse, die
    /// die App an dieser Zeile noch selbst bestimmt.
    ///
    /// Gemessen wird sie am Sichtbaum, nicht am Entwurf --
    /// gesucht ist in der gewaehlten `NSTableRowView` die NIEDRIGSTE Ansicht,
    /// die noch mindestens die halbe Zeilenbreite einnimmt. Das ist der
    /// Inhaltsrahmen, den SwiftUI fuer die Zeile aufspannt; alles Schmalere
    /// darin sind einzelne Beschriftungen und Knoepfe.
    ///
    /// Ohne Auswahl wird die erste Sitzungszeile gemessen -- kopflos steht
    /// nicht immer eine Wahl, und die Zahl soll trotzdem da sein.
    var seitenleisteInhaltsflaeche: [String: Int] {
        guard let v = seitenleisteHost else { return [:] }
        var zeilen: [(NSTableRowView, Bool)] = []
        func gehen(_ x: NSView) {
            if let r = x as? NSTableRowView { zeilen.append((r, r.isSelected)); return }
            for k in x.subviews { gehen(k) }
        }
        gehen(v)
        // Die gewaehlte Zeile, sonst die hoechste (eine Sitzung, kein Kopf).
        let ziel = zeilen.first { $0.1 }?.0
            ?? zeilen.map(\.0).max(by: { $0.frame.height < $1.frame.height })
        guard let r = ziel else { return [:] }
        var flaeche = r.bounds
        func suchen(_ x: NSView) {
            for k in x.subviews {
                let f = k.convert(k.bounds, to: r)
                if f.width >= r.bounds.width / 2, f.height < flaeche.height { flaeche = f }
                suchen(k)
            }
        }
        suchen(r)
        return ["hoehe": Int(flaeche.height.rounded()),
                "zeile": Int(r.frame.height.rounded()),
                "oben": Int(flaeche.minY.rounded()),
                "gewaehlt": r.isSelected ? 1 : 0]
    }

    /// DAS ZUSTANDSWORT UND SEIN PLATZ (08.09.2026, Entscheidung des Nutzers „der
    /// Zusatz bekommt Mindestplatz fuer das Zustandswort").
    ///
    /// Je Sitzungszeile: das Wort, die Breite, die es in seiner Schrift braucht
    /// (Caption 2, gerechnet wie SwiftUI es setzt), und der Platz, den die Zeile
    /// ueberhaupt hat -- die gemessene Inhaltsbreite. Solange die erste Zahl
    /// unter der zweiten bleibt, kann das Wort nicht gekuerzt werden; im Bau
    /// ist es zusaetzlich mit `fixedSize` festgenagelt.
    var seitenleisteZustandsbreiten: [[String: Any]] {
        let schrift = NSFont.preferredFont(forTextStyle: .caption2)
        var platz = 0
        if let v = seitenleisteHost {
            var zeilen: [NSTableRowView] = []
            func gehen(_ x: NSView) {
                if let r = x as? NSTableRowView { zeilen.append(r); return }
                for k in x.subviews { gehen(k) }
            }
            gehen(v)
            // Die schmalste Inhaltsbreite unter den gezeichneten Zeilen: was
            // dort passt, passt in jeder.
            var schmalste = CGFloat.greatestFiniteMagnitude
            for r in zeilen {
                var breite = r.bounds.width
                func suchen(_ x: NSView) {
                    for k in x.subviews {
                        let f = k.convert(k.bounds, to: r)
                        if f.width >= r.bounds.width / 2, f.width < breite { breite = f.width }
                        suchen(k)
                    }
                }
                suchen(r)
                schmalste = min(schmalste, breite)
            }
            if schmalste < .greatestFiniteMagnitude { platz = Int(schmalste.rounded()) }
        }
        return kern.modell.projekte.flatMap(\.zeilen).compactMap { z in
            guard case .sitzung(let s) = z else { return nil }
            let wort = s.zusatzteile(eigene: kern.modell.machine).zustand
            let breite = (wort as NSString).size(withAttributes: [.font: schrift]).width
            return ["name": s.name, "zustand": wort, "breite": Int(breite.rounded(.up)), "platz": platz]
        }
    }

    /// DIE PLUSKNOEPFE DER LEISTE, WIE SIE WIRKLICH DASTEHEN (08.09.2026,
    /// Befund des Nutzers „ich sehe das Plus am Projektkopf nicht").
    ///
    /// Gemessen wird die WIRKSAME Deckkraft: die des Knopfes mal die aller
    /// Ansichten ueber ihm. Ein Knopf, der selbst voll deckend ist, aber in
    /// einer durchsichtigen Huelle steckt, ist trotzdem unsichtbar -- und genau
    /// das war der Fehler (`opacity 0` am Knopf, Ueberfahren an derselben
    /// unsichtbaren Flaeche). Dazu Groesse und Lage, damit eine Pruefung auch
    /// sagen kann, dass er nicht nur da, sondern auch zu treffen ist.
    func seitenleistePlusknoepfe(_ kennung: String) -> [[String: Any]] {
        guard let v = seitenleisteHost else { return [] }
        var aus: [[String: Any]] = []
        func merken(_ eigen: CGFloat, _ breite: CGFloat, _ hoehe: CGFloat, _ versteckt: Bool) {
            aus.append(["deckung": (eigen * 100).rounded() / 100,
                        "breite": Int(breite.rounded()), "hoehe": Int(hoehe.rounded()),
                        "versteckt": versteckt])
        }
        func gehen(_ x: NSView, _ deckung: CGFloat) {
            let eigen = deckung * x.alphaValue
            if x.accessibilityIdentifier() == kennung {
                merken(eigen, x.frame.width, x.frame.height, x.isHiddenOrHasHiddenAncestor)
            } else {
                // SwiftUI haengt die Kennung an das BARRIEREFREIHEITS-Element,
                // nicht an die AppKit-Ansicht darunter. Also wird auch dort
                // nachgesehen; die Deckkraft kommt von der Ansicht, in der das
                // Element sitzt -- eine durchsichtige Huelle macht auch ein
                // Element unsichtbar.
                for e in (x.accessibilityChildren() ?? []) {
                    guard let el = e as? NSAccessibilityElement,
                          el.accessibilityIdentifier() == kennung else { continue }
                    let r = el.accessibilityFrame()
                    merken(eigen, r.width, r.height, x.isHiddenOrHasHiddenAncestor)
                }
            }
            for k in x.subviews { gehen(k, eigen) }
        }
        gehen(v, 1)
        return aus
    }

    var seitenleisteSichtbar: Bool {
        !(splitController.splitViewItems.first?.isCollapsed ?? true)
    }

    /// Ein Belegbild des ganzen Fensters -- auch dann, wenn es nie auf dem
    /// Bildschirm war: gezeichnet wird der Rahmen des Fensters (Titel, Symbol-
    /// leiste, Inhalt) in eine Bitmap. Gemessen am 06.09.: `cacheDisplay` auf
    /// dem Inhalt allein liefert nur Text ohne Fenstergrund (im dunklen
    /// Erscheinungsbild weiss auf transparent); der Rahmen bringt den Grund mit.
    func schuss(pfad: String) throws -> (breite: Int, hoehe: Int) {
        guard let rahmen = fenster.contentView?.superview else { throw NSError(domain: "Werkbank", code: 1, userInfo: [NSLocalizedDescriptionKey: "kein Fensterrahmen"]) }
        fenster.layoutIfNeeded()
        rahmen.layoutSubtreeIfNeeded()
        guard let rep = rahmen.bitmapImageRepForCachingDisplay(in: rahmen.bounds) else {
            throw NSError(domain: "Werkbank", code: 2, userInfo: [NSLocalizedDescriptionKey: "keine Bitmap"])
        }
        // Den Fenstergrund vorlegen: Materialien (Seitenleiste, Glas) zeichnen
        // ausserhalb des Bildschirms nichts, und ohne Grund staende dort Weiss.
        if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = ctx
            fenster.backgroundColor.setFill()
            NSRect(x: 0, y: 0, width: rep.pixelsWide, height: rep.pixelsHigh).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        rahmen.cacheDisplay(in: rahmen.bounds, to: rep)
        // Die Elemente der Symbolleiste (Kopf.swift): im Rahmenbild bleiben sie leer.
        kopf.symbolleisteZeichnen(in: rep)
        // Die offene Worker-Liste als Beleg (Kopf.swift): das Popover zeichnet
        // ausserhalb des Bildschirms nichts.
        kopf.belegZeichnen(in: rep, fensterHoehe: rahmen.bounds.height)
        // DIE SEITENLEISTE ALS BELEG, GETRENNT GEZEICHNET (gemessen 06.09.,
        // Auftrag mac21). Im Bild des Rahmens blieb ihre Spalte leer, obwohl die
        // Liste ihre Zeilen gebaut hatte (12 NSTableRowViews im Sichtbaum):
        // `cacheDisplay` auf der Spalte und `layer.render` liefern ausserhalb
        // des Bildschirms beide nichts -- die Zeilen der Tabelle sind
        // layer-gestuetzt und haben ohne Bildschirm keinen Inhalt. Also zeichnet
        // SwiftUIs `ImageRenderer` DIESELBEN Zeilen-Views (ProjektKopf,
        // SitzungsZeile, WorkerZeile, SubagentZeile) mit demselben Modell in der
        // Breite der Spalte und legt sie an ihre Stelle. Was dem Beleg fehlt, ist
        // die Liste selbst: Material, Auswahl, Aufklappdreiecke. Text, Symbole,
        // Farben und Einrueckung sind die des Fensters.
        if let seite = seitenleisteHost, !seite.isHiddenOrHasHiddenAncestor,
           let ctx = NSGraphicsContext(bitmapImageRep: rep) {
            let ziel = seite.convert(seite.bounds, to: nil)
            let beleg = SeitenleisteBeleg(modell: kern.modell, breite: ziel.width, hoehe: ziel.height, kern: kern, oberflaeche: oberflaeche, fuss: self)
                .environment(\.colorScheme, fenster.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light)
            let renderer = ImageRenderer(content: beleg)
            renderer.scale = fenster.backingScaleFactor
            renderer.proposedSize = ProposedViewSize(width: ziel.width, height: ziel.height)
            if let bild = renderer.nsImage {
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = ctx
                bild.draw(in: ziel, from: .zero, operation: .sourceOver, fraction: 1)
                NSGraphicsContext.restoreGraphicsState()
            }
        }
        // DER INSPEKTOR GENAUSO (Auftrag 2.4, um die Blaetter aus 3.5/3.6
        // erweitert; gemessen 06.09.): der
        // Inspektor kommt im Rahmenbild als ungerenderte Flaeche (Grundfarbe
        // des Materials, kein Text). Also dieselben Views mit demselben Zustand
        // ueber ImageRenderer in die Spalte legen, vorher den Fenstergrund.
        if let item = inspektorItem, !item.isCollapsed, let blatt = inspektorHost,
           !blatt.isHiddenOrHasHiddenAncestor, let ctx = NSGraphicsContext(bitmapImageRep: rep) {
            let ziel = blatt.convert(blatt.bounds, to: nil)
            let dunkel = fenster.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let beleg = InspektorBlatt(kern: kern, oberflaeche: oberflaeche, freigaben: freigabenZustand,
                                       ordner: ordnerZustand, aktivitaet: aktivitaetZustand,
                                       protokolle: protokolleZustand, handlungen: self, beleg: true)
                .frame(width: ziel.width, height: ziel.height, alignment: .topLeading)
                .environment(\.colorScheme, dunkel ? .dark : .light)
            let renderer = ImageRenderer(content: beleg)
            renderer.scale = fenster.backingScaleFactor
            renderer.proposedSize = ProposedViewSize(width: ziel.width, height: ziel.height)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = ctx
            fenster.backgroundColor.setFill()
            ziel.fill()
            renderer.nsImage?.draw(in: ziel, from: .zero, operation: .sourceOver, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
        }
        // DIE CHAT-BUEHNE ALS BELEG (Auftrag 3.2): ScrollView, Buttons und das
        // NSTextView zeichnen ausserhalb des Bildschirms nichts -- dieselbe
        // Ansicht mit demselben Zustand ueber ImageRenderer an ihre Stelle.
        if !chatBuehne.isHiddenOrHasHiddenAncestor, let ctx = NSGraphicsContext(bitmapImageRep: rep) {
            let ziel = chatBuehne.convert(chatBuehne.bounds, to: nil)
            let dunkel = fenster.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let beleg = ChatBuehne(zustand: chat, beleg: true)
                .frame(width: ziel.width, height: ziel.height)
                .environment(\.colorScheme, dunkel ? .dark : .light)
            let renderer = ImageRenderer(content: beleg)
            renderer.scale = fenster.backingScaleFactor
            renderer.proposedSize = ProposedViewSize(width: ziel.width, height: ziel.height)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = ctx
            fenster.backgroundColor.setFill()
            ziel.fill()
            renderer.nsImage?.draw(in: ziel, from: .zero, operation: .sourceOver, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
        }
        // DAS EDITOR-BLATT (Auftrag 3.4) aus demselben Grund: seine Tab-Zeile und
        // sein Dateibaum sind SwiftUI mit Buttons, ScrollView und Textfeld, und
        // die zeichnen ausserhalb des Bildschirms nichts. Der Text selbst kommt
        // vom NSTextView, der auch kopflos zeichnet (gemessen 06.09., 3.3) --
        // ueberzeichnet wird nur die Baumspalte und der Streifen.
        if !editorLeiste.isHidden, let ctx = NSGraphicsContext(bitmapImageRep: rep) {
            let ziel = editorLeiste.convert(editorLeiste.bounds, to: nil)
            let dunkel = fenster.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let beleg = EditorTabLeiste(zustand: editorZustand, beleg: true)
                .frame(width: ziel.width, height: ziel.height)
                .environment(\.colorScheme, dunkel ? .dark : .light)
            let renderer = ImageRenderer(content: beleg)
            renderer.scale = fenster.backingScaleFactor
            renderer.proposedSize = ProposedViewSize(width: ziel.width, height: ziel.height)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = ctx
            fenster.backgroundColor.setFill()
            ziel.fill()
            renderer.nsImage?.draw(in: ziel, from: .zero, operation: .sourceOver, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
        }
        if let blatt = editorBlatt, !blatt.isHiddenOrHasHiddenAncestor, let ctx = NSGraphicsContext(bitmapImageRep: rep) {
            let ziel = blatt.baumRahmen
            let dunkel = fenster.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let beleg = DateibaumAnsicht(zustand: editorZustand, beleg: true)
                .frame(width: ziel.width, height: ziel.height, alignment: .topLeading)
                .environment(\.colorScheme, dunkel ? .dark : .light)
            let renderer = ImageRenderer(content: beleg)
            renderer.scale = fenster.backingScaleFactor
            renderer.proposedSize = ProposedViewSize(width: ziel.width, height: ziel.height)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = ctx
            fenster.backgroundColor.setFill()
            ziel.fill()
            renderer.nsImage?.draw(in: ziel, from: .zero, operation: .sourceOver, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
        }
        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "Werkbank", code: 3, userInfo: [NSLocalizedDescriptionKey: "kein PNG"])
        }
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: pfad).deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: URL(fileURLWithPath: pfad))
        return (rep.pixelsWide, rep.pixelsHigh)
    }

    // MARK: NSToolbarDelegate

    private static let zahnradKennung = NSToolbarItem.Identifier("werkbank.zahnrad")
    private static let freigabenKennung = NSToolbarItem.Identifier("werkbank.freigaben")
    /// Das Symbol des Inspektorknopfs und sein Hilfeschildchen -- an EINER
    /// Stelle, weil `freigabenNachfuehren` das Schildchen im Takt neu setzt.
    static let inspektorSymbol = "sidebar.trailing"
    static let inspektorHilfe = "Inspektor: Freigaben, Ordner, Aktivität, Protokolle (⌥⌘I)"

    /// Rechts, in dieser Reihenfolge wie im Inhaltskopf der Electron-Fassung:
    /// Pille, Umschalter, Zahnrad. Der Titel (Name, Herkunft) steht links davon.
    /// Zaehler und Pausenschalter der Welt stehen vor dem Inspektorknopf und nur
    /// im Zustand Agents (Kopf.swift, `nachziehen`).
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace, Kopf.flaecheKennung, Kopf.pilleKennung, Kopf.umschalterKennung, .flexibleSpace,
         Kopf.weltenZaehlerKennung, Kopf.weltenPauseKennung, Self.freigabenKennung, Self.zahnradKennung]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch id {
        case Kopf.flaecheKennung:
            return kopf.flaecheItem()
        case Kopf.pilleKennung:
            return kopf.pilleItem()
        case Kopf.umschalterKennung:
            return kopf.umschalterItem()
        case Kopf.weltenZaehlerKennung:
            return kopf.weltenZaehlerItem()
        case Kopf.weltenPauseKennung:
            return kopf.weltenPauseItem()
        case Self.freigabenKennung:
            // Das Abzeichen der offenen Freigaben (Electron: Zaehler rechts oben).
            // Es steht IMMER da -- es ist der Weg ins Blatt, auch wenn nichts
            // wartet (Befund 2 der Inventur, 04.09.); die Zahl kommt als Badge,
            // bei null keins.
            //
            // DAS SYMBOL SAGT, WAS DER KNOPF OEFFNET (Befund des Nutzers vom
            // 08.09.: „das schild oben rechts öffnet nicht nur freigaben
            // sondern auch datei ansicht und weitere, das symbol passt also
            // nicht ganz"). Der Knopf schaltet den Inspektor, und der traegt
            // vier Blaetter; `checkmark.shield` versprach nur eines davon.
            // `sidebar.trailing` ist das Zeichen, mit dem der Mac ueberall auf
            // die hintere Spalte zeigt -- dasselbe, das
            // `NSToolbarItem.Identifier.toggleInspector` mitbringt. Der
            // Systemeintrag selbst kommt nicht in Frage: er traegt kein
            // Abzeichen, und die Zahl der offenen Freigaben soll am Knopf
            // bleiben.
            let item = NSToolbarItem(itemIdentifier: id)
            item.image = NSImage(systemSymbolName: Self.inspektorSymbol, accessibilityDescription: "Inspektor")
            item.label = "Inspektor"
            item.toolTip = Self.inspektorHilfe
            item.target = self
            item.action = #selector(freigabenUmschalten(_:))
            item.isBordered = true
            freigabenItem = item
            letzteOffene = -1
            return item
        case Self.zahnradKennung:
            let item = NSToolbarItem(itemIdentifier: id)
            item.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Einstellungen")
            item.label = "Einstellungen"
            item.toolTip = "Einstellungen"
            item.target = self
            item.action = #selector(einstellungenZeigen(_:))
            item.isBordered = true
            return item
        default:
            return nil
        }
    }

    // MARK: NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Auf dem Mac schliesst ⌘W das Fenster, die App bleibt (Vorgabe der Plattform).
        return true
    }

    /// Die Lage wird bei jeder Aenderung gemerkt -- auch in einem Fenster, das
    /// nie auf dem Bildschirm war (kopflos), damit eine Pruefung den Neustart
    /// zeigen kann. Ein sichtbares Fenster merkt AppKit ohnehin.
    func windowDidResize(_ notification: Notification) { lageMerken() }
    func windowDidMove(_ notification: Notification) { lageMerken() }

    // MARK: Auskunft ueber Symbolleiste und Menueleiste (fuer awbmac-ctl)

    /// Die Elemente der Symbolleiste mit ihrer Beschriftung fuer VoiceOver.
    /// Ein Element ohne eigene View traegt sein `label`; genau das liest
    /// VoiceOver bei einem Symbolleistenknopf vor.
    func symbolleisteAuskunft() -> [[String: Any]] {
        guard let leiste = fenster.toolbar else { return [] }
        leiste.validateVisibleItems()
        return leiste.items.map { item in
            [
                "id": item.itemIdentifier.rawValue,
                "label": item.label,
                "accessibility": (item.view?.accessibilityLabel()).flatMap { $0.isEmpty ? nil : $0 } ?? item.label,
                "hilfe": item.toolTip ?? "",
                "aktiv": item.isEnabled,
                "verborgen": item.isHidden,
                "abzeichen": freigabenItem === item ? String(kern.freigaben.offene.count) : "",
                // Das Zeichen auf dem Knopf, soweit dieses Fenster es selbst
                // gesetzt hat (NSImage gibt den Symbolnamen nicht zurueck).
                "symbol": freigabenItem === item ? Self.inspektorSymbol : (item.itemIdentifier == Self.zahnradKennung ? "gearshape" : ""),
            ]
        }
    }

    /// Die Menueleiste als Baum: Titel, Kuerzel, aktiv/grau, Haken -- so, wie
    /// sie JETZT staende, mit `validateMenuItem` und den Untermenues aus dem
    /// Delegaten. Ein Punkt mit `eigen` gehoert diesem Fenster; die uebrigen
    /// sind Standardpunkte des Systems (Bearbeiten, Dienste, Ausblenden …).
    func menueleisteAuskunft() -> [[String: Any]] {
        (NSApp.mainMenu?.items ?? []).map { ["titel": $0.title, "punkte": menuePunkte($0.submenu)] }
    }

    private func menuePunkte(_ menu: NSMenu?) -> [[String: Any]] {
        guard let menu else { return [] }
        if menu.delegate != nil { menu.delegate?.menuNeedsUpdate?(menu) }
        menu.update()
        return menu.items.map { it in
            if it.isSeparatorItem { return ["trenner": true] }
            var e: [String: Any] = [
                "titel": it.title, "kuerzel": Self.kuerzelText(it), "taste": it.keyEquivalent,
                "aktiv": it.isEnabled, "an": it.state == .on, "eigen": it.target === self,
                "aktion": it.action.map { NSStringFromSelector($0) } ?? "",
            ]
            if let sub = it.submenu { e["untermenue"] = menuePunkte(sub) }
            return e
        }
    }

    /// Das Kuerzel, wie es im Menue steht: ⌃⌥⇧⌘ und die Taste.
    static func kuerzelText(_ it: NSMenuItem) -> String {
        guard !it.keyEquivalent.isEmpty else { return "" }
        var t = ""
        let m = it.keyEquivalentModifierMask
        // Die Globus-Taste (fn): seit macOS 13 das Kuerzel fuer Vollbild.
        if m.contains(.function) { t += "fn " }
        if m.contains(.control) { t += "⌃" }
        if m.contains(.option) { t += "⌥" }
        if m.contains(.shift) || it.keyEquivalent != it.keyEquivalent.lowercased() { t += "⇧" }
        if m.contains(.command) { t += "⌘" }
        switch it.keyEquivalent {
        case "\r": t += "↩"
        case "\u{8}", "\u{7f}": t += "⌫"
        case "\u{1b}": t += "⎋"
        case "\t": t += "⇥"
        default: t += it.keyEquivalent.uppercased()
        }
        return t
    }
}

/// Der Leerzustand des Inhaltsbereichs: sagt, warum nichts da ist, und was zu tun ist.
struct LeerAnsicht: View {
    var body: some View {
        ContentUnavailableView(
            "Keine Sitzung gewählt",
            systemImage: "terminal",
            description: Text("Wähle links eine Sitzung. Ihr Orchestrator erscheint hier.")
        )
        .background(.background)
    }
}


/// DIE AUFTEILUNG DES FENSTERS (08.09.2026): Seitenleiste, Inhalt, Inspektor.
///
/// Eine eigene Klasse nur wegen EINER Sache: `toggleSidebar` erreicht den
/// Aufteiler aus drei Richtungen -- ueber den Menuepunkt „Seitenleiste
/// ein-/ausblenden“, ueber das Symbolleistenelement der Plattform und ueber
/// dessen Kuerzel. Nur zwei davon gehen durch `Fenster.seitenleisteUmschalten`;
/// das Symbolleistenelement schickt `toggleSidebar:` die Responderkette hinauf
/// und landet direkt hier. Wer nach JEDEM Zug etwas tun will, tut es also an
/// dieser Stelle.
final class Aufteilung: NSSplitViewController {
    /// Nach jedem Zug an der Seitenleiste, gleich aus welcher Richtung.
    var aufUmschalten: (() -> Void)?
    /// Ob die Bewegung animiert werden darf (im Betrieb ja, in einer Pruefung
    /// ohne gezeigtes Fenster nein -- siehe unten).
    var animiert = true

    /// NICHT `super.toggleSidebar` (08.09.2026, gemessen). Apples Fassung
    /// dreht `animator().isCollapsed` um, LIEST den alten Wert also durch den
    /// Animator-Stellvertreter -- und der liegt hinter dem echten zurueck.
    /// Gemessen an der laufenden App: nach dem ersten Einklappen stand
    /// `isCollapsed` auf wahr, die Spalten lagen aber unveraendert (Buehne 952
    /// statt 1192 Punkte breit, die Leiste weiter bei x=8), und erst der
    /// naechste Zug holte die vorige Bewegung nach. Genau das sieht der Nutzer:
    /// die Leiste ist weg, die Buehne bleibt schmal, der Cursor steht falsch,
    /// bis ein Zug am Fensterrand alles neu legt. Dieselbe Eigenheit steht seit
    /// dem 06.09. am Inspektor (`blattSetzen`).
    ///
    /// Hier wird deshalb ZUGEWIESEN statt umgedreht, und der neue Wert kommt
    /// aus der echten Eigenschaft.
    override func toggleSidebar(_ sender: Any?) {
        guard let seite = splitViewItems.first else { return }
        let neu = !seite.isCollapsed
        if animiert { seite.animator().isCollapsed = neu } else { seite.isCollapsed = neu }
        aufUmschalten?()
    }
}

/// DAS HAUPTFENSTER EINER PRUEFUNG DARF GROESSER SEIN ALS DER BILDSCHIRM (16.09.2026).
/// AppKit kuerzt einen Rahmen sonst auf den sichtbaren Bildschirm -- gemessen: `fenster
/// 1728x1080` wurde auf einem 14-Zoll-Bildschirm zu 1728x908. Die Vorschaubilder
/// (publish/tools/vorschau-mac.sh) zeigen die Werkbank in der Groesse eines Menschen an
/// einem grossen Bildschirm. Ausserhalb einer Pruefung (kopflos, ohne Fokus) bleibt das
/// gewohnte Verhalten.
final class Hauptfenster: NSWindow {
    var groesserAlsBildschirm = false

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        groesserAlsBildschirm ? frameRect : super.constrainFrameRect(frameRect, to: screen)
    }
}
