// Eine Kachel der Buehne (Auftrag 2.3, mac/PLAN.md): oben die Kopfzeile mit
// Zustandspunkt, Name, Modell, Tokenstand und rechts Zoom- und Chat-Symbol,
// darunter das Terminal des Panes. Die Kopfzeile nimmt sich ihre Hoehe, sie
// leiht sie nicht: `Kachelung.terminalflaeche` zieht sie je Kachelzeile ab,
// BEVOR die Zellenzahl an den Kern geht -- so deckt sie keine Zelle zu
// (paneflaeche.ts, `KOPFHOEHE`, 03.09.).
//
// ZAHLEN (reference/zahlen.md, macOS): ein Steuerelement ist mindestens
// 20 x 20 pt gross; die Kopfzeile ist 24 pt hoch, damit die beiden Knoepfe mit
// 2 pt Luft darin stehen. Fuer eine Eckenrundung nennt Apple keine Zahl; die
// Kachel bekommt 8 pt, die Fuge dazwischen ist die des Renderers (4 pt,
// `Kachelung.fuge`). Textstile statt Punktgroessen, Systemfarben, der
// Fokusrahmen in der Systemakzentfarbe.
import AppKit
import SwiftUI
import WerkbankProtokoll

/// Was in der Kopfzeile eines Panes steht (paneflaeche.ts `PaneKopf`).
struct KachelKopfDaten: Equatable {
    var name = ""
    /// running | blocked | stalled | done | unknown | "" (kein Worker)
    var zustand = ""
    var modell = ""
    var tokens = ""
}

/// Die Kopfzeile einer Kachel.
struct KachelKopf: View {
    let daten: KachelKopfDaten
    let pane: String
    let aktiv: Bool
    let gezoomt: Bool
    let zoom: () -> Void
    let zurueck: () -> Void
    let fokus: () -> Void

    static let hoehe: CGFloat = 24

