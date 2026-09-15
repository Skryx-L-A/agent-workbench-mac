// Die Seitenleiste: der Sitzungsbaum (Auftrag 2.1, mac/PLAN.md).
//
//   Projekt (Abschnittskopf, auf- und zuklappbar: Name, Zahl der Sitzungen,
//            Wartepunkt, wenn eine wartet; der Ordner steht im Hilfeschildchen)
//     Sitzung   Zustand als PUNKT UND Farbe UND Wort (Zustandspunkt.swift,
//               Politur 08.09.), Zusatzzeile (Worker-Zahl, Zustand, Maschine
//               nur, wenn fremd), Abzeichen mit den offenen Freigaben,
//               Kontextmenue
//
// KEINE WORKER UND KEINE SUBAGENTEN ALS ZEILEN (Vorgabe des Nutzers vom 03.09.,
// bestaetigt am 06.09. fuer den Mantel): mit ihnen war die Leiste „viel zu
// voll". Die Worker bleiben im Modell und in `awbmac-ctl ui` (je Sitzung
// `worker`), und `klick worker:<pane>` fuehrt weiter zu ihrem Pane -- Auftrag
// 2.2 baut daraus die Pille „N laufen" mit aufklappbarer Worker-Liste im Kopf,
// wie in der Electron-Fassung. Die Zeilen-Views WorkerZeile und SubagentZeile
// stehen unten bereit dafuer.
//
// Inhalt und Zeilenbau folgen der linken Leiste der Electron-Fassung
// (app/src/renderer/renderer.ts: `orchZeile`, `zusatzzeile`, `workerZeile`,
// `zustandText`, `tokenKurz`); die Form ist die Mac-Seitenleiste
// (apple-native-design, plattformen.md: `List` im `.sidebar`-Stil, Abschnitte,
// Auf-/Zuklappen). Reihenfolge und Filter (`ui.sort`, `order`, `showStopped`)
// rechnet der KERN -- `sessions` kommt sortiert und gefiltert an, die Leiste
// zeichnet, was sie bekommt. Was gewaehlt ist, sagt der Kern (`selected`).
//
// Textstile statt Punktgroessen, Systemfarben statt Hexwerte, SF Symbols
// statt Emojis: die Zeilen wachsen mit der Schriftgroesse des Systems. Die
// beiden Zeilenhoehen stehen in `Leistenmasse` (32 fuer eine Sitzung -- die
// Untergrenze der Plattform --, 24 fuer einen Projektkopf) und gelten als
// Untergrenze, nicht als feste Hoehe.
//
// VON HAND GEZOGENE REIHENFOLGE (08.09.2026, zweite Runde): Projekte lassen
// sich untereinander verschieben, Zeilen innerhalb ihres Projekts. Beides
// merkt sich der KERN (uistate.ts `projektReihenfolge` und `order`), damit die
// Electron-Fassung dieselbe Reihenfolge zeichnet; die Leiste schickt nur, was
// gezogen wurde. Wer keine Maus benutzt, findet dieselben zwei Zuege im
// Kontextmenue („Nach oben", „Nach unten").
import AppKit
import SwiftUI
import WerkbankProtokoll

/// Was die Leiste ausloesen kann -- das Fenster fuehrt es aus.
@MainActor
protocol Sitzungshandlungen: AnyObject {
    /// Ein Punkt des Kontextmenues (fortsetzen, umbenennen, ordner-zeigen, schliessen, loeschen).
    func menuePunkt(_ sitzungsId: String, _ punkt: String)
    /// Ein Worker-Pane auf die Buehne.
    func workerZeigen(sitzung: String, pane: String)
    /// Eine Chat-Sitzung auf die Buehne (Auftrag 3.2; echt nur aus dem sichtbaren Fenster).
    func chatZeigen(_ id: String)
    /// Eine Zeile VOR eine andere Zeile DESSELBEN Projekts ziehen.
    func zeileZiehen(_ gezogen: String, auf ziel: String)
    /// Ein ganzes Projekt vor ein anderes ziehen.
    func projektZiehen(_ gezogen: String, auf ziel: String)
    /// Eine Zeile um einen Platz nach oben oder unten -- der Weg ohne Maus.
    func zeileSchieben(_ kennung: String, hoch: Bool)
    /// Ein Projekt um einen Platz nach oben oder unten.
    func projektSchieben(_ dir: String, hoch: Bool)
    /// Ein Projekt auf- oder zuklappen (der Klick auf den ganzen Kopf).
    func projektKlappen(_ dir: String, offen: Bool)
    /// EINE NEUE SITZUNG (08.09.2026, Nachtrag des Nutzers). Mit leerem `ordner`
    /// fragt das Fenster erst den Ordner (NSOpenPanel); mit einem Ordner startet
    /// sie ohne Dialog dort. Beides geht denselben Weg in den Kern
    /// (`awb:sitz-neu`), also mit dem Orchestrator aus den Einstellungen.
    func neueSitzung(ordner: String, echt: Bool)
}

/// Die fuenf Punkte des Kontextmenues -- dieselben Kennungen wie
/// `menueVorlage` in main.ts, damit der Kern sie ausfuehrt.
struct MenuePunkt: Identifiable, Sendable {
    let id: String
    let titel: String
    let symbol: String
    let rueckfrage: Bool
    static let alle: [MenuePunkt] = [
        MenuePunkt(id: "fortsetzen", titel: "Fortsetzen", symbol: "play", rueckfrage: false),
        MenuePunkt(id: "umbenennen", titel: "Namen ändern …", symbol: "pencil", rueckfrage: false),
        MenuePunkt(id: "ordner-zeigen", titel: "Ordner im Finder zeigen", symbol: "folder", rueckfrage: false),
        MenuePunkt(id: "schliessen", titel: "Sitzung schließen", symbol: "xmark.circle", rueckfrage: false),
        MenuePunkt(id: "loeschen", titel: "Endgültig löschen …", symbol: "trash", rueckfrage: true),
    ]
    /// Die Punkte einer Chat-Sitzung (main.ts `menueVorlage` fuer `art: 'chat'`):
    /// kein Fortsetzen, kein Ordner im Finder -- Umbenennen, Schliessen, Loeschen.
    static let chat: [MenuePunkt] = alle.filter { ["umbenennen", "schliessen", "loeschen"].contains($0.id) }
}

