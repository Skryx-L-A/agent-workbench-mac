// DAS ORDNER-BLATT (Auftrag 3.5) und die Inhaltssuche darin (Auftrag 3.6).
//
// Vorbild ist `app/src/renderer/ordner-view.ts`: der Projektordner der
// gewaehlten Sitzung, sonst das Eigenheim; ausgeschlossene Pfade
// (`~/Knowledge/90-secrets/`, `~/.ssh/`) entscheidet der Kern (main/folder.ts),
// dieses Blatt zeichnet nur, was es bekommt. Die Suche sitzt oben im selben
// Blatt und ersetzt bei nicht-leerer Eingabe den Baum durch die Treffer --
// „in derselben Leiste", nicht in einer eigenen.
//
// AUFFRISCHUNG IM TAKT, ABER NUR SOLANGE DAS BLATT STEHT (dieselbe Messung wie
// in der Electron-Fassung: ein Ordner kostet 0,04 bis 0,29 ms, eine Runde ueber
// zwei, drei offene Ordner also unter einer Millisekunde -- billiger als ein
// Dateisystem-Beobachter, der je Ordner eine Ressource haelt). Der Takt haengt
// am 0,25-s-Zug des Fensters (`Fenster.nachziehen`) mit eigener Sperre, damit
// hier kein zweiter Timer laeuft: was nicht sichtbar ist, fragt nicht nach.
//
// EIN KLICK AUF EINE DATEI OEFFNET SIE IM EDITOR, nicht im Finder (Auftrag
// 3.5): Text landet im Editor-Blatt, Binaeres geht ans System. Beides
// entscheidet der Kern (`awb:chat-pfad-oeffnen`, main/chatpfade.ts), nicht
// diese Ansicht -- derselbe Weg wie beim Pfad-Klick im Gespraech.
import SwiftUI
import WerkbankProtokoll

/// Eine gezeichnete Zeile des Baums.
struct OrdnerZeile: Identifiable, Equatable {
    var id: String { pfad }
    let pfad: String
    let name: String
    let ordner: Bool
    let tiefe: Int
    let offen: Bool
    let groesse: Int
}

@MainActor
@Observable
final class OrdnerZustand {
    @ObservationIgnored let kern: KernVerbindung

    private(set) var wurzel = ""
    private(set) var kinder: [String: [OrdnerEintrag]] = [:]
    private(set) var aufgeklappt: Set<String> = []
    /// Wieviele Ordner-Antworten dieses Blatt seit dem Start verarbeitet hat --
    /// die MESSGROESSE hinter „nichts laeuft auf Vorrat": bei geschlossenem
    /// Blatt bleibt sie stehen, egal was auf der Platte geschieht.
    private(set) var lesungen = 0
    /// Steht das Blatt gerade im Inspektor? Nur dann wird nachgesehen.
    private(set) var sichtbar = false

    var suche = "" {
        didSet { if suche != oldValue { sucheGeaendert() } }
    }
    private(set) var treffer: [Suchtreffer]?
    /// Wahr, solange die Antwort auf die aktuelle Eingabe noch aussteht.
    private(set) var suchtLaeuft = false
    private(set) var letzteAnfrage = ""
    private(set) var meldung = ""

    /// Der Ordner, bis zu dem aufgeklappt werden soll (Pfad-Klick auf ein
    /// Verzeichnis). Leer, sobald alle Stufen dorthin gelesen sind.
    @ObservationIgnored private var zielPfad = ""
    @ObservationIgnored private var wurzelAngefragt = false
    @ObservationIgnored private var letzterTakt = Date.distantPast
    @ObservationIgnored private var suchZeit: Date?
    /// Ein Klick auf eine Datei laeuft ueber diesen Weg (Fenster setzt ihn).
    @ObservationIgnored var dateiOeffnen: ((String) -> Void)?

    /// Zwei Sekunden: schnell genug, dass eine Datei „gleich" auftaucht, langsam
    /// genug, dass die Runde im Rauschen verschwindet (ordner-view.ts).
    static let taktSekunden: TimeInterval = 2

    init(kern: KernVerbindung) {
        self.kern = kern
    }

    // MARK: Sichtbarkeit und Takt