    var body: some View {
        HStack(spacing: 8) {
            Zustandspunkt(art: daten.zustand.isEmpty ? .ruhig : WorkerZeile.punkt(fuer: daten.zustand))
            Text(daten.name.isEmpty ? pane : daten.name)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(aktiv ? Color.accentColor : Color.primary)
                .lineLimit(1)
                .layoutPriority(2)
            if !daten.modell.isEmpty {
                Text(daten.modell)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            Spacer(minLength: 4)
            if !daten.tokens.isEmpty {
                Text(daten.tokens)
                    .font(.caption.monospaced())
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Button(action: gezoomt ? zurueck : zoom) {
                Image(systemName: gezoomt ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(.borderless)
            .frame(width: 20, height: 20)
            .help(gezoomt ? "Alle Kacheln zeigen (⌘↩)" : "Diese Kachel allein zeigen (⌘↩)")
            .accessibilityLabel(gezoomt ? "Alle Kacheln zeigen" : "Kachel vergrößern")
            Button(action: {}) {
                Image(systemName: "bubble.left")
            }
            .buttonStyle(.borderless)
            .frame(width: 20, height: 20)
            .disabled(true)
            .help("Als Gespräch zeigen – kommt mit der Chat-Bühne (Auftrag 3.2)")
            .accessibilityLabel("Als Gespräch zeigen, noch nicht verfügbar")
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .frame(height: Self.hoehe)
        .background(aktiv ? AnyShapeStyle(Color.accentColor.opacity(0.18)) : AnyShapeStyle(.quaternary))
        .contentShape(Rectangle())
        // Ein Klick auf die Kopfzeile holt den Fokus und zoomt die Kachel; ein
        // Doppelklick auf die gezoomte holt alle zurueck (Auftrag 2.3).
        .onTapGesture(count: 2) { if gezoomt { zurueck() } else { zoom() } }
        .onTapGesture(count: 1) { fokus(); if !gezoomt { zoom() } }
        .help([daten.name.isEmpty ? pane : daten.name, daten.modell, daten.tokens].filter { !$0.isEmpty }.joined(separator: " · "))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Kachel \(daten.name.isEmpty ? pane : daten.name)\(daten.zustand.isEmpty ? "" : ", \(WorkerZeile.wort(fuer: daten.zustand))")\(aktiv ? ", hat die Tastatur" : "")")
    }
}

/// Der Platzhalter einer Kachel, deren Pane es nicht (mehr) gibt.
struct KachelFehlt: View {
    let pane: String
    let grund: String

    var body: some View {
        ContentUnavailableView {
            Label(pane, systemImage: "rectangle.dashed")
        } description: {
            Text(grund)
        }
        .background(.background)
    }
}

/// Eine Kachel: Kopfzeile oben, Terminal (oder Platzhalter) darunter. Flipped,
/// damit y wie beim Renderer nach unten waechst.
@MainActor
final class Kachel: NSView {
    static let eckenradius: CGFloat = 8
    let pane: String
    let kopf: NSHostingView<KachelKopf>
    let terminal: StromTerminal?
    private var platzhalter: NSHostingView<KachelFehlt>?
    /// Die Groesse des Panes aus dem Kern -- das Terminal ist genau so gross.
    var cols = 0
    var rows = 0
    var fehltGrund: String?
    private(set) var daten = KachelKopfDaten()
    private(set) var aktiv = false
    private(set) var gezoomt = false
    /// Ob die Kopfzeile Platz hat (unter der doppelten Hoehe faellt sie weg).
    private(set) var kopfSichtbar = true

    override var isFlipped: Bool { true }

    /// NICHTS VERLAESST DIE KACHEL (08.09.2026). Gibt tmux einem Pane mehr
    /// Zeilen, als in die Kachel passen, wird die Ansicht nach oben geschoben,
    /// damit die UNTERSTE Zeile sichtbar bleibt (`anordnen`) -- ohne diesen
    /// Beschnitt zeichnete sie dabei ueber die Kopfzeile der Kachel hinweg.
    override var clipsToBounds: Bool {
        get { true }
        set { _ = newValue }
    }

    init(pane: String, terminal: StromTerminal?, zoom: @escaping (String) -> Void, zurueck: @escaping () -> Void, fokus: @escaping (String) -> Void) {
        self.pane = pane
        self.terminal = terminal
        kopf = NSHostingView(rootView: KachelKopf(daten: KachelKopfDaten(), pane: pane, aktiv: false, gezoomt: false,
                                                  zoom: { zoom(pane) }, zurueck: zurueck, fokus: { fokus(pane) }))
        kopf.sizingOptions = []
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = Self.eckenradius
        layer?.masksToBounds = true
        layer?.borderWidth = 0
        addSubview(kopf)
        if let t = terminal { addSubview(t) }
        kopf.setAccessibilityIdentifier("kachelkopf:\(pane)")
    }

    required init?(coder: NSCoder) { fatalError("nicht aus einem Nib") }

    func fehlt(_ grund: String) {
        fehltGrund = grund
        if platzhalter == nil {
            let p = NSHostingView(rootView: KachelFehlt(pane: pane, grund: grund))
            p.sizingOptions = []
            addSubview(p)
            platzhalter = p
        }
    }

    func nachziehen(daten neu: KachelKopfDaten, aktiv a: Bool, gezoomt z: Bool, mehrere: Bool) {
        if neu != daten || a != aktiv || z != gezoomt {
            daten = neu; aktiv = a; gezoomt = z
            var r = kopf.rootView
            r = KachelKopf(daten: neu, pane: pane, aktiv: a, gezoomt: z, zoom: r.zoom, zurueck: r.zurueck, fokus: r.fokus)
            kopf.rootView = r
            // Das Terminal selbst traegt den Namen seines Panes fuer VoiceOver.
            terminal?.setAccessibilityLabel("Terminal \(neu.name.isEmpty ? pane : neu.name)")
        }
        // Der Fokusrahmen in der Systemakzentfarbe -- nur, wo es mehr als eine
        // Kachel gibt; eine einzelne hat nichts, wovon sie sich abheben muesste.
        let rahmen = a && mehrere
        layer?.borderWidth = rahmen ? 2 : 0
        layer?.borderColor = rahmen ? NSColor.controlAccentColor.cgColor : nil
    }

    /// Kopf oben, Terminal darunter in Panegroesse; ist der Pane hoeher als die
    /// Kachel, wird das UNTERE Ende gezeigt (paneflaeche.ts, `ueberhang`).
    func anordnen(zelle: Kachelung.Zelle) {
        let b = bounds.width
        let h = bounds.height
        kopfSichtbar = h >= KachelKopf.hoehe * 2
        kopf.isHidden = !kopfSichtbar
        let kopfH: CGFloat = kopfSichtbar ? KachelKopf.hoehe : 0
        kopf.frame = NSRect(x: 0, y: 0, width: b, height: kopfH)
        if let p = platzhalter {
            p.frame = NSRect(x: 0, y: kopfH, width: b, height: max(0, h - kopfH))
        }
        guard let t = terminal else { return }
        // ERST DIE ZELLEN, DANN DER RAHMEN (08.09.2026, vierte Runde). Ein
        // Rahmenwechsel IST fuer SwiftTerm eine Groessenaenderung
        // (`setFrameSize` -> `processSizeChange`), und die bricht den Inhalt um.
        // Deshalb wird die Zellenzahl zuerst gestellt und der Rahmen danach aus
        // `getOptimalFrameSize()` genommen -- der Zahl, die SwiftTerm SELBST
        // fuer genau diese Zellen nennt. Damit rechnet es aus dem Rahmen
        // dieselbe Zahl zurueck, die schon dasteht, und der Wechsel bewegt
        // nichts mehr. Der Rollbalken bleibt dabei aus, sonst zoege er die
        // Rechnung um drei Spalten auseinander (siehe `rollbalkenAus`).
        t.rollbalkenAus()
        if cols > 0, rows > 0, t.getTerminal().cols != cols || t.getTerminal().rows != rows {
            t.resize(cols: cols, rows: rows)
        }
        let optimal = t.getOptimalFrameSize().size
        let tb = cols > 0 ? optimal.width : b
        let th = rows > 0 ? optimal.height : max(0, h - kopfH)
        let ueberhang = max(0, th - (h - kopfH))
        t.frame = NSRect(x: 0, y: kopfH - ueberhang, width: tb, height: th)
        // NACHHUT, NICHT MEHR DIE ERSTE HAND (08.09.2026). Gestellt wird die
        // Groesse seither dort, wo der Schirm hineinlaeuft
        // (TerminalBereich.swift, `einspielen`) -- vorher, nicht nachher, sonst
        // bricht das Stellen den eben gefuetterten Schirm um. Hier bleibt es
        // fuer den Weg ueber den Rahmen: aendert sich die Kachel, ohne dass eine
        // neue Lage kommt, ist das die einzige Stelle, die es merkt. Steht die
        // Groesse schon, tut diese Abfrage nichts.
    }

    override func layout() {
        super.layout()
        layer?.borderColor = aktiv && layer?.borderWidth ?? 0 > 0 ? NSColor.controlAccentColor.cgColor : nil
    }
}