/// DIE ZAHLEN DER LEISTE (08.09.2026, zweite Runde nach Befund des Nutzers „sie
/// sind zu gross und aufdringlich").
///
/// Massstab ist die Systemseitenleiste, nicht mehr die Electron-Fassung.
///
/// DIE SITZUNGSZEILE STEHT BEI 32 pt, UND DAS IST DER ANSCHLAG DER PLATTFORM
/// (08.09.2026, dritte Runde nach Befund des Nutzers „die Session-Liste links hat
/// noch zu grosse Flaechen pro Session, die muessen duenner werden").
///
/// Gemessen wurde diesmal nicht die Zahl, sondern der ANSCHLAG -- auf fuenf
/// Wegen, alle am Sichtbaum der laufenden App (`awbmac-ctl ui`,
/// `seitenleisteZeilenhoehen` liest die NSTableRowViews):
///
///   1. `.environment(\.defaultMinListRowHeight, 24)` an der Liste: ohne
///      Wirkung. Auch mit 60 blieb jede Zeile bei 32 -- der Seitenleistenstil
///      liest diese Umgebung gar nicht.
///   2. Dieselbe Umgebung an der ZEILE statt an der Liste: ebenfalls 32.
///   3. `.listRowInsets` an der Zeile, auch mit negativem Rand (-4 oben und
///      unten): ohne Wirkung, 32.
///   4. `.controlSize(.small)`: ohne Wirkung, 32.
///   5. Der Inhalt ist gleichgueltig: eine Zeile, die nur `Text("x")` mit
///      einer Mindesthoehe von 1 pt enthaelt, misst ebenfalls 32. Es ist
///      also ein Anschlag, keine Summe aus Inhalt und Rand.
///
/// Woher er kommt, sagt die Tabelle darunter: SwiftUI baut fuer die Liste eine
/// `SwiftUIOutlineListView` mit `rowSizeStyle = .medium` und `rowHeight = 32`.
/// Diese Tabelle von aussen umzustellen bricht die App -- der Versuch
/// (`rowSizeStyle = .small`, `rowHeight = 24`) endete zweimal in einem
/// Abbruch in SwiftUIs Attributgraph („AG::precondition_failure" im Layout).
///
/// UNTER 32 GEHT ES NUR OHNE DEN SEITENLEISTENSTIL: mit `.listStyle(.plain)`
/// oder `.inset` UND ohne `Section` misst dieselbe Zeile 24 pt, und die
/// Umgebung aus Punkt 1 wirkt dort auch. Das kostet aber genau das, was eine
/// Mac-Seitenleiste ausmacht und was hier zweimal ausdruecklich bestellt war:
/// die runde Auswahlflaeche der Plattform, den Einzug der Zeilen und die
/// Abschnittskoepfe, an denen die Projekte zuklappen (Befund vom 08.09.:
/// „ich kann die sessions nicht mehr in ihren projektordnern einklappen").
/// Deshalb bleibt der Seitenleistenstil, und die Sitzungszeile bleibt bei 32.
/// Der Vergleich beider Fassungen am echten Fenster liegt im Ergebnisbericht.
///
/// WAS DAFUER DUENNER WIRD: der PROJEKTKOPF. Ein Abschnittskopf ist keine
/// gewoehnliche Listenzeile und kennt den Anschlag nicht -- er folgt der Zahl,
/// die er bekommt, und steht jetzt auf 24 statt 32 (gemessen: die drei Koepfe
/// der Pruefleiste messen 24, die vier Sitzungszeilen 32).
///
/// WOHER DIE 24 KOMMEN: Auf macOS ist Body 13 pt bei 16 pt Zeilenhoehe (HIG
/// „Typography", reference/zahlen.md, „Text: Groessen"). Vier Punkte Luft oben
/// und unten ergeben 24 -- und 24 liegt ueber Apples Mindestgroesse fuer ein
/// Bedienelement auf macOS (20 x 20 pt, Vorgabegroesse 28 x 28; HIG
/// „Accessibility", Abschnitt Mobility, reference/zahlen.md).
///
/// DASS DIE ZWEITZEILE IN DIE ERSTE ZIEHT, IST DIE FOLGE DAVON, keine eigene
/// Entscheidung: macOS setzt Body auf 13 pt bei 16 pt Zeilenhoehe und
/// Caption 2 auf 10/13 (zahlen.md, „Text: Groessen"). Zwei Zeilen sind damit
/// 29 pt hoch, und eine Listenzeile legt Rand darauf -- zweizeilig blieb die
/// Sitzung bei 44 stehen und war genau das, was der Nutzer als aufdringlich
/// beanstandet hat. Die Systemseitenleiste (Finder, Mail) ist einzeilig.
/// Verloren geht dabei nichts: der Zusatz steht rechts in derselben Zeile, und
/// vollstaendig weiter im Hilfeschildchen und im Barrierefreiheitsbaum.
enum Leistenmasse {
    /// Hoehe einer Sitzungs- oder Gespraechszeile: der Anschlag der Liste.
    static let zeile: CGFloat = 32
    /// DIE AUSWAHLFLAECHE IN DIESER ZEILE (08.09.2026, Entscheidung des Nutzers
    /// „32 pt behalten, optisch schlanker"). Die Zeile bleibt 32 Punkte hoch --
    /// tiefer laesst die Plattform sie nicht --, aber was darin steht und was
    /// bei der Auswahl hinterlegt wird, ist schmaler: 22 Punkte, also Callout
    /// (12 pt bei 15 pt Zeilenhoehe, HIG „Typography", reference/zahlen.md)
    /// plus dreieinhalb Punkte Luft oben und unten. Die Systemseitenleiste des
    /// Finders steht auf derselben Marke. Fuenf Punkte oben und unten bleiben
    /// als Abstand zur naechsten Zeile -- die Zeilen liegen dadurch weiter
    /// auseinander, obwohl sie gleich hoch sind, und genau das macht die Leiste
    /// ruhiger.
    static let inhalt: CGFloat = 22
    /// Hoehe eines Projektkopfes. Anders als die Sitzungszeile darf er unter
    /// den Anschlag der Liste (siehe oben) und steht auf derselben schlanken
    /// Marke wie die Auswahlflaeche.
    static let kopf: CGFloat = 22
    /// Der Zustandspunkt in der Leiste: sechs statt acht Punkte, und mit ihm
    /// schrumpfen Ring und Hof im selben Verhaeltnis (Zustandspunkt.swift).
    static let punkt: CGFloat = 6
}