    func sichtbarSetzen(_ an: Bool) {
        guard an != sichtbar else { return }
        sichtbar = an
        if an {
            wurzelAngefragt = true
            letzterTakt = Date()
            kern.ordnerListe("")
        }
    }

    /// Eine Runde: jeden SICHTBAREN Ordner neu anfordern. Wird vom Fenster im
    /// 0,25-s-Zug gerufen und begrenzt sich selbst auf `taktSekunden`.
    func takt() {
        guard sichtbar, !wurzel.isEmpty else { return }
        guard Date().timeIntervalSince(letzterTakt) >= Self.taktSekunden else { return }
        letzterTakt = Date()
        for pfad in offeneOrdner() { kern.ordnerListe(pfad) }
    }

    /// Wieviele Ordner gerade nachgesehen werden. Zu ist zu: geschlossen null.
    var beobachtet: Int { sichtbar ? offeneOrdner().count : 0 }

    // MARK: Antworten des Kerns

    func angekommen(_ p: OrdnerNutzlast) {
        lesungen += 1
        if wurzelAngefragt {
            wurzelAngefragt = false
            if p.root != wurzel {
                wurzel = p.root
                kinder = [:]
                aufgeklappt = [wurzel]
            }
        }
        kinder[p.root] = p.entries
        zielVerfolgen()
        aufraeumen()
    }

    func sucheAngekommen(_ p: SucheNutzlast) {
        // Bei schnellem Tippen koennen Antworten in anderer Reihenfolge
        // ankommen, als sie losgeschickt wurden -- was nicht mehr zur Eingabe
        // passt, wird verworfen (ordner-view.ts).
        guard p.query == letzteAnfrage else { return }
        suchtLaeuft = false
        treffer = p.treffer
        if p.treffer == nil {
            meldung = "Auf dieser Maschine ist kein Suchwerkzeug (ripgrep oder grep) erreichbar."
        } else {
            meldung = ""
        }
    }

    // MARK: Der Baum

    /// Die Ordner, die wirklich auf dem Schirm stehen: die Wurzel und jeder
    /// aufgeklappte Ordner, der von ihr aus erreichbar ist. Der Wall gegen
    /// doppelte Pfade faengt einen Symlink-Ring ab.
    private func offeneOrdner() -> [String] {
        guard !wurzel.isEmpty else { return [] }
        var raus: [String] = []
        var gesehen = Set<String>()
        func gehe(_ pfad: String) {
            guard !gesehen.contains(pfad) else { return }
            gesehen.insert(pfad)
            raus.append(pfad)
            for e in kinder[pfad] ?? [] where e.isDir && aufgeklappt.contains(e.path) { gehe(e.path) }
        }
        gehe(wurzel)
        return raus
    }

    /// Was von der Wurzel aus noch erreichbar ist. Ein von aussen geloeschter
    /// Ordner stuende sonst fuer immer im Zwischenspeicher.
    private func aufraeumen() {
        guard !wurzel.isEmpty else { return }
        var lebt = Set<String>()
        func gehe(_ pfad: String) {
            guard !lebt.contains(pfad) else { return }
            lebt.insert(pfad)
            for e in kinder[pfad] ?? [] where e.isDir { gehe(e.path) }
        }
        gehe(wurzel)
        for pfad in kinder.keys where !lebt.contains(pfad) { kinder.removeValue(forKey: pfad) }
        aufgeklappt = aufgeklappt.filter { lebt.contains($0) }
    }

    /// Der Baum, flach: Wurzelkinder, darunter die aufgeklappten Zweige.
    var zeilen: [OrdnerZeile] {
        var raus: [OrdnerZeile] = []
        func gehe(_ pfad: String, _ tiefe: Int) {
            guard tiefe < 12 else { return }
            for e in kinder[pfad] ?? [] {
                let auf = e.isDir && aufgeklappt.contains(e.path)
                raus.append(OrdnerZeile(pfad: e.path, name: e.name, ordner: e.isDir, tiefe: tiefe,
                                        offen: auf, groesse: e.size))
                if auf { gehe(e.path, tiefe + 1) }
            }
        }
        gehe(wurzel, 0)
        return raus
    }

