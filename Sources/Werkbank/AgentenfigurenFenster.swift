// DAS VORSCHAU-BLATT DER AGENTENFIGUREN (10.09.2026, Bau-Schritt 4) -- die
// Sichtpruefung fuer den Nutzer, bevor die Ansicht „Agents" die Figuren traegt
// (docs/AGENTS-PLAN.md, Abschnitt 9, Punkt 4: „Zuerst das Vorab-Blatt mit den
// Figuren aller Rollen der Bibliothek zur Abnahme").
//
// Es zeigt, was `docs/agentenfiguren.html` zeigt, nur mit dem SwiftUI-Zeichner:
// die zwei Einzelnen (Kern und Linse), jede Rolle der Bibliothek in BEIDEN
// Arten (Tier und Roboter -- die Art ist je Team umstellbar, also muss jede
// Rolle in beiden bestehen), alle Zustaende je Art, Instanz-Varianten derselben
// Rolle und die fuenf Groessen. Ein Schalter oben stellt alles auf Standbild,
// wie „Bewegung reduzieren" es tut.
//
// EIN EIGENES FENSTER, kein Blatt des Inspektors: ein Bericht zum Ansehen, wie
// die Verbrauchsseite (Verbrauchsfenster.swift). Dieselbe Auflage: `bauen()`
// baut ohne zu zeigen (der Weg des Steuerkanals), `zeigen()` ist der einzige
// Weg auf den Bildschirm und kopflos wirkungslos.
import AppKit
import SwiftUI

@MainActor
@Observable
final class FigurenVorschauZustand {
    var standbild = false
}

struct AgentenfigurenAnsicht: View {
    @Bindable var zustand: FigurenVorschauZustand
    /// Fuer Belegbilder: kein Rollbalken, das Blatt in voller Hoehe.
    var beleg = false

    static let zustaende: [FigurZustand] = [.arbeitet, .ungelesen, .entscheidung, .haengt, .fertig, .fern]
    static let unterzeilen: [FigurZustand: String] = [
        .arbeitet: "Augen lesen, Tastpunkte, Leuchte pulst",
        .ungelesen: "schaut dich an, Sprechblase mit Punkt",
        .entscheidung: "Kopf schief, ein Auge hoch, Fragezeichen",
        .haengt: "gekreuzte Augen, Schweißtropfen, Schwanken",
        .fertig: "schläft, „z“",
        .fern: "blass, gestrichelter Rahmen",
    ]
    /// Je Art ein Vertreter fuer die Zustandsreihe (wie im Blatt).
    static let artVertreter: [(titel: String, rolle: String, team: String, stufe: String, art: String)] = [
        ("Roboter", "junior-dev", "entwicklung", "mitglied", "roboter"),
        ("Tier", "recherche-laeufer", "recherche", "mitglied", "tier"),
        ("Hauptagent, der Kern", "hauptagent", "hauptagent", "hauptagent", "kern"),
        ("Reviewer, die Linse", "reviewer", "pruefung", "mitglied", "linse"),
    ]
    static let instanzen: [(titel: String, rolle: String, team: String, stufe: String, namen: [String])] = [
        ("Vier Recherche-Läufer", "recherche-laeufer", "recherche", "mitglied", ["agentsweb", "agentsscout", "quellen-3", "nachtlauf"]),
        ("Vier Junior-Devs", "junior-dev", "entwicklung", "mitglied", ["kal-2", "ui-fix", "tests-b", "parser"]),
        ("Drei Hauptagenten", "hauptagent", "hauptagent", "hauptagent", ["agents-plan", "npc-1", "myproject-kal"]),
        ("Drei Reviewer", "reviewer", "pruefung", "mitglied", ["plan-review", "rev-kal", "rev-npc"]),
    ]
    static let groessenRollen: [(rolle: String, team: String, stufe: String)] = [
        ("hauptagent", "hauptagent", "hauptagent"), ("senior-dev", "entwicklung", "mitglied"),
        ("quellenpruefer", "recherche", "mitglied"), ("reviewer", "pruefung", "mitglied"),
    ]

    /// Wie viele Figuren das Blatt zeichnet, je Abschnitt -- fuer die Auskunft.
    static var zaehlung: [String: Int] {
        let rollen = FigurBibliothek.teams.reduce(0) { $0 + $1.rollen.count }
        return [
            "einzelne": 6,
            "teams": rollen * 2,
            "zustaende": artVertreter.count * zustaende.count,
            "instanzen": instanzen.reduce(0) { $0 + $1.namen.count },
            "groessen": Agentenfigur.groessen.count * groessenRollen.count,
        ]
    }