/// DIE AUSWAHLFLAECHE GEHOERT DER PLATTFORM (08.09.2026, gemessen am echten
/// Fenster).
///
/// Entscheidung des Nutzers lautete „32 pt behalten, optisch schlanker", und der
/// naheliegende Weg dahin waere ein eigener Auswahlhintergrund gewesen:
/// `listRowBackground` mit einem abgerundeten Rechteck, so hoch wie der Inhalt.
/// Der Weg ist gebaut und wieder ausgebaut worden, weil er nichts bewirkt: Die
/// Liste im Seitenleistenstil zeichnet ihre eigene Auswahl UEBER den
/// Zeilenhintergrund, und sie fuellt die ganze Zeile.
///
/// Der Beweis ist ein Bild: mit einem knallroten Hintergrund als Probe blieb
/// die gezeichnete Flaeche im Belegbild grau (220, 220, 220) und 64 Bildpunkte
/// hoch -- bei zweifacher Aufloesung also glatte 32 Punkte, die volle
/// Zeilenhoehe. Dasselbe mit `listRowInsets` (5 oben und unten): unveraendert
/// 32. Damit sind alle drei Stellschrauben, die eine Zeile in SwiftUI schlanker
/// machen koennten, an diesem Listenstil ohne Wirkung -- die dritte,
/// `defaultMinListRowHeight`, steht schon oben.
///
/// SCHLANKER GEWORDEN IST DESHALB, WAS UNS GEHOERT: der Inhalt der Zeile misst
/// 22 statt 24 Punkte, der Projektkopf 22 statt 24, der Name steht in Callout
/// statt Body und der Zusatz in Caption 2 statt Caption. Was bliebe, um auch
/// die gezeichnete Flaeche zu verkleinern, steht im Ergebnisbericht: die
/// Auswahl der Liste abschalten und selbst zeichnen -- zum Preis der
/// Tastaturbedienung der Leiste.

/// DER KONTRAST DES PROJEKTNAMENS, GERECHNET STATT BEHAUPTET (08.09.2026)./// DER KONTRAST DES PROJEKTNAMENS, GERECHNET STATT BEHAUPTET (08.09.2026).
///
/// Apple verlangt fuer Text unter 18 pt ein Kontrastverhaeltnis von 4,5:1
/// (HIG „Accessibility", Abschnitt Vision; reference/zahlen.md, „Text:
/// Kontrast"). Die Rechnung dahinter ist die relative Leuchtdichte aus WCAG
/// 2.1 -- dieselbe, auf die Apple sich beruft.
///
/// Gerechnet wird gegen den Grund, den auch das Belegbild der Leiste zeichnet
/// (`windowBackgroundColor`, SeitenleisteBeleg). Die Sekundaerfarbe steht
/// daneben, damit im Bericht nachzulesen ist, warum sie fuer eine Ueberschrift
/// nicht reicht: sie ist eine halbdurchsichtige Tinte und wird deshalb vor der
/// Rechnung ueber den Grund gelegt.
@MainActor
enum Leistenkontrast {
    /// Eine Farbe im wirksamen Erscheinungsbild, in sRGB, ueber den Grund gelegt.
    private static func aufGrund(_ farbe: NSColor, grund: NSColor) -> (r: Double, g: Double, b: Double) {
        guard let f = farbe.usingColorSpace(.sRGB), let g = grund.usingColorSpace(.sRGB) else { return (0, 0, 0) }
        let a = Double(f.alphaComponent)
        return (Double(f.redComponent) * a + Double(g.redComponent) * (1 - a),
                Double(f.greenComponent) * a + Double(g.greenComponent) * (1 - a),
                Double(f.blueComponent) * a + Double(g.blueComponent) * (1 - a))
    }

    /// Die relative Leuchtdichte nach WCAG 2.1.
    private static func leuchtdichte(_ c: (r: Double, g: Double, b: Double)) -> Double {
        func kanal(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * kanal(c.r) + 0.7152 * kanal(c.g) + 0.0722 * kanal(c.b)
    }

    static func verhaeltnis(_ vorne: NSColor, auf grund: NSColor) -> Double {
        let a = leuchtdichte(aufGrund(vorne, grund: grund))
        let b = leuchtdichte(aufGrund(grund, grund: grund))
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// Was `awbmac-ctl ui` meldet: der Kontrast der Primaerfarbe (die der
    /// Projektname jetzt traegt) und der der Sekundaerfarbe (die er trug).
    static func auskunft(dunkel: Bool) -> [String: Any] {
        var primaer = 0.0
        var sekundaer = 0.0
        let bild = NSAppearance(named: dunkel ? .darkAqua : .aqua) ?? NSAppearance.currentDrawing()
        bild.performAsCurrentDrawingAppearance {
            let grund = NSColor.windowBackgroundColor
            primaer = verhaeltnis(.labelColor, auf: grund)
            sekundaer = verhaeltnis(.secondaryLabelColor, auf: grund)
        }
        // Zwei Nachkommastellen: mehr Genauigkeit taeuscht eine vor, die die
        // Farben des Systems gar nicht haben.
        return ["projektname": (primaer * 100).rounded() / 100,
                "sekundaer": (sekundaer * 100).rounded() / 100,
                "gefordert": 4.5]
    }
}

/// EINE KENNUNG, DIE AUCH IM SICHTBAUM STEHT (08.09.2026).
///
/// `accessibilityIdentifier` in SwiftUI setzt die Kennung am
/// Barrierefreiheits-Element, nicht an der AppKit-Ansicht darunter -- eine
/// Pruefung, die den Sichtbaum abgeht (und nur dort steht die Deckkraft), fand
/// den Knopf deshalb nicht. Diese leere Ansicht liegt hinter dem Knopf, traegt
/// dieselbe Kennung an der Ansicht und teilt seine Groesse und seine Deckkraft.
struct Kennmarke: NSViewRepresentable {
    let kennung: String

    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: .zero)
        v.setAccessibilityIdentifier(kennung)
        return v
    }