    /// Ein Klick auf eine Zeile des Blatts: ein Ordner geht auf oder zu, eine
    /// Datei geht auf. Waehrend einer Suche steht statt des Baums die
    /// Trefferliste da -- ein Klick trifft dann einen Treffer, samt seiner
    /// Zeilennummer (`pfad:zeile`), wie der Knopf in der Ansicht.
    func klick(_ pfad: String) {
        if let z = zeilen.first(where: { $0.pfad == pfad }) {
            if z.ordner { ordnerUmschalten(pfad) } else { dateiOeffnen?(pfad) }
            return
        }
        let k = Pfadlinks.zerlegen(pfad)
        if let t = (treffer ?? []).first(where: { $0.pfad == k.pfad }) {
            dateiOeffnen?("\(t.pfad):\(k.zeile > 0 ? k.zeile : t.zeile)")
            return
        }
        ordnerUmschalten(pfad)
    }

    func ordnerUmschalten(_ pfad: String) {
        if aufgeklappt.contains(pfad) {
            aufgeklappt.remove(pfad)
        } else {
            aufgeklappt.insert(pfad)
            if kinder[pfad] == nil { kern.ordnerListe(pfad) }
        }
    }

    /// Bis zu diesem Ordner aufklappen (der Pfad-Klick auf ein Verzeichnis).
    /// Liegt er ausserhalb der Wurzel, bleibt es beim geoeffneten Blatt.
    func zeigen(_ pfad: String) {
        zielPfad = pfad
        if wurzel.isEmpty {
            wurzelAngefragt = true
            kern.ordnerListe("")
            return
        }
        zielVerfolgen()
    }

    @discardableResult
    private func zielVerfolgen() -> Bool {
        guard !zielPfad.isEmpty, !wurzel.isEmpty else { return false }
        guard zielPfad == wurzel || zielPfad.hasPrefix(wurzel + "/") else {
            meldung = "„\(Pfadlinks.kurzerPfad(zielPfad))“ liegt nicht unter \(Pfadlinks.kurzerPfad(wurzel))."
            zielPfad = ""
            return false
        }
        let rest = zielPfad == wurzel ? "" : String(zielPfad.dropFirst(wurzel.count + 1))
        var hier = wurzel
        var fertig = true
        aufgeklappt.insert(wurzel)
        for teil in rest.isEmpty ? [] : rest.split(separator: "/").map(String.init) {
            hier += "/\(teil)"
            aufgeklappt.insert(hier)
            if kinder[hier] == nil {
                kern.ordnerListe(hier)
                fertig = false
            }
        }
        if fertig { zielPfad = "" }
        return true
    }

    // MARK: Die Suche

    private func sucheGeaendert() {
        let text = suche.trimmingCharacters(in: .whitespaces)
        if text.isEmpty {
            letzteAnfrage = ""
            treffer = nil
            suchtLaeuft = false
            suchZeit = nil
            meldung = ""
            return
        }
        // 300 ms Ruhe wie im Renderer -- getippt wird schneller, als `rg` liest.
        suchZeit = Date().addingTimeInterval(0.3)
        suchtLaeuft = true
    }

    /// Der Fensterzug prueft, ob die Ruhe vor dem Suchlauf um ist.
    func suchTakt() {
        guard let faellig = suchZeit, Date() >= faellig else { return }
        suchZeit = nil
        let text = suche.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        letzteAnfrage = text
        kern.sucheLesen(text, pfad: wurzel)
    }

    /// Sofort suchen, ohne die Ruhe abzuwarten -- der Weg des Steuerkanals.
    func jetztSuchen() {
        suchZeit = nil
        let text = suche.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { treffer = nil; letzteAnfrage = ""; return }
        letzteAnfrage = text
        suchtLaeuft = true
        kern.sucheLesen(text, pfad: wurzel)
    }

    var sucheAktiv: Bool { !suche.trimmingCharacters(in: .whitespaces).isEmpty }