    var body: some View {
        Group {
            if beleg {
                inhalt.frame(width: 1100, alignment: .topLeading)
            } else {
                ScrollView { inhalt.frame(maxWidth: 1100).frame(maxWidth: .infinity) }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.figurStandbild, zustand.standbild)
    }

    private var inhalt: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Agentenfiguren").font(.largeTitle.bold())
                Text("Jedes Team hat eine Farbe und eine Art: Entwicklung und Prüfung sind Roboter, Recherche und Gestaltung sind Tiere, je Team umstellbar in den Einstellungen. Der Hauptagent ist der Kern, der Reviewer die Linse. Jeder Zustand trägt ein Zeichen über dem Kopf und eine Leuchte, damit er auch still und klein lesbar ist.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if beleg {
                    // `ImageRenderer` zeichnet AppKit-Steuerelemente nicht -- im Bild steht das Wort.
                    Text(zustand.standbild ? "Standbild: an" : "Standbild: aus, die Figuren bewegen sich")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    Toggle("Standbild, wie bei „Bewegung reduzieren“", isOn: $zustand.standbild)
                        .toggleStyle(.switch)
                        .accessibilityIdentifier("figuren-standbild")
                }
            }
            karte("Die zwei Einzelnen") {
                HStack(alignment: .top, spacing: 36) {
                    einzelne(rolle: "hauptagent", team: "hauptagent", stufe: "hauptagent", titel: "Hauptagent: der Kern",
                             zustaende: [(.ruhig, "ruhig"), (.arbeitet, "arbeitet"), (.ungelesen, "Ergebnis")])
                    einzelne(rolle: "reviewer", team: "pruefung", stufe: "mitglied", titel: "Reviewer: die Linse",
                             zustaende: [(.ruhig, "ruhig"), (.arbeitet, "prüft"), (.entscheidung, "Frage")])
                }
            }
            karte("Die Teams, jede Rolle in beiden Arten") {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(FigurBibliothek.teams, id: \.schluessel) { t in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 3).fill(rgb(FigurBibliothek.farbe(team: t.schluessel, art: .roboter)))
                                    .frame(width: 10, height: 10).accessibilityHidden(true)
                                Text(t.name).font(.headline)
                                Text("Vorgabe: \(FigurBibliothek.artVorgabe[t.schluessel] == "tier" ? "Tier" : "Roboter")").foregroundStyle(.secondary)
                            }
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 12)], alignment: .leading, spacing: 10) {
                                ForEach(t.rollen, id: \.rolle) { r in rolle(r, team: t.schluessel) }
                            }
                        }
                    }
                }
            }
            karte("Zustände je Art") {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Self.artVertreter, id: \.titel) { v in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(v.titel).font(.headline)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], alignment: .center, spacing: 12) {
                                ForEach(Self.zustaende, id: \.self) { z in
                                    VStack(spacing: 4) {
                                        Agentenfigur(rolle: v.rolle, stufe: v.stufe, name: nil, team: v.team, zustand: z, groesse: 64, arten: [v.team: v.art])
                                        Text(z.wort).font(.callout.weight(.medium))
                                        Text(Self.unterzeilen[z] ?? "").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                                    }
                                    .accessibilityElement(children: .combine)
                                    .accessibilityLabel("\(v.titel), \(z.wort)")
                                }
                            }
                        }
                    }
                }
            }
            karte("Gleiche Rolle, nie dieselbe Figur") {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Self.instanzen, id: \.titel) { i in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(i.titel).font(.headline)
                            HStack(spacing: 18) {
                                ForEach(i.namen, id: \.self) { n in
                                    VStack(spacing: 4) {
                                        Agentenfigur(rolle: i.rolle, stufe: i.stufe, name: n, team: i.team, groesse: 64)
                                        Text(n).font(.caption.monospaced()).foregroundStyle(.secondary)
                                    }
                                    .accessibilityElement(children: .combine)
                                }
                            }
                        }
                    }
                    Text("Die Rolle bestimmt Art, Farbe und Grundform. Der Name des Workers wandelt ab: Muster, Zubehör, Tönung, Augengröße; beim Kern Ringneigung und Satelliten, bei der Linse Braue und Iris. Gleicher Name, gleiche Figur.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            karte("Fünf Größen") {
                // Je Groesse eine Zeile: nebeneinander waeren es ueber 1200 Punkte.
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Agentenfigur.groessen, id: \.self) { g in
                        HStack(alignment: .center, spacing: 12) {
                            Text("\(Int(g)) pt").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                                .frame(width: 44, alignment: .trailing)
                            ForEach(Self.groessenRollen, id: \.rolle) { r in
                                Agentenfigur(rolle: r.rolle, stufe: r.stufe, name: nil, team: r.team, zustand: .ungelesen, groesse: g)
                            }
                        }
                    }
                }
            }
        }
        .padding(28)
    }

    private func karte<Inhalt: View>(_ titel: String, @ViewBuilder _ inhalt: () -> Inhalt) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(titel).font(.title3.weight(.semibold))
            inhalt()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(nsColor: .separatorColor)))
    }

    private func einzelne(rolle: String, team: String, stufe: String, titel: String, zustaende: [(FigurZustand, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 18) {
                ForEach(Array(zustaende.enumerated()), id: \.offset) { i, z in
                    VStack(spacing: 4) {
                        Agentenfigur(rolle: rolle, stufe: stufe, name: nil, team: team, zustand: z.0, groesse: i == 0 ? 96 : 64)
                        Text(z.1).font(.caption).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(titel), \(z.1)")
                }
            }
            Text(titel).font(.headline)
        }
    }

    private func rolle(_ r: FigurBibliothek.Rolle, team: String) -> some View {
        HStack(spacing: 10) {
            ForEach(["tier", "roboter"], id: \.self) { art in
                Agentenfigur(rolle: r.rolle, stufe: r.stufe, name: nil, team: team, groesse: 44, arten: [team: art])
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(r.titel).fontWeight(.semibold)
                Text(r.stufe == "teamleiter" ? "\(r.rolle), Leiter" : r.rolle).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .windowBackgroundColor)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(r.titel), als Tier und als Roboter")
    }
}

@MainActor
final class AgentenfigurenFenster: NSObject, NSWindowDelegate {
    let zustand = FigurenVorschauZustand()
    let fenster: NSWindow
    private let optionen: Laufoptionen
    var sichtbar: Bool { fenster.isVisible }

    @MainActor
    init(optionen: Laufoptionen) {
        self.optionen = optionen
        fenster = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1160, height: 860),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable],
                           backing: .buffered, defer: false)
        super.init()
        fenster.title = "Agentenfiguren"
        fenster.minSize = NSSize(width: 760, height: 520)
        fenster.isReleasedWhenClosed = false
        fenster.delegate = self
        fenster.identifier = NSUserInterfaceItemIdentifier("agentenfiguren")
        let inhalt = NSHostingController(rootView: AgentenfigurenAnsicht(zustand: zustand))
        inhalt.sizingOptions = []
        fenster.contentViewController = inhalt
        fenster.setContentSize(NSSize(width: 1160, height: 860))
    }

    /// Der einzige Weg auf den Bildschirm. Kopflos wirkungslos.
    @MainActor
    func zeigen() {
        guard !optionen.kopflos else { return }
        fenster.vorZeigen(ohneFokus: optionen.ohneFokus)
    }

    /// Ein Belegbild des ganzen Blatts, auch kopflos -- in voller Hoehe, nicht nur
    /// der sichtbare Ausschnitt des Fensters.
    @MainActor
    func schuss(pfad: String, dunkel: Bool) throws -> (breite: Int, hoehe: Int) {
        let renderer = ImageRenderer(content: AgentenfigurenAnsicht(zustand: zustand, beleg: true)
            .environment(\.colorScheme, dunkel ? .dark : .light))
        renderer.scale = 2
        guard let bild = renderer.cgImage else {
            throw NSError(domain: "Werkbank", code: 2, userInfo: [NSLocalizedDescriptionKey: "keine Bitmap"])
        }
        let rep = NSBitmapImageRep(cgImage: bild)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "Werkbank", code: 3, userInfo: [NSLocalizedDescriptionKey: "kein PNG"])
        }
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: pfad).deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: URL(fileURLWithPath: pfad))
        return (rep.pixelsWide, rep.pixelsHigh)
    }

    @MainActor
    func auskunft() -> [String: Any] {
        let z = AgentenfigurenAnsicht.zaehlung
        return [
            "sichtbar": sichtbar, "standbild": zustand.standbild, "titel": fenster.title,
            "abschnitte": z, "figuren": z.values.reduce(0, +),
            // Alle Profile der Bibliothek (profile/rollen/): die Teamrollen und die zwei Einzelnen.
            "rollen": ["hauptagent", "reviewer"] + FigurBibliothek.teams.flatMap { $0.rollen.map(\.rolle) },
            "arten": FigurArt.allCases.map(\.rawValue),
            "zustaende": AgentenfigurenAnsicht.zustaende.map(\.rawValue),
            "groessen": Agentenfigur.groessen.map { Int($0) },
        ]
    }
}