    func updateNSView(_ v: NSView, context: Context) { v.setAccessibilityIdentifier(kennung) }
}

struct Seitenleiste: View {
    let kern: KernVerbindung
    unowned let handlungen: Sitzungshandlungen
    // Der Statusfuss (Auftrag 2.5): Maschinenkarten und Fusszeile UNTER der
    // Liste, in derselben Spalte -- Ort des Nutzers vom 05.09. (Statusfuss.swift).
    let oberflaeche: Oberflaeche
    unowned let fuss: Fusshandlungen
    var kopflos = false

    var body: some View {
        VStack(spacing: 0) {
            kopfzeile
            Divider()
            liste
            Divider()
            Statusfuss(kern: kern, oberflaeche: oberflaeche, handlungen: fuss, kopflos: kopflos)
        }
    }

    /// DIE KOPFZEILE UEBER DER LISTE (08.09.2026, Nachtrag des Nutzers „einen oben
    /// ueber den Sessions, mit dem ich eine Session in einem Projektordner
    /// starte, der noch nicht in der Workbench geoeffnet ist"). Dieselbe Zeile
    /// wie in der Electron-Fassung („Projekte" und ein Plus rechts,
    /// renderer.ts `leiste-kopf`).
    private var kopfzeile: some View {
        HStack {
            Text("Projekte")
                .font(.headline)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                handlungen.neueSitzung(ordner: "", echt: true)
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .background(Kennmarke(kennung: "neu-ordner"))
            .help("Neue Sitzung in einem Ordner, der noch nicht offen ist")
            .accessibilityIdentifier("neu-ordner")
            .accessibilityLabel("Neue Sitzung in einem Ordner")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var liste: some View {
        List(selection: auswahl) {
            ForEach(kern.modell.projekte) { p in
                // ZU- UND AUFKLAPPBAR (Befund des Nutzers vom 08.09.: „ich kann
                // die sessions nicht mehr in ihren projektordnern einklappen").
                // `Section(isExpanded:)` bringt das Chevron der Plattform mit;
                // die Wahl liegt in der Oberflaeche und ueberlebt den Neustart.
                Section(isExpanded: offen(p)) {
                    ForEach(p.zeilen) { z in
                        zeile(z, in: p)
                            // ZIEHEN UND ABLEGEN (08.09.2026). `draggable`
                            // traegt die Kennung des Kerns, `dropDestination`
                            // nimmt sie entgegen; welche Zuege ueberhaupt
                            // erlaubt sind, entscheidet das Fenster (eine Zeile
                            // bleibt in ihrem Projekt, der Ordner bestimmt es).
                            .draggable(z.kennung)
                            .dropDestination(for: String.self) { fracht, _ in
                                guard let gezogen = fracht.first, gezogen != z.kennung else { return false }
                                handlungen.zeileZiehen(gezogen, auf: z.kennung)
                                return true
                            }
                    }
                } header: {
                    ProjektKopf(projekt: p, offen: !oberflaeche.zugeklappteProjekte.contains(p.id),
                                klappen: { handlungen.projektKlappen(p.id, offen: oberflaeche.zugeklappteProjekte.contains(p.id)) },
                                neueSitzung: { handlungen.neueSitzung(ordner: p.dir, echt: true) })
                        .contextMenu {
                            let alle = kern.modell.projekte
                            let i = alle.firstIndex { $0.id == p.id } ?? 0
                            ProjektKontextmenue(projekt: p, handlungen: handlungen,
                                                offen: !oberflaeche.zugeklappteProjekte.contains(p.id),
                                                hoch: i > 0, runter: i + 1 < alle.count)
                        }
                        .draggable(p.dir)
                        .dropDestination(for: String.self) { fracht, _ in
                            guard let gezogen = fracht.first, gezogen != p.dir else { return false }
                            handlungen.projektZiehen(gezogen, auf: p.dir)
                            return true
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if kern.modell.sessions.isEmpty {
                ContentUnavailableView(
                    "Keine Sitzungen",
                    systemImage: "rectangle.stack",
                    description: Text(leerText)
                )
            }
        }
        .accessibilityIdentifier("seitenleiste")
    }

    /// Eine Zeile der Leiste, mit Auswahlmarke und Kontextmenue. Das Projekt
    /// reist mit, weil das Menue wissen muss, ob es ueber oder unter dieser
    /// Zeile ueberhaupt noch eine gibt -- ein Punkt, der nichts tut, gehoert
    /// nicht in ein Menue.
    @ViewBuilder
    private func zeile(_ z: ModellNutzlast.Projekt.Zeile, in p: ModellNutzlast.Projekt) -> some View {
        let i = p.zeilen.firstIndex { $0.id == z.id } ?? 0
        let hoch = i > 0
        let runter = i + 1 < p.zeilen.count
        switch z {
        case .sitzung(let s):
            SitzungsZeile(sitzung: s, eigene: kern.modell.machine)
                .tag(s.id)
                .contextMenu { Kontextmenue(sitzung: s, handlungen: handlungen, hoch: hoch, runter: runter) }
        case .chat(let c):
            ChatZeile(chat: c)
                .tag(z.id)
                .contextMenu { ChatKontextmenue(chat: c, handlungen: handlungen, hoch: hoch, runter: runter) }
        }
    }

    private var leerText: String {
        if !kern.verbunden { return "Der Kern ist nicht verbunden. Die App verbindet sich weiter im Sekundentakt." }
        if kern.modell.all > 0 {
            return "Alle \(kern.modell.all) Sitzungen sind beendet. Darstellung, „Beendete Sitzungen einblenden“ zeigt sie."
        }
        return "Der Kern meldet keine laufende Sitzung. Eine neue Sitzung entsteht über Ablage, Neue Sitzung."
    }

    /// Ob ein Projekt aufgeklappt ist. Gemerkt wird das ZUGEKLAPPTE: ein
    /// Projekt, das die Werkbank noch nie gesehen hat, geht damit offen auf.
    private func offen(_ p: ModellNutzlast.Projekt) -> Binding<Bool> {
        Binding(
            get: { !oberflaeche.zugeklappteProjekte.contains(p.id) },
            set: { neu in oberflaeche.projektKlappen(p.id, offen: neu) }
        )
    }

    /// Gewaehlt heisst: das siehst Du gerade (renderer.ts `buehneZeigt`, Befund 6
    /// vom 04.09.): liegt ein Gespraech oder sein Worker auf der Buehne, ist
    /// seine Zeile die eine hervorgehobene, sonst die gewaehlte Terminal-Sitzung.
    private var auswahl: Binding<String?> {
        Binding(
            get: {
                let m = kern.modell
                if let c = m.gezeigterChat { return "chat:" + c.id }
                return m.selected.isEmpty ? nil : m.selected
            },
            set: { neu in
                guard let id = neu else { return }
                if id.hasPrefix("chat:") {
                    let chatId = String(id.dropFirst(5))
                    if chatId != kern.modell.chatGezeigt { handlungen.chatZeigen(chatId) }
                } else if id != kern.modell.selected || kern.modell.gezeigterChat != nil {
                    kern.waehlen(id)
                }
            }
        )
    }

}

/// Der Abschnittskopf eines Projekts: Name, Ordnerkurzpfad, Zahl der Sitzungen, Wartende.
///
/// EINGEKLAPPT SAGT ER DASSELBE (Auftrag vom 08.09.): Zahl der Sitzungen und
/// der wartende Punkt stehen auch dann da, wenn keine Zeile darunter mehr
/// sichtbar ist -- sonst waere ein zugeklapptes Projekt ein blinder Fleck.
struct ProjektKopf: View {
    let projekt: ModellNutzlast.Projekt
    /// Nur fuer das Wort im Barrierefreiheitsbaum: das Chevron zeichnet die Section.
    var offen = true
    /// DER GANZE KOPF KLAPPT (08.09.2026, Befund des Nutzers: „wenn man auf den
    /// Projektordner drückt will ich auch dass sie einklappen, nicht nur die
    /// Pfeile rechts"). Der Beleg ausserhalb des Bildschirms zeichnet dieselbe
    /// Ansicht ohne Bedienung -- deshalb eine Vorgabe, die nichts tut.
    var klappen: () -> Void = {}

    /// Was der Plusknopf tut -- gesetzt vom Fenster, damit der Beleg ausserhalb
    /// des Bildschirms denselben Kopf ohne Bedienung zeichnen kann.
    var neueSitzung: () -> Void = {}

    @ScaledMetric(relativeTo: .callout) private var kopfhoehe: CGFloat = Leistenmasse.kopf
    /// Steht der Zeiger auf dieser Kopfzeile? Dann tritt das Plus hervor.
    @State private var zeigen = false
    @FocusState private var fokus: Bool

    var body: some View {
        // EINE ZEILE, kein Ordnerpfad darunter (Politur 08.09.). Die zweite
        // Zeile stand in jedem Abschnittskopf und machte die Leiste schwer;
        // die Electron-Fassung, der Massstab, hat sie nie gehabt
        // (renderer.ts `projekt-zeile`: Pfeil, Symbol, Name, Merker, Zahl).
        // Der Ordner steht weiter im Hilfeschildchen und in `ui`.
        HStack(alignment: .firstTextBaseline) {
            // GUT ZU SEHEN (08.09.2026, Befund des Nutzers: „Die Namen der
            // Projektordner sind ausgegraut, die sollten auch gut zu sehen
            // sein"). Ein Abschnittskopf im Seitenleistenstil kommt von SwiftUI
            // in der Sekundaerfarbe; das ist Apples Ton fuer NACHRANGIGES, und
            // der Projektname ist die Ueberschrift der Gruppe. Also
            // Primaerfarbe und der Textstil Headline (macOS 13 pt, halbfett --
            // zahlen.md, „Text: Groessen"). Dass die Sekundaerfarbe hier zu
            // wenig Kontrast traegt, ist keine Geschmacksfrage: Apple verlangt
            // fuer Text unter 18 pt ein Verhaeltnis von 4,5:1 (zahlen.md,
            // „Text: Kontrast"), und `.secondary` ist eine halbdurchsichtige
            // Tinte, die auf dem Seitenleistengrund darunter bleibt.
            Text(projekt.projekt)
                // Callout halbfett statt Headline (08.09.2026, „optisch
                // schlanker"): 12 statt 13 Punkte, die Gruppe setzt sich
                // weiter durch das Gewicht ab, nicht durch die Groesse.
                .font(.callout.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if projekt.wartet > 0 {
                // Derselbe Punkt wie an der wartenden Sitzung, nur eine Ebene
                // hoeher (renderer.ts `.merker`).
                Zustandspunkt(art: .will, basis: Leistenmasse.punkt)
                    .accessibilityHidden(false)
                    .accessibilityLabel("\(projekt.wartet) warten auf Dich")
            }
            // ALLE ZEILEN, nicht nur die Terminal-Sitzungen (08.09.2026, am
            // Bild der Chat-Buehne gesehen): ein Projekt mit zwei Gespraechen
            // und keiner Terminal-Sitzung zeigte „0" ueber zwei sichtbaren
            // Zeilen. Die Electron-Fassung zaehlt hier `p.zeilen.length`
            // (renderer.ts `zeichneBaum`), und die Zahl soll sagen, wie viel
            // unter dem Kopf steht -- gerade dann, wenn er zugeklappt ist.
            Text("\(projekt.zeilen.count)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            // DAS PLUS AM PROJEKT (08.09.2026, Nachtrag des Nutzers „und einen in
            // jeder Leiste links, wo jeweils die Projektordner stehen (also zu
            // jedem einen), mit dem direkt eine Session mit Standard-
            // Orchestrator in diesem Projektordner gestartet wird").
            //
            // ES IST IMMER ZU SEHEN (Nachbesserung vom selben Tag: „der Nutzer
            // sieht das Plus am Projektkopf nicht"). Zwei Fehler steckten in der
            // ersten Fassung: das Plus war in Ruhe UNSICHTBAR (`opacity 0`), und
            // `onHover` hing am Knopf selbst -- an einer Flaeche also, die man
            // nicht sieht und kaum trifft. Beides ist weg: das Plus steht
            // dauerhaft da, in Ruhe gedaempft (tertiaer), unter dem Zeiger und
            // am Tastaturfokus in der Primaerfarbe. Das Ueberfahren meldet die
            // GANZE Kopfzeile (siehe `contentShape` und `onHover` unten).
            Button { neueSitzung() } label: {
                Image(systemName: "plus")
                    .foregroundStyle(zeigen || fokus ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
            }
            .buttonStyle(.borderless)
            .focusable()
            .focused($fokus)
            .background(Kennmarke(kennung: "projekt-neu"))
            .help("Neue Sitzung in \(projekt.projekt)")
            .accessibilityIdentifier("projekt-neu")
            .accessibilityLabel("Neue Sitzung in \(projekt.projekt)")
        }
        // Der Abschnittskopf bekommt die Zahl unverkuerzt: eine Kopfzeile der
        // Liste traegt keinen Einzug (gemessen 08.09.: Inhalt 24 ergab Zeile 24,
        // waehrend eine Sitzungszeile acht Punkte drauflegt).
        .frame(minHeight: kopfhoehe)
        // DIE GANZE ZEILE IST DAS ZIEL, nicht nur das Chevron rechts:
        // `contentShape` macht auch die Luft zwischen Name und Zahl
        // anklickbar. Das Chevron der Section bleibt daneben, und die
        // Tastaturwege (Darstellung, Projekt ein-/ausklappen) bleiben, wie sie
        // waren -- sie gehen ohnehin ueber dieselbe Stelle im Fenster.
        .contentShape(Rectangle())
        // Das Ueberfahren gilt der ganzen Kopfzeile, nicht dem Knopf darin:
        // seine Flaeche ist zwoelf Punkte breit, die Zeile ist die ganze Leiste.
        .onHover { zeigen = $0 }
        .onTapGesture(perform: klappen)
        .help("\(projekt.projekt)\n\(projekt.kurzpfad)")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Projekt \(projekt.projekt), \(projekt.kurzpfad), \(projekt.zeilen.count) Sitzungen, \(offen ? "aufgeklappt" : "eingeklappt")")
    }

    /// Was eine Listenzeile ueber ihren Inhalt hinaus belegt (oben und unten
    /// zusammen), gemessen am Sichtbaum: die 32 Punkte der Zeile abzueglich der
    /// 22, die der Inhalt bekommt. Die Zahl steht hier, weil eine Pruefung sie
    /// gegen die gemessene Auswahlflaeche halten koennen soll.
    static let zeileneinzug: CGFloat = Leistenmasse.zeile - Leistenmasse.inhalt
}

/// DIE BEIDEN ZUEGE OHNE MAUS (08.09.2026). Ziehen ist der Weg des Zeigers;
/// wer die Tastatur benutzt oder das Ziehen nicht treffen mag, findet dieselbe
/// Handlung hier. Die Punkte stehen nur da, wo sie etwas bewirken -- oben in
/// der Gruppe gibt es kein „Nach oben".
struct SchiebePunkte: View {
    let hoch: Bool
    let runter: Bool
    let schieben: (Bool) -> Void

    var body: some View {
        if hoch || runter {
            Divider()
            if hoch {
                Button { schieben(true) } label: { Label("Nach oben", systemImage: "arrow.up") }
            }
            if runter {
                Button { schieben(false) } label: { Label("Nach unten", systemImage: "arrow.down") }
            }
        }
    }
}

/// Das Kontextmenue der Sitzung: die fuenf Punkte, das Loeschen abgesetzt und rot.
struct Kontextmenue: View {
    let sitzung: SitzungsEintrag
    unowned let handlungen: Sitzungshandlungen
    var hoch = false
    var runter = false

    var body: some View {
        ForEach(MenuePunkt.alle.filter { !$0.rueckfrage }) { p in
            Button { handlungen.menuePunkt(sitzung.id, p.id) } label: { Label(p.titel, systemImage: p.symbol) }
        }
        SchiebePunkte(hoch: hoch, runter: runter) { handlungen.zeileSchieben(sitzung.id, hoch: $0) }
        Divider()
        ForEach(MenuePunkt.alle.filter { $0.rueckfrage }) { p in
            Button(role: .destructive) { handlungen.menuePunkt(sitzung.id, p.id) } label: { Label(p.titel, systemImage: p.symbol) }
        }
    }
}

/// Das Kontextmenue des Projektkopfes: auf- und zuklappen, und die beiden
/// Zuege, mit denen ein Projekt ohne Maus seinen Platz wechselt.
struct ProjektKontextmenue: View {
    let projekt: ModellNutzlast.Projekt
    unowned let handlungen: Sitzungshandlungen
    var offen = true
    var hoch = false
    var runter = false

    var body: some View {
        // Das Klappen steht hier auch dann, wenn es nichts zu schieben gibt --
        // ein Kontextmenue, das nur aus zwei manchmal fehlenden Punkten
        // bestuende, waere bei einem einzelnen Projekt leer.
        // Der Weg ohne Maus und ohne Ueberfahren zum Plus am Kopf.
        Button { handlungen.neueSitzung(ordner: projekt.dir, echt: true) } label: {
            Label("Neue Sitzung hier", systemImage: "plus")
        }
        Divider()
        Button { handlungen.projektKlappen(projekt.dir, offen: !offen) } label: {
            Label(offen ? "Einklappen" : "Ausklappen", systemImage: offen ? "chevron.right" : "chevron.down")
        }
        SchiebePunkte(hoch: hoch, runter: runter) { handlungen.projektSchieben(projekt.dir, hoch: $0) }
    }
}

/// Die Zeile einer Chat-Sitzung: Sprechblase als Symbol, Zustand als Farbe und
/// Wort, darunter die Worker-Zahl (renderer.ts `chatZeile`).
struct ChatZeile: View {
    let chat: ChatEintrag
    @ScaledMetric(relativeTo: .callout) private var inhaltshoehe: CGFloat = Leistenmasse.inhalt

    var body: some View {
        Label {
            // EINE ZEILE (08.09.2026, siehe `Leistenmasse`): der Name traegt
            // den Platz, der Zusatz steht rechts daneben und weicht zuerst.
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                // Dieselbe Aufteilung wie an der Sitzungszeile: der Name weicht
                // zuerst, das Zustandswort nie.
                Text(chat.name.isEmpty ? chat.projekt : chat.name)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
                Spacer(minLength: 4)
                if !chat.zusatzzeile.isEmpty {
                    Text(chat.zusatzzeile)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .layoutPriority(2)
                }
                Text(chat.laeuft ? "läuft" : "beendet")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(3)
            }
        } icon: {
            // Punkt UND Sprechblase, wie in der Electron-Fassung (renderer.ts
            // `chatZeile`): der Punkt sagt den Zustand, die Blase die Sorte.
            HStack(spacing: 5) {
                Zustandspunkt(art: chat.laeuft ? .laeuft : .ruhig, basis: Leistenmasse.punkt)
                Image(systemName: ChatZeile.symbol(laeuft: chat.laeuft))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: inhaltshoehe)
        .help("\(chat.name) · \(chat.ordner)\nGespräch, \(chat.laeuft ? "läuft" : "beendet")")
        .accessibilityLabel("Gespräch \(chat.name), \(chat.laeuft ? "läuft" : "beendet"), \(chat.zusatzzeile)")
    }

    /// Die Sorte der Zeile als Symbol -- der Zustand steht daneben als Punkt.
    static func symbol(laeuft: Bool) -> String { laeuft ? "bubble.left.fill" : "bubble.left" }

    static func punkt(laeuft: Bool) -> Punktart { laeuft ? .laeuft : .ruhig }
}

/// Das Kontextmenue einer Chat-Sitzung: Umbenennen, Schliessen, Loeschen.
struct ChatKontextmenue: View {
    let chat: ChatEintrag
    unowned let handlungen: Sitzungshandlungen
    var hoch = false
    var runter = false

    var body: some View {
        ForEach(MenuePunkt.chat.filter { !$0.rueckfrage }) { p in
            Button { handlungen.menuePunkt(chat.id, p.id) } label: { Label(p.titel, systemImage: p.symbol) }
        }
        SchiebePunkte(hoch: hoch, runter: runter) { handlungen.zeileSchieben(chat.id, hoch: $0) }
        Divider()
        ForEach(MenuePunkt.chat.filter { $0.rueckfrage }) { p in
            Button(role: .destructive) { handlungen.menuePunkt(chat.id, p.id) } label: { Label(p.titel, systemImage: p.symbol) }
        }
    }
}

struct SitzungsZeile: View {
    let sitzung: SitzungsEintrag
    let eigene: String
    /// Die Zeile misst 32 Punkte -- das ist der Anschlag der Liste, nicht unsere
    /// Wahl. Was DARIN steht und bei der Auswahl hinterlegt wird, sind 22
    /// (`Leistenmasse.inhalt`).
    @ScaledMetric(relativeTo: .callout) private var inhaltshoehe: CGFloat = Leistenmasse.inhalt

    var body: some View {
        Label {
            // EINE ZEILE statt zweier (siehe `Leistenmasse`): der Name hat
            // Vorrang, der Zusatz weicht zuerst und steht vollstaendig im
            // Hilfeschildchen und im Barrierefreiheitsbaum.
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                // WER ZUERST WEICHT (08.09.2026, Entscheidung des Nutzers): der
                // NAME. Er hat die niedrigste Priorität und kürzt hinten;
                // danach der vordere Teil des Zusatzes, der VORN kürzt
                // („… · pruefmaschine"); das Zustandswort weicht nie -- es ist
                // mit `fixedSize` festgenagelt und hat den Vorrang.
                Text(sitzung.name.isEmpty ? sitzung.projekt : sitzung.name)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
                Spacer(minLength: 4)
                let teile = sitzung.zusatzteile(eigene: eigene)
                if !teile.vorne.isEmpty {
                    Text(teile.vorne)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .layoutPriority(2)
                }
                Text(teile.zustand)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(3)
            }
        } icon: {
            Zustandspunkt(art: punkt, basis: Leistenmasse.punkt)
        }
        .frame(minHeight: inhaltshoehe)
        .badge(sitzung.pendingApprovals)
        .help(hilfe)
        .accessibilityLabel("\(sitzung.name), \(sitzung.zustandText), \(sitzung.zusatzzeile(eigene: eigene))"
                            + (sitzung.pendingApprovals > 0 ? ", \(sitzung.pendingApprovals) offene Freigaben" : ""))
    }

    private var hilfe: String {
        var teile = ["\(sitzung.name) · \(sitzung.machine) · \(sitzung.dir)", sitzung.zustandText]
        // Derselbe Satz wie das Hilfeschildchen der Electron-Fassung
        // (renderer.ts `el.title`, `sitzung.verloren`): der Zustand erklaert sich
        // dort, wo mehr Platz ist als in der Zusatzzeile.
        if sitzung.verloren { teile.append("lief noch, als dieses Fenster zuletzt hinsah") }
        if sitzung.pendingApprovals > 0 { teile.append("\(sitzung.pendingApprovals) offene Freigaben") }
        return teile.joined(separator: "\n")
    }

    // Zustand als Punkt UND Farbe UND Wort (abnahme.md, Merkmal 5): der Punkt
    // traegt Form und Farbe, das Wort steht in der Zusatzzeile, im
    // Hilfeschildchen und im Barrierefreiheitsbaum.
    static func punkt(fuer s: SitzungsEintrag) -> Punktart { Punktart.sitzung(s) }

    private var punkt: Punktart { Self.punkt(fuer: sitzung) }
}

/// Die Zeile eines Workers -- fuer die Worker-Liste im Kopf (Auftrag 2.2);
/// in der Seitenleiste steht sie nicht (siehe Kopf der Datei).
struct WorkerZeile: View {
    let worker: WorkerEintrag
    /// Auf Antrag eines lebenden Workers entstanden: eine Stufe tiefer.
    let kind: Bool
    /// So viele Worker sind auf seinen Antrag entstanden (`+n`).
    let kinder: Int
    /// Die Maschine, wenn es nicht diese hier ist -- die Worker-Liste im Kopf
    /// hat keinen Kopf, der sie sonst nennt (renderer.ts `workerlisteZeichnen`).
    var maschine: String = ""

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Zustandspunkt(art: Self.punkt(fuer: worker.state))
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(worker.name).lineLimit(1)
                    if kinder > 0 {
                        Text("+\(kinder)").font(.caption).foregroundStyle(.secondary)
                    }
                    if !worker.model.isEmpty {
                        Text(worker.model).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Text(unten).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if !worker.tokensKurz.isEmpty {
                Text(worker.tokensKurz).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .padding(.leading, kind ? 16 : 0)
        .help("\(worker.name)\(worker.model.isEmpty ? "" : " · \(worker.model)") — \(unten)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Worker \(worker.name), \(Self.wort(fuer: worker.state)), \(unten)")
        .accessibilityAddTraits(worker.paneId.isEmpty ? [] : .isButton)
    }

    /// Herkunft zuerst, dann was er tut -- wie `workerZeile` in renderer.ts.
    var unten: String {
        var teile: [String] = []
        if !maschine.isEmpty { teile.append(maschine) }
        if kind { teile.append("auf Antrag von \(worker.requestedBy)") }
        teile.append(worker.titel.isEmpty ? worker.zustandText : worker.titel)
        return teile.joined(separator: " · ")
    }

    static func punkt(fuer state: String) -> Punktart { Punktart.worker(state) }

    static func wort(fuer state: String) -> String {
        switch state {
        case "running": return "läuft"
        case "blocked": return "blockiert"
        case "stalled": return "hängt"
        case "done": return "fertig"
        case "unknown": return "nicht einsehbar"
        default: return state
        }
    }
}

struct SubagentZeile: View {
    let subagent: SubagentEintrag
    var elternlos = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.turn.down.right")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(subagent.anzeigename).lineLimit(1)
            if !subagent.type.isEmpty {
                Text(subagent.type).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
        }
        .padding(.leading, elternlos ? 0 : 16)
        .help(elternlos ? "Subagent ohne zuordenbaren Worker" : "Subagent")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Subagent \(subagent.anzeigename)\(elternlos ? ", ohne zuordenbaren Worker" : "")")
    }
}

/// Der Beleg der Seitenleiste fuer kopflose Bilder (Fenster.schuss): dieselben
/// Zeilen wie die Liste, als einfacher Stapel, weil die Liste ausserhalb des
/// Bildschirms nichts zeichnet. Keine Bedienung, nur Ansicht.
struct SeitenleisteBeleg: View {
    let modell: ModellNutzlast
    let breite: CGFloat
    let hoehe: CGFloat
    /// Der Fuss (Auftrag 2.5) als Beleg unter den Zeilen, mit offenem Feld.
    let kern: KernVerbindung
    let oberflaeche: Oberflaeche
    unowned let fuss: Fusshandlungen

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(modell.projekte) { p in
                let offen = !oberflaeche.zugeklappteProjekte.contains(p.id)
                // DERSELBE TON WIE IM FENSTER (08.09.2026): der Beleg trug
                // den Projektnamen bisher in der Sekundaerfarbe -- genau das,
                // was der Nutzer am Fenster beanstandet hat. Der Kopf bringt
                // seinen Stil jetzt selbst mit (Headline, Primaerfarbe).
                ProjektKopf(projekt: p, offen: offen)
                    .padding(.top, 8)
                ForEach(offen ? p.zeilen : []) { z in
                    HStack(spacing: 4) {
                        switch z {
                        case .sitzung(let s):
                            SitzungsZeile(sitzung: s, eigene: modell.machine)
                            Spacer()
                            if s.pendingApprovals > 0 {
                                Text("\(s.pendingApprovals)")
                                    .font(.caption).monospacedDigit()
                                    .padding(.horizontal, 6).padding(.vertical, 1)
                                    .background(Capsule().fill(.quaternary))
                                    .fixedSize()
                                    .layoutPriority(1)
                            }
                            if s.id == modell.selected, modell.gezeigterChat == nil {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        case .chat(let c):
                            ChatZeile(chat: c)
                            Spacer()
                            if c.id == modell.gezeigterChat?.id {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                    .padding(.leading, 8)
                    .padding(.vertical, 3)
                }
            }
            Spacer(minLength: 0)
            Divider()
            Statusfuss(kern: kern, oberflaeche: oberflaeche, handlungen: fuss, kopflos: true, beleg: true)
                .padding(.horizontal, -10)
        }
        .padding(.horizontal, 10)
        .frame(width: breite, height: hoehe, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