    func auskunft() -> [String: Any] {
        [
            "sichtbar": sichtbar,
            "wurzel": wurzel,
            "kurzpfad": Pfadlinks.kurzerPfad(wurzel),
            "zeilen": zeilen.map { ["pfad": $0.pfad, "name": $0.name, "ordner": $0.ordner, "tiefe": $0.tiefe,
                                    "offen": $0.offen, "groesse": $0.groesse] },
            "namen": zeilen.map(\.name),
            "lesungen": lesungen,
            "beobachtet": beobachtet,
            "sucheAktiv": sucheAktiv,
            "suche": suche,
            "sucheLaeuft": suchtLaeuft,
            "trefferDa": treffer != nil,
            "treffer": (treffer ?? []).map { ["pfad": $0.pfad, "zeile": $0.zeile, "text": $0.text] },
            "meldung": meldung,
        ]
    }
}

// MARK: - Die Ansicht

struct OrdnerAnsicht: View {
    @Bindable var zustand: OrdnerZustand
    /// Im Beleg zeichnen ScrollView, Buttons und Textfelder nichts (mac/PLAN.md,
    /// Auftrag 2.4) -- dann steht derselbe Wortlaut als Text.
    var beleg = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            kopf
            Divider()
            if beleg {
                inhalt.padding(10)
                Spacer(minLength: 0)
            } else {
                ScrollView { inhalt.padding(10) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(beleg ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor)) : AnyShapeStyle(.background))
        .accessibilityIdentifier("ordnerblatt")
    }

    private var kopf: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Pfadlinks.kurzerPfad(zustand.wurzel))
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
                .help(zustand.wurzel)
                .accessibilityLabel("Ordner \(zustand.wurzel)")
            if beleg {
                Label(zustand.suche.isEmpty ? "Im Inhalt suchen" : zustand.suche, systemImage: "magnifyingglass")
                    .font(.callout)
                    .foregroundStyle(zustand.suche.isEmpty ? .secondary : .primary)
            } else {
                TextField("Im Inhalt suchen", text: $zustand.suche)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("ordner-suche")
                    .onSubmit { zustand.jetztSuchen() }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var inhalt: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !zustand.meldung.isEmpty {
                Label(zustand.meldung, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
            }
            if zustand.sucheAktiv {
                trefferliste
            } else {
                baum
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var baum: some View {
        let zeilen = zustand.zeilen
        if zeilen.isEmpty {
            Text(zustand.wurzel.isEmpty ? "Kein Ordner: erst eine Sitzung wählen." : "Dieser Ordner ist leer.")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            ForEach(zeilen) { z in
                if beleg {
                    zeileninhalt(z)
                } else {
                    Button { zustand.klick(z.pfad) } label: { zeileninhalt(z) }
                        .buttonStyle(.plain)
                        .help(z.pfad)
                }
            }
        }
    }

    private func zeileninhalt(_ z: OrdnerZeile) -> some View {
        HStack(spacing: 6) {
            Image(systemName: z.ordner ? (z.offen ? "chevron.down" : "chevron.right") : "doc")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 12)
            Text(z.name).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 4)
            if !z.ordner {
                Text("\(z.groesse) B").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .padding(.leading, CGFloat(z.tiefe) * 14)
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(z.ordner ? "Ordner \(z.name), \(z.offen ? "aufgeklappt" : "zugeklappt")" : "Datei \(z.name)")
    }

    @ViewBuilder
    private var trefferliste: some View {
        if zustand.treffer == nil {
            Text(zustand.suchtLaeuft ? "Wird gesucht …" : "Keine Suche möglich.")
                .font(.callout).foregroundStyle(.secondary)
        } else if zustand.treffer?.isEmpty ?? true {
            Text(zustand.suchtLaeuft ? "Wird gesucht …" : "Kein Treffer.")
                .font(.callout).foregroundStyle(.secondary)
        } else {
            ForEach(zustand.treffer ?? []) { t in
                if beleg {
                    trefferinhalt(t)
                } else {
                    Button { zustand.dateiOeffnen?("\(t.pfad):\(t.zeile)") } label: { trefferinhalt(t) }
                        .buttonStyle(.plain)
                        .help(t.pfad)
                }
            }
        }
    }

    private func trefferinhalt(_ t: Suchtreffer) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Text(t.pfad.split(separator: "/").last.map(String.init) ?? t.pfad)
                    .fontWeight(.semibold).lineLimit(1)
                Text("Zeile \(t.zeile)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Text(t.text)
                .font(.caption)
                .monospaced()
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
