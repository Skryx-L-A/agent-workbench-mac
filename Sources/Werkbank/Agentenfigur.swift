// DIE AGENTENFIGUREN (10.09.2026, Bau-Schritt 4 des Agents-Features).
//
// Uebertragen aus `docs/agentenfiguren.html`, dem fuenften Entwurf, den
// der Nutzer am 10.09. als Richtung abgenommen hat (docs/AGENTS-PLAN.md,
// Abschnitt 7, „Das Aussehen der Agenten"). Der Zeichner dort ist
// Canvas-JavaScript; hier ist er SwiftUI `Canvas`, bewegt von `TimelineView`.
// Dieselben Ableitungen, dieselben Masse, dieselbe Reihenfolge der
// Zufallszahlen -- ein Worker-Name ergibt hier genau die Figur, die er im
// Blatt ergibt. `AgentenfigurTests` prueft das an Werten, die das Blatt selbst
// ausgerechnet hat.
//
// WAS DIE FIGUR TRAEGT:
//   Art        je Team (Recherche und Gestaltung Tier, Entwicklung und Pruefung
//              Roboter, aenderbar ueber `agents.teams.<name>.art`), dazu zwei
//              eigene Avatare: der Kern fuer den Hauptagenten, die Linse fuer
//              den Reviewer.
//   Farbe      vom Team. Die sechs Identitaetsfarben kommen unveraendert aus
//              dem abgenommenen Blatt; sie sind Illustration, keine
//              Bedienfarben. Die ZUSTANDSFARBEN (Leuchte, Zeichen ueber dem
//              Kopf) sind Systemfarben und folgen Hell, Dunkel und erhoehtem
//              Kontrast von selbst.
//   Koerper    aus dem Rollennamen (Form, Antenne, Ohren, Augen).
//   Variante   aus dem Worker-Namen (Muster, Zubehoer, Toenung, Augengroesse;
//              beim Kern Ringneigung und Satelliten, bei der Linse Braue und
//              Iris). Gleicher Name, gleiche Figur.
//   Zustand    sechs, jeder mit Zeichen ueber dem Kopf und Leuchte, damit er
//              auch still und bei 16 Punkt lesbar bleibt.
//
// BEWEGUNG: Blinzeln in unregelmaessigem Takt, Lesen, Schlafen, Schwanken.
// Bei „Bewegung reduzieren" (System) oder `figurStandbild` (Umgebung, fuer die
// Vorschau und Belegbilder) steht die Figur still -- dieselbe Pose, die das
// Blatt bei `prefers-reduced-motion` zeichnet. Das Blinzeln haengt hier nicht
// an einem Zufallsgenerator im Zustand, sondern ist eine Funktion der Zeit und
// des Namens: eine Figur braucht damit keinen eigenen Speicher.
//
// Die Figur ist Schmuck neben dem Namen und dem Zustandswort der Zeile; fuer
// VoiceOver ist sie deshalb still (`accessibilityHidden`). Wo sie allein steht
// (Vorschau-Fenster), traegt die umgebende Zelle die Beschriftung.
import AppKit
import SwiftUI

// MARK: Zustand und Art

/// Die sechs Zustaende des Blatts, dazu „ruhig" fuer eine Figur ohne Zustand
/// (Rollenliste, Vorschau). Die Rohwerte sind die Kurzformen des Blatts.
enum FigurZustand: String, CaseIterable, Sendable {
    case ruhig, arbeitet, ungelesen, entscheidung, haengt, fertig, fern

    /// Aus dem Wort des Kern-Vertrags (`awb:aufgaben`, Feld `zustand`).
    init(vertrag: String) {
        switch vertrag {
        case "arbeitet": self = .arbeitet
        case "ergebnis_ungelesen": self = .ungelesen
        case "braucht_entscheidung": self = .entscheidung
        case "haengt": self = .haengt
        case "fertig": self = .fertig
        case "nicht_einsehbar": self = .fern
        default: self = .ruhig
        }
    }

    /// Das Wort, das neben der Figur steht -- nie Farbe allein.
    var wort: String {
        switch self {
        case .ruhig: "ruhig"
        case .arbeitet: "arbeitet"
        case .ungelesen: "Ergebnis ungelesen"
        case .entscheidung: "braucht Entscheidung"
        case .haengt: "hängt"
        case .fertig: "fertig"
        case .fern: "nicht einsehbar"
        }
    }

    /// Die Zustandsfarbe als Systemfarbe (Leuchte und Zeichen).
    var farbe: NSColor {
        switch self {
        case .ruhig: .secondaryLabelColor
        case .arbeitet: .systemGreen
        case .ungelesen: .systemPurple
        case .entscheidung: .systemOrange
        case .haengt: .systemRed
        case .fertig: .systemGray
        case .fern: .tertiaryLabelColor
        }
    }
}

enum FigurArt: String, CaseIterable, Sendable {
    case roboter, tier, kern, linse

    /// Kern fuer den Hauptagenten, Linse fuer den Reviewer, sonst die Art des Teams.
    static func fuer(rolle: String, team: String, arten: [String: String]) -> FigurArt {
        if rolle == "hauptagent" { return .kern }
        if rolle == "reviewer" { return .linse }
        return FigurArt(rawValue: arten[team] ?? FigurBibliothek.artVorgabe[team] ?? "roboter") ?? .roboter
    }
}

// MARK: Die Bibliothek (docs/agentenfiguren.html, `TEAMS`; profile/teams/)

enum FigurBibliothek {
    struct Rolle: Sendable { let rolle: String; let titel: String; let stufe: String }
    struct Team: Sendable { let schluessel: String; let name: String; let rollen: [Rolle] }

    static let teams: [Team] = [
        Team(schluessel: "recherche", name: "Recherche", rollen: [
            Rolle(rolle: "recherche-leiter", titel: "Recherche-Leiter", stufe: "teamleiter"),
            Rolle(rolle: "recherche-laeufer", titel: "Recherche-Läufer", stufe: "mitglied"),
            Rolle(rolle: "quellenpruefer", titel: "Quellenprüfer", stufe: "mitglied")]),
        Team(schluessel: "entwicklung", name: "Entwicklung", rollen: [
            Rolle(rolle: "entwicklungs-leiter", titel: "Entwicklungs-Leiter", stufe: "teamleiter"),
            Rolle(rolle: "senior-dev", titel: "Senior-Dev", stufe: "mitglied"),
            Rolle(rolle: "junior-dev", titel: "Junior-Dev", stufe: "mitglied"),
            Rolle(rolle: "tester", titel: "Tester", stufe: "mitglied")]),
        Team(schluessel: "pruefung", name: "Prüfung", rollen: [
            Rolle(rolle: "sicherheitspruefer", titel: "Sicherheitsprüfer", stufe: "mitglied")]),
        Team(schluessel: "gestaltung", name: "Gestaltung", rollen: [
            Rolle(rolle: "gestaltungs-leiter", titel: "Gestaltungs-Leiter", stufe: "teamleiter"),
            Rolle(rolle: "ui-gestalter", titel: "UI-Gestalter", stufe: "mitglied"),
            Rolle(rolle: "dokument-gestalter", titel: "Dokument-Gestalter", stufe: "mitglied"),
            Rolle(rolle: "bild-lokal", titel: "Bild lokal", stufe: "mitglied")]),
    ]

    /// Vorgabe des Plans: Entwicklung und Pruefung Roboter, Recherche und Gestaltung Tier.
    static let artVorgabe: [String: String] = [
        "recherche": "tier", "entwicklung": "roboter", "pruefung": "roboter", "gestaltung": "tier",
    ]

    /// Das Team einer Rolle -- dieselbe Ableitung wie `teamDerRolle` im Kern (aufgaben.ts).
    static func team(der rolle: String) -> String {
        let r = rolle.lowercased()
        if r == "hauptagent" { return "hauptagent" }
        if r == "reviewer" { return "pruefung" }
        for t in teams where t.rollen.contains(where: { $0.rolle == r }) { return t.schluessel }
        if r.contains("recherche") || r.contains("quelle") || r.contains("laeufer") { return "recherche" }
        if r.contains("gestalt") || r.contains("ui-") || r.contains("bild") || r.contains("dokument") { return "gestaltung" }
        if r.contains("pruef") || r.contains("review") || r.contains("sicherheit") { return "pruefung" }
        return "entwicklung"
    }

    /// Die Identitaetsfarbe (abgenommenes Blatt, `--hauptagent` bis `--gestaltung`).
    static func farbe(team: String, art: FigurArt) -> UInt32 {
        if art == .kern { return 0x5856D6 }
        if art == .linse { return 0x3A3F4B }
        switch team {
        case "recherche": return 0x1F9E8F
        case "pruefung": return 0xD9800A
        case "gestaltung": return 0xD6337A
        default: return 0x3478F6
        }
    }
}

// MARK: Der Bauplan -- deterministisch aus Rolle, Stufe und Name

/// FNV-1a ueber die UTF-16-Einheiten, wie `hash()` im Blatt (`for (const c of s)`
/// liest je Codepunkt die erste UTF-16-Einheit).
func figurHash(_ s: String) -> UInt32 {
    var h: UInt32 = 2_166_136_261
    for skalar in s.unicodeScalars {
        let v = skalar.value
        let einheit = v > 0xFFFF ? 0xD800 + ((v - 0x10000) >> 10) : v
        h ^= einheit
        h = h &* 16_777_619
    }
    return h
}

/// xorshift32 wie `rng()` im Blatt.
struct FigurZufall {
    private var x: UInt32
    init(_ seed: UInt32) { x = seed == 0 ? 1 : seed }
    mutating func weiter() -> Double {
        x ^= x << 13
        x ^= x >> 17
        x ^= x << 5
        return Double(x) / 4_294_967_296
    }
    mutating func waehle(_ liste: [String]) -> String {
        liste[Int((weiter() * Double(liste.count)).rounded(.down))]
    }
}

/// `Math.round` aus JavaScript: halbe Werte nach oben, auch im Negativen.
@inline(__always) private func jsRunden(_ x: Double) -> Int { Int((x + 0.5).rounded(.down)) }

struct FigurBauplan: Equatable, Sendable {
    // aus der Rolle
    let koerper: String, antenne: String, ohren: String, auge: String
    let augenAbstand: Double, augenGroesse: Double, fuesse: String
    let wabbeln: [Double]
    let tierOhren: String, tierAuge: Double, tierAbstand: Double, tierWangen: Bool, tierSchwanz: String
    let leiter: Bool
    // aus dem Namen
    let muster: String, zubehoer: String, toenung: Int, augenFaktor: Double
    let ringNeigung: Double, satelliten: Int, braue: String, farbVersatz: Int

    /// `spec(role, stufe, name)` aus dem Blatt, Zeile fuer Zeile in derselben
    /// Reihenfolge: erst die Varianten aus dem Namen, dann der Koerper aus der Rolle.
    init(rolle: String, stufe: String, name: String?) {
        var r = FigurZufall(figurHash(rolle))
        let n = (name?.isEmpty ?? true) ? rolle : name!
        var q = FigurZufall(figurHash(n + "#" + rolle))
        muster = q.waehle(["none", "spots", "stripe", "patch", "none"])
        zubehoer = q.waehle(["none", "scarf", "badge", "sticker", "tip", "none"])
        toenung = jsRunden((q.weiter() - 0.5) * 36)
        augenFaktor = 0.9 + q.weiter() * 0.25
        ringNeigung = -0.6 + q.weiter() * 0.5
        satelliten = q.weiter() < 0.35 ? 2 : 1
        braue = q.waehle(["flat", "arc", "angle"])
        farbVersatz = jsRunden((q.weiter() - 0.5) * 40)

        koerper = r.waehle(["dome", "box", "capsule", "wide"])
        antenne = r.waehle(["none", "single", "twin", "loop", "single"])
        ohren = r.waehle(["none", "round", "fin", "none"])
        auge = r.waehle(["tall", "round", "wide", "tall"])
        augenAbstand = 0.17 + r.weiter() * 0.08
        augenGroesse = 0.12 + r.weiter() * 0.04
        fuesse = r.waehle(["stubs", "wheel", "stubs"])
        wabbeln = (0..<6).map { _ in 0.92 + r.weiter() * 0.2 }
        tierOhren = r.waehle(["pointy", "round", "feeler", "round"])
        tierAuge = 0.11 + r.weiter() * 0.04
        tierAbstand = 0.2 + r.weiter() * 0.08
        tierWangen = r.weiter() < 0.5
        tierSchwanz = r.waehle(["none", "stub", "curl"])
        leiter = stufe == "teamleiter"
    }
}

// MARK: Ausdruck -- gemeinsam fuer alle Arten (`expr()` im Blatt)

struct FigurAusdruck {
    var wippen = 0.0, schwanken = 0.0, atmen = 1.0, blickX = 0.0, blickY = 0.0
    var lidL = 1.0, lidR = 1.0, neigung = 0.0, gekreuzt = false

    static func fuer(_ z: FigurZustand, t: Double, reduziert: Bool, samen: UInt32) -> FigurAusdruck {
        var e = FigurAusdruck()
        if reduziert {
            switch z {
            case .entscheidung: e.neigung = -0.08; e.lidL = 1.2; e.lidR = 0.8
            case .haengt: e.gekreuzt = true; e.neigung = 0.08
            case .fertig: e.lidL = 0.06; e.lidR = 0.06
            case .fern: e.lidL = 0.6; e.lidR = 0.6
            case .arbeitet: e.blickY = 0.35
            default: break
            }
            return e
        }
        switch z {
        case .arbeitet:
            e.blickX = sin(t * 2.8) * 0.9; e.blickY = 0.3 + sin(t * 0.9) * 0.15; e.wippen = sin(t * 3) * 0.8
        case .ungelesen:
            e.blickY = -0.1; e.lidL = 1.15; e.lidR = 1.15
        case .entscheidung:
            e.neigung = -0.1; e.lidL = 1.3; e.lidR = 0.75; e.blickX = 0.35; e.blickY = -0.35
        case .haengt:
            e.schwanken = sin(t * 1.2) * 3; e.neigung = sin(t * 1.2) * 0.06; e.gekreuzt = true
        case .fertig:
            e.atmen = 1 + sin(t * 1.0) * 0.014; e.lidL = 0.06; e.lidR = 0.06
        case .fern:
            e.lidL = 0.6; e.lidR = 0.6
        case .ruhig:
            e.blickX = sin(t * 0.5) * 0.35; e.blickY = sin(t * 0.37) * 0.15; e.atmen = 1 + sin(t * 1.4) * 0.008
        }
        if z != .fertig && z != .haengt {
            let k = blinzeln(t: t, samen: samen)
            e.lidL *= 1 - k * 0.95
            e.lidR *= 1 - k * 0.95
        }
        return e
    }

    /// Blinzeln ohne Speicher: je Abschnitt von 3,2 s ein Lidschlag von 0,16 s
    /// an einer Stelle, die aus Name und Abschnitt folgt -- unregelmaessig wie im
    /// Blatt (dort alle 2 bis 6 s), aber reproduzierbar.
    static func blinzeln(t: Double, samen: UInt32) -> Double {
        let takt = 3.2
        let k = (t / takt).rounded(.down)
        var z = FigurZufall(samen ^ (UInt32(truncatingIfNeeded: Int64(k)) &* 2_654_435_761))
        let versatz = 0.4 + z.weiter() * 2.4
        let p = (t - k * takt - versatz) / 0.16
        guard p >= 0, p < 1 else { return 0 }
        return 1 - abs(p * 2 - 1)
    }
}

// MARK: Farbe

/// Die Palette des Blatts fuer Hell und Dunkel (`--screen` bis `--bubbleline`).
struct FigurPalette {
    let dunkel: Bool
    var bildschirm: Color { dunkel ? rgb(0x0C0C10) : rgb(0x15151A) }
    var auge: Color { rgb(0xF2F6FF) }
    var schatten: Color { Color.black.opacity(dunkel ? 0.5 : 0.14) }
    var blase: Color { dunkel ? rgb(0x2C2C31) : .white }
    var blasenRand: Color { dunkel ? rgb(0x4A4A52) : rgb(0xD0D0D6) }
    var fernRahmen: Color { dunkel ? rgb(0x5A5A62) : rgb(0xB0B0B8) }
}

func rgb(_ hex: UInt32, _ a: Double = 1) -> Color {
    Color(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255).opacity(a)
}

/// `shade(hex, amt, grey)` aus dem Blatt: aufhellen oder abdunkeln, wahlweise ins Grau.
func figurTon(_ hex: UInt32, _ betrag: Double, grau: Bool) -> Color {
    var r = Double((hex >> 16) & 255), g = Double((hex >> 8) & 255), b = Double(hex & 255)
    if grau { let l = 0.3 * r + 0.59 * g + 0.11 * b; r = l; g = l; b = l }
    func k(_ v: Double) -> Double { Double(Int(min(255, max(0, v + betrag)))) / 255 }
    return Color(red: k(r), green: k(g), blue: k(b))
}

// MARK: Der Zeichner

/// Alles in einem Raum von 100 x 100 Einheiten, wie im Blatt (`u = S/100`).
struct FigurZeichner {
    let plan: FigurBauplan
    let art: FigurArt
    let team: String
    let zustand: FigurZustand
    let reduziert: Bool
    let palette: FigurPalette
    let samen: UInt32
    /// Punkte je Einheit -- nur fuer die zwei Linienstaerken, die das Blatt in Bildpunkten festhaelt.
    let u: Double

    private var fern: Bool { zustand == .fern }
    private var basis: UInt32 { FigurBibliothek.farbe(team: team, art: art) }
    private func C(_ a: Int) -> Color { figurTon(basis, Double(a + plan.toenung), grau: fern) }

    func zeichnen(_ ctx: inout GraphicsContext, groesse: CGFloat, t: Double) {
        ctx.scaleBy(x: groesse / 100, y: groesse / 100)
        let e = FigurAusdruck.fuer(zustand, t: t, reduziert: reduziert, samen: samen)
        var koerper = ctx
        if fern { koerper.opacity = 0.5 }
        switch art {
        case .roboter: roboter(&koerper, t, e)
        case .tier: tier(&koerper, t, e)
        case .kern: kern(&koerper, t, e)
        case .linse: linse(&koerper, t, e)
        }
        if fern {
            let rahmen = Path(roundedRect: CGRect(x: 3, y: 3, width: 94, height: 94), cornerRadius: 14)
            ctx.stroke(rahmen, with: .color(palette.fernRahmen), style: StrokeStyle(lineWidth: 1.4, dash: [4, 3]))
        } else if zustand != .ruhig {
            zeichen(&ctx, t, x: 80, y: 17)
        }
    }

    // --- Bausteine ------------------------------------------------------------

    private func rr(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ r: Double) -> Path {
        Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: max(0, min(r, w / 2, h / 2)))
    }

    private func kreis(_ x: Double, _ y: Double, _ r: Double) -> Path {
        Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
    }

    private func ellipse(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double, drehung: Double = 0) -> Path {
        let p = Path(ellipseIn: CGRect(x: -rx, y: -ry, width: 2 * rx, height: 2 * ry))
        return p.applying(CGAffineTransform(rotationAngle: drehung).concatenating(CGAffineTransform(translationX: x, y: y)))
    }

    /// `arc()` des Canvas ohne `anticlockwise`: der Winkel waechst.
    private func bogen(_ x: Double, _ y: Double, _ r: Double, _ von: Double, _ bis: Double) -> Path {
        var p = Path()
        p.addArc(center: CGPoint(x: x, y: y), radius: r, startAngle: .radians(von), endAngle: .radians(bis), clockwise: false)
        return p
    }

    private func linie(_ punkte: [(Double, Double)]) -> Path {
        var p = Path()
        for (i, q) in punkte.enumerated() {
            if i == 0 { p.move(to: CGPoint(x: q.0, y: q.1)) } else { p.addLine(to: CGPoint(x: q.0, y: q.1)) }
        }
        return p
    }

    private func rund(_ breite: Double) -> StrokeStyle { StrokeStyle(lineWidth: breite, lineCap: .round, lineJoin: .round) }

    private func gekreuzteAugen(_ ctx: inout GraphicsContext, _ x: Double, _ y: Double, _ s: Double, _ farbe: Color) {
        var q = Path()
        q.addPath(linie([(x - s / 2, y - s / 2), (x + s / 2, y + s / 2)]))
        q.addPath(linie([(x + s / 2, y - s / 2), (x - s / 2, y + s / 2)]))
        ctx.stroke(q, with: .color(farbe), style: rund(max(1.2 / u, s * 0.22)))
    }

    private func leuchte(_ ctx: inout GraphicsContext, _ t: Double, _ x: Double, _ y: Double) {
        guard zustand != .ruhig else { return }
        let farbe = Color(nsColor: zustand.farbe)
        let puls = (!reduziert && (zustand == .ungelesen || zustand == .arbeitet)) ? 0.65 + 0.35 * sin(t * 4) : 1
        var c = ctx
        c.opacity *= puls
        c.fill(kreis(x, y, 3.8), with: .color(farbe))
        c.opacity *= 0.35
        c.fill(kreis(x, y, 6.5), with: .color(farbe))
    }

    /// Das Zeichen ueber dem Kopf (`cue()` im Blatt).
    private func zeichen(_ ctx: inout GraphicsContext, _ t: Double, x: Double, y: Double) {
        let farbe = Color(nsColor: zustand.farbe)
        switch zustand {
        case .arbeitet:
            for i in 0..<3 {
                var c = ctx
                c.opacity = reduziert ? 1 : 0.55 + 0.45 * sin(t * 5 - Double(i) * 0.9)
                c.fill(kreis(x + Double(i - 1) * 7, y, 2.6), with: .color(farbe))
            }
        case .ungelesen, .entscheidung:
            let w = 20.0, h = 16.0
            let blase = rr(x - w / 2, y - h / 2, w, h, 5)
            var spitze = Path()
            spitze.move(to: CGPoint(x: x - 3, y: y + h / 2 - 0.5))
            spitze.addLine(to: CGPoint(x: x - 6, y: y + h / 2 + 4))
            spitze.addLine(to: CGPoint(x: x + 1, y: y + h / 2 - 0.5))
            spitze.closeSubpath()
            for p in [blase, spitze] {
                ctx.fill(p, with: .color(palette.blase))
                ctx.stroke(p, with: .color(palette.blasenRand), lineWidth: 1.2)
            }
            ctx.fill(Path(CGRect(x: x - 3.5, y: y + h / 2 - 1.5, width: 5, height: 2)), with: .color(palette.blase))
            if zustand == .ungelesen {
                ctx.fill(kreis(x, y, 3.6), with: .color(farbe))
            } else {
                ctx.draw(Text("?").font(.system(size: 13, weight: .bold)).foregroundColor(farbe), at: CGPoint(x: x, y: y + 0.5), anchor: .center)
            }
        case .haengt:
            let dy = reduziert ? 0 : (t * 18).truncatingRemainder(dividingBy: 9)
            var tropfen = Path()
            tropfen.move(to: CGPoint(x: x, y: y - 6 + dy))
            tropfen.addQuadCurve(to: CGPoint(x: x, y: y + 5 + dy), control: CGPoint(x: x + 5, y: y + 2 + dy))
            tropfen.addQuadCurve(to: CGPoint(x: x, y: y - 6 + dy), control: CGPoint(x: x - 5, y: y + 2 + dy))
            ctx.fill(tropfen, with: .color(rgb(0x4FA3F7)))
        case .fertig:
            let ph = reduziert ? 0 : (t * 0.6).truncatingRemainder(dividingBy: 1)
            var c = ctx
            c.opacity = 1 - ph * 0.7
            c.draw(Text("z").font(.system(size: 11, weight: .bold)).foregroundColor(farbe), at: CGPoint(x: x - 2, y: y + 2 - ph * 8), anchor: .center)
            c.draw(Text("z").font(.system(size: 8, weight: .bold)).foregroundColor(farbe), at: CGPoint(x: x + 6, y: y - 4 - ph * 8), anchor: .center)
        case .ruhig, .fern:
            break
        }
    }

    private struct Kasten { let x, y, w, h: Double }

    /// Muster aus dem Namen (`markings()` im Blatt).
    private func muster(_ ctx: inout GraphicsContext, _ b: Kasten) {
        var r = FigurZufall(figurHash("m" + plan.muster + String(Int(b.w.rounded()))))
        switch plan.muster {
        case "spots":
            for _ in 0..<4 {
                let x = b.x + b.w * (0.2 + r.weiter() * 0.6)
                let y = b.y + b.h * (0.55 + r.weiter() * 0.35)
                ctx.fill(kreis(x, y, 2 + r.weiter() * 2.5), with: .color(.white.opacity(0.28)))
            }
        case "stripe":
            for i in 0..<2 {
                ctx.fill(rr(b.x + b.w * 0.1, b.y + b.h * (0.68 + Double(i) * 0.12), b.w * 0.8, 3, 1.5), with: .color(.black.opacity(0.14)))
            }
        case "patch":
            ctx.fill(ellipse(b.x + b.w * 0.72, b.y + b.h * 0.72, b.w * 0.16, b.h * 0.12, drehung: 0.4), with: .color(.black.opacity(0.14)))
        default:
            break
        }
    }

    /// Zubehoer aus dem Namen (`accessory()` im Blatt).
    private func zubehoer(_ ctx: inout GraphicsContext, _ b: Kasten, tier: Bool) {
        let cx = b.x + b.w / 2
        switch plan.zubehoer {
        case "scarf":
            ctx.fill(rr(b.x + b.w * 0.15, b.y + b.h * (tier ? 0.66 : 0.62), b.w * 0.7, 5, 2.5), with: .color(C(-55)))
            ctx.fill(rr(b.x + b.w * 0.62, b.y + b.h * 0.66, 5, 12, 2.5), with: .color(C(-55)))
        case "badge":
            ctx.fill(kreis(b.x + b.w * 0.22, b.y + b.h * 0.74, 4), with: .color(.white.opacity(0.85)))
            ctx.fill(kreis(b.x + b.w * 0.22, b.y + b.h * 0.74, 2), with: .color(C(-30)))
        case "sticker":
            var c = ctx
            c.translateBy(x: b.x + b.w * 0.78, y: b.y + b.h * 0.7)
            c.rotate(by: .radians(-0.4))
            c.fill(rr(-4, -3, 8, 6, 1.2), with: .color(rgb(0xFFD60A)))
        case "tip":
            ctx.fill(kreis(cx, b.y - (tier ? b.h * 0.42 : 0) - 13, 2.4), with: .color(rgb(0xFFD60A)))
        default:
            break
        }
    }

    // --- Roboter -------------------------------------------------------------

    private func roboter(_ ctx0: inout GraphicsContext, _ t: Double, _ e: FigurAusdruck) {
        var ctx = ctx0
        ctx.translateBy(x: 50 + e.schwanken, y: 50 + e.wippen)
        ctx.rotate(by: .radians(e.neigung))
        ctx.scaleBy(x: e.atmen, y: e.atmen)
        ctx.translateBy(x: -50, y: -50)
        var bx = 20.0, by = 26.0, bw = 60.0, bh = 60.0, br = 14.0
        switch plan.koerper {
        case "dome": by = 24; bh = 64; br = 28
        case "capsule": bx = 26; bw = 48; by = 18; bh = 72; br = 24
        case "wide": bx = 12; bw = 76; by = 32; bh = 54; br = 18
        default: break
        }
        ctx.fill(ellipse(50, by + bh + 6, bw * 0.42, 3.5), with: .color(palette.schatten))
        if plan.fuesse == "stubs" {
            ctx.fill(rr(bx + bw * 0.2, by + bh - 4, 12, 9, 4), with: .color(C(-40)))
            ctx.fill(rr(bx + bw * 0.8 - 12, by + bh - 4, 12, 9, 4), with: .color(C(-40)))
        } else {
            ctx.fill(kreis(50, by + bh, 7), with: .color(C(-40)))
        }
        if plan.ohren == "round" {
            ctx.fill(kreis(bx, by + bh * 0.45, 8), with: .color(C(-18)))
            ctx.fill(kreis(bx + bw, by + bh * 0.45, 8), with: .color(C(-18)))
        } else if plan.ohren == "fin" {
            ctx.fill(rr(bx - 7, by + bh * 0.3, 8, 22, 3), with: .color(C(-18)))
            ctx.fill(rr(bx + bw - 1, by + bh * 0.3, 8, 22, 3), with: .color(C(-18)))
        }
        func antenne(_ x: Double, _ h: Double) {
            ctx.stroke(linie([(x, by), (x, by - h)]), with: .color(C(-30)), style: rund(3))
            ctx.fill(kreis(x, by - h, 3.2), with: .color(C(-30)))
        }
        switch plan.antenne {
        case "single": antenne(50, 12)
        case "twin": antenne(38, 9); antenne(62, 9)
        case "loop": ctx.stroke(bogen(50, by - 4, 9, .pi, 2 * .pi), with: .color(C(-30)), style: rund(3))
        default: break
        }
        let rumpf = rr(bx, by, bw, bh, br)
        ctx.fill(rumpf, with: .linearGradient(Gradient(colors: [C(26), C(-20)]), startPoint: CGPoint(x: 0, y: by), endPoint: CGPoint(x: 0, y: by + bh)))
        ctx.stroke(rr(bx + 1, by + 1, bw - 2, bh - 2, br - 1), with: .color(.white.opacity(0.28)), lineWidth: 1.2)
        muster(&ctx, Kasten(x: bx, y: by, w: bw, h: bh))
        let fx = bx + bw * 0.12, fw = bw * 0.76, fy = by + bh * 0.14, fh = bh * 0.46
        ctx.fill(rr(fx, fy, fw, fh, 8), with: .color(palette.bildschirm))
        ctx.fill(rr(fx + 2, fy + 2, fw - 4, fh * 0.35, 6), with: .color(.white.opacity(0.06)))
        if plan.leiter { ctx.fill(rr(fx + 3, fy + 3, fw - 6, 3, 1.5), with: .color(.white.opacity(0.6))) }
        let cx = 50.0, cy = fy + fh * 0.55
        let gap = plan.augenAbstand * 100, es = plan.augenGroesse * 100 * plan.augenFaktor
        func auge(_ x: Double, _ lid: Double) {
            var w = es, h = es * 1.35
            if plan.auge == "round" { h = es } else if plan.auge == "wide" { w = es * 1.3; h = es * 0.9 }
            let ex = x + e.blickX * es * 0.5, ey = cy + e.blickY * es * 0.5
            if e.gekreuzt { gekreuzteAugen(&ctx, x, cy, es * 0.9, palette.auge); return }
            if zustand == .fertig { ctx.fill(rr(ex - w / 2, ey - 1.2, w, 2.4, 1.2), with: .color(palette.auge)); return }
            h *= lid
            ctx.fill(rr(ex - w / 2, ey - h / 2, w, max(1.5, h), min(w, h) * 0.42), with: .color(palette.auge))
            if h > 3 { ctx.fill(kreis(ex + w * 0.22, ey - h * 0.22, max(0.6, w * 0.14)), with: .color(.white.opacity(0.9))) }
        }
        auge(cx - gap / 2, e.lidL)
        auge(cx + gap / 2, e.lidR)
        zubehoer(&ctx, Kasten(x: bx, y: by, w: bw, h: bh), tier: false)
        leuchte(&ctx, t, bx + bw - 9, by + bh - 9)
    }

    // --- Tier ----------------------------------------------------------------

    private func tier(_ ctx0: inout GraphicsContext, _ t: Double, _ e: FigurAusdruck) {
        var ctx = ctx0
        ctx.translateBy(x: 50 + e.schwanken, y: 50 + e.wippen * 0.5)
        ctx.rotate(by: .radians(e.neigung))
        ctx.scaleBy(x: e.atmen, y: e.atmen)
        ctx.translateBy(x: -50, y: -50)
        let cx = 50.0, cy = 57.0, R = 31.0
        ctx.fill(ellipse(cx, cy + R * 0.98, R * 0.8, 3.5), with: .color(palette.schatten))
        if plan.tierSchwanz == "stub" {
            ctx.stroke(linie([(cx + R * 0.85, cy + R * 0.5), (cx + R * 1.15, cy + R * 0.65)]), with: .color(C(-20)), style: rund(4))
        } else if plan.tierSchwanz == "curl" {
            ctx.stroke(bogen(cx + R * 1.05, cy + R * 0.45, R * 0.22, .pi * 0.9, .pi * 2.2), with: .color(C(-20)), style: rund(4))
        }
        switch plan.tierOhren {
        case "pointy":
            for s in [-1.0, 1.0] {
                var p = Path()
                p.move(to: CGPoint(x: cx + s * R * 0.4, y: cy - R * 0.75))
                p.addLine(to: CGPoint(x: cx + s * R * 0.7, y: cy - R * 1.35))
                p.addLine(to: CGPoint(x: cx + s * R * 0.92, y: cy - R * 0.5))
                p.closeSubpath()
                ctx.fill(p, with: .color(C(-8)))
            }
        case "round":
            for s in [-1.0, 1.0] { ctx.fill(kreis(cx + s * R * 0.75, cy - R * 0.78, R * 0.3), with: .color(C(-8))) }
        default:
            for s in [-1.0, 1.0] {
                var p = Path()
                p.move(to: CGPoint(x: cx + s * R * 0.35, y: cy - R * 0.9))
                p.addQuadCurve(to: CGPoint(x: cx + s * R * 0.95, y: cy - R * 1.35), control: CGPoint(x: cx + s * R * 0.6, y: cy - R * 1.5))
                ctx.stroke(p, with: .color(C(-20)), style: rund(2.5))
                ctx.fill(kreis(cx + s * R * 0.95, cy - R * 1.35, 3), with: .color(C(-8)))
            }
        }
        var rumpf = Path()
        let w = plan.wabbeln
        for i in 0..<6 {
            let a0 = Double(i) / 6 * 2 * .pi - .pi / 2, a1 = Double(i + 1) / 6 * 2 * .pi - .pi / 2
            let r0 = R * w[i], r1 = R * w[(i + 1) % 6]
            let am = (a0 + a1) / 2, rm = (r0 + r1) / 2 * 1.08
            if i == 0 { rumpf.move(to: CGPoint(x: cx + cos(a0) * r0, y: cy + sin(a0) * r0)) }
            rumpf.addQuadCurve(to: CGPoint(x: cx + cos(a1) * r1, y: cy + sin(a1) * r1), control: CGPoint(x: cx + cos(am) * rm, y: cy + sin(am) * rm))
        }
        rumpf.closeSubpath()
        // Das Blatt verlaeuft von einem versetzten inneren Kreis zum Mittelpunkt;
        // SwiftUI kennt nur einen Mittelpunkt -- der liegt hier dazwischen.
        ctx.fill(rumpf, with: .radialGradient(Gradient(colors: [C(40), C(-18)]), center: CGPoint(x: cx - R * 0.15, y: cy - R * 0.2), startRadius: R * 0.1, endRadius: R * 1.2))
        ctx.fill(ellipse(cx, cy + R * 0.35, R * 0.45, R * 0.38), with: .color(.white.opacity(0.22)))
        var innen = ctx
        innen.clip(to: kreis(cx, cy, R * 1.02))
        muster(&innen, Kasten(x: cx - R, y: cy - R, w: 2 * R, h: 2 * R))
        if plan.leiter { ctx.stroke(ellipse(cx, cy + R * 0.62, R * 0.72, R * 0.16), with: .color(.white.opacity(0.75)), lineWidth: 2.2) }
        if plan.tierWangen {
            for s in [-1.0, 1.0] { ctx.fill(ellipse(cx + s * R * 0.55, cy + R * 0.12, R * 0.14, R * 0.09), with: .color(Color(red: 1, green: 120 / 255, blue: 140 / 255).opacity(0.35))) }
        }
        let es = plan.tierAuge * 100 * plan.augenFaktor, gap = plan.tierAbstand * 100, ey0 = cy - R * 0.2
        func auge(_ x: Double, _ lid: Double) {
            if e.gekreuzt { gekreuzteAugen(&ctx, x, ey0, es * 1.4, palette.bildschirm); return }
            if zustand == .fertig {
                ctx.stroke(bogen(x, ey0 - es * 0.2, es * 0.8, .pi * 0.15, .pi * 0.85), with: .color(palette.bildschirm), style: rund(max(1.4, es * 0.22)))
                return
            }
            let h = es * 2 * lid
            ctx.fill(ellipse(x, ey0, es, max(1.2, h / 2)), with: .color(.white))
            if h > 2.5 {
                var c = ctx
                c.clip(to: ellipse(x, ey0, es, h / 2))
                let px = x + e.blickX * es * 0.45, py = ey0 + e.blickY * es * 0.45
                c.fill(kreis(px, py, es * 0.58), with: .color(palette.bildschirm))
                c.fill(kreis(px + es * 0.2, py - es * 0.22, max(0.7, es * 0.18)), with: .color(.white.opacity(0.95)))
            }
        }
        auge(cx - gap / 2, e.lidL)
        auge(cx + gap / 2, e.lidR)
        zubehoer(&ctx, Kasten(x: cx - R, y: cy - R, w: 2 * R, h: 2 * R), tier: true)
        leuchte(&ctx, t, cx + R * 0.62, cy + R * 0.72)
    }

    // --- Hauptagent: der Kern --------------------------------------------------

    private func kern(_ ctx0: inout GraphicsContext, _ t: Double, _ e: FigurAusdruck) {
        var ctx = ctx0
        let schweben = reduziert ? 0 : sin(t * 1.3) * 2.5
        let dreh = reduziert ? 0.6 : t * (zustand == .arbeitet ? 2.2 : 0.7)
        let neigung = plan.ringNeigung
        ctx.translateBy(x: 50 + e.schwanken, y: 50 + schweben)
        ctx.rotate(by: .radians(e.neigung * 0.5))
        ctx.translateBy(x: -50, y: -50)
        let cx = 50.0, cy = 52.0, R = 26.0
        ctx.fill(ellipse(cx, 88, R * 0.7, 3), with: .color(palette.schatten))
        let glut = fern ? Color(red: 120 / 255, green: 120 / 255, blue: 130 / 255).opacity(0.25) : rgb(0x5856D6, 0.28)
        ctx.fill(kreis(cx, cy, R * 1.7), with: .radialGradient(Gradient(colors: [glut, rgb(0x5856D6, 0)]), center: CGPoint(x: cx, y: cy), startRadius: R * 0.6, endRadius: R * 1.7))
        func ring(_ von: Double, _ bis: Double, _ ton: Int) {
            var c = ctx
            c.translateBy(x: cx, y: cy)
            c.rotate(by: .radians(neigung))
            c.scaleBy(x: 1, y: 0.32)
            c.stroke(bogen(0, 0, R * 1.55, von, bis), with: .color(C(ton)), lineWidth: 3.2)
        }
        ring(.pi, 2 * .pi, -30)
        func lage(_ a: Double) -> (Double, Double) {
            let rx = cos(a) * R * 1.55, ry = sin(a) * R * 1.55 * 0.32
            return (cx + rx * cos(neigung) - ry * sin(neigung), cy + rx * sin(neigung) + ry * cos(neigung))
        }
        let satelliten = (0..<plan.satelliten).map { i -> (a: Double, hinten: Bool, r: Double) in
            let a = dreh + Double(i) * .pi * 1.1
            return (a, sin(a) < 0, i == 0 ? 3.6 : 2.6)
        }
        // Hinter dem Kern zuerst -- er verdeckt sie (Befund zum vierten Entwurf).
        for s in satelliten where s.hinten {
            let (sx, sy) = lage(s.a)
            ctx.fill(kreis(sx, sy, s.r), with: .color(C(-25)))
        }
        ctx.fill(kreis(cx, cy, R), with: .radialGradient(Gradient(stops: [.init(color: C(70), location: 0), .init(color: C(0), location: 0.6), .init(color: C(-45), location: 1)]),
                                                         center: CGPoint(x: cx - R * 0.2, y: cy - R * 0.22), startRadius: R * 0.1, endRadius: R * 1.05))
        ctx.stroke(kreis(cx, cy, R - 1), with: .color(.white.opacity(0.35)), lineWidth: 1.2)
        let es = 8.5, gap = 17.0
        func auge(_ x: Double, _ lid: Double) {
            let ex = x + e.blickX * es * 0.4, ey = cy - 2 + e.blickY * es * 0.4
            if e.gekreuzt { gekreuzteAugen(&ctx, x, cy - 2, es * 1.1, palette.auge); return }
            if zustand == .fertig { ctx.fill(rr(ex - es * 0.6, ey - 1.1, es * 1.2, 2.2, 1.1), with: .color(palette.auge)); return }
            let h = max(1.5, es * 1.5 * lid)
            ctx.fill(rr(ex - es * 0.55, ey - h / 2, es * 1.1, h, es * 0.45), with: .color(palette.auge))
            if h > 3 { ctx.fill(kreis(ex + es * 0.25, ey - h * 0.25, 0.9), with: .color(.white.opacity(0.9))) }
        }
        auge(cx - gap / 2, e.lidL)
        auge(cx + gap / 2, e.lidR)
        ring(0, .pi, -10)
        for s in satelliten where !s.hinten {
            let (sx, sy) = lage(s.a)
            ctx.fill(kreis(sx, sy, s.r), with: .color(C(12)))
            ctx.fill(kreis(sx - s.r * 0.3, sy - s.r * 0.3, s.r * 0.35), with: .color(.white.opacity(0.6)))
        }
        leuchte(&ctx, t, cx + R * 0.75, cy + R * 0.75)
    }

    // --- Reviewer: die Linse ---------------------------------------------------

    private func linse(_ ctx0: inout GraphicsContext, _ t: Double, _ e: FigurAusdruck) {
        var ctx = ctx0
        let pruef: UInt32 = 0xD9800A
        func I(_ a: Int) -> Color { figurTon(pruef, Double(a + plan.farbVersatz), grau: fern) }
        // Die Linse toent nur halb (`a + sp.tint*0.5` im Blatt).
        func G(_ a: Int) -> Color { figurTon(basis, Double(a) + Double(plan.toenung) * 0.5, grau: fern) }
        ctx.translateBy(x: 50 + e.schwanken, y: 50 + e.wippen)
        ctx.rotate(by: .radians(e.neigung))
        ctx.translateBy(x: -50, y: -50)
        let bx = 30.0, by = 14.0, bw = 40.0, bh = 64.0, cx = 50.0
        ctx.fill(ellipse(cx, 92, 22, 3.5), with: .color(palette.schatten))
        for dx in [-16.0, 0, 16] {
            ctx.stroke(linie([(cx, by + bh - 6), (cx + dx, 91)]), with: .color(G(-25)), style: rund(3.2))
        }
        ctx.fill(rr(bx, by, bw, bh, 10), with: .linearGradient(Gradient(stops: [.init(color: G(30), location: 0), .init(color: G(8), location: 0.5), .init(color: G(-25), location: 1)]),
                                                               startPoint: CGPoint(x: bx, y: 0), endPoint: CGPoint(x: bx + bw, y: 0)))
        ctx.stroke(rr(bx + 1, by + 1, bw - 2, bh - 2, 9), with: .color(.white.opacity(0.22)), lineWidth: 1.2)
        do {
            var c = ctx
            c.translateBy(x: cx, y: by + 9)
            c.rotate(by: .radians(zustand == .entscheidung ? -0.18 : 0))
            switch plan.braue {
            case "flat":
                c.fill(rr(-15, -2.5, 30, 5, 2.5), with: .color(G(-40)))
            case "arc":
                c.stroke(bogen(0, 6, 16, .pi * 1.15, .pi * 1.85), with: .color(G(-40)), style: rund(5))
            default:
                var p = Path()
                p.move(to: CGPoint(x: -15, y: 2)); p.addLine(to: CGPoint(x: 0, y: -3)); p.addLine(to: CGPoint(x: 15, y: 2))
                p.addLine(to: CGPoint(x: 15, y: 5)); p.addLine(to: CGPoint(x: 0, y: 0)); p.addLine(to: CGPoint(x: -15, y: 5))
                p.closeSubpath()
                c.fill(p, with: .color(G(-40)))
            }
        }
        let ly = by + 30, LR = 15.0
        ctx.fill(kreis(cx, ly, LR), with: .color(palette.bildschirm))
        do {
            var c = ctx
            c.clip(to: kreis(cx, ly, LR - 1.5))
            if e.gekreuzt {
                gekreuzteAugen(&c, cx, ly, LR * 1.1, I(20))
            } else {
                let ir = zustand == .arbeitet ? LR * 0.42 : zustand == .ungelesen ? LR * 0.7 : LR * 0.55
                let lid = min(e.lidL, e.lidR)
                let ix = cx + e.blickX * LR * 0.3, iy = ly + e.blickY * LR * 0.3
                if zustand == .fertig || lid < 0.2 {
                    c.fill(Path(CGRect(x: cx - LR, y: ly - LR, width: LR * 2, height: LR * 2)), with: .color(G(-10)))
                    c.stroke(linie([(cx - LR * 0.6, ly), (cx + LR * 0.6, ly)]), with: .color(I(0)), lineWidth: 2)
                } else {
                    c.fill(kreis(ix, iy, ir), with: .radialGradient(Gradient(stops: [.init(color: I(60), location: 0), .init(color: I(0), location: 0.7), .init(color: I(-40), location: 1)]),
                                                                  center: CGPoint(x: ix, y: iy), startRadius: ir * 0.2, endRadius: ir))
                    c.fill(kreis(ix, iy, ir * 0.42), with: .color(palette.bildschirm))
                    c.fill(kreis(ix - ir * 0.35, iy - ir * 0.4, max(0.8, ir * 0.18)), with: .color(.white.opacity(0.85)))
                    if zustand == .arbeitet && !reduziert {
                        let sy = ly - LR + (t * 30).truncatingRemainder(dividingBy: LR * 2)
                        c.fill(Path(CGRect(x: cx - LR, y: sy, width: LR * 2, height: 1.6)), with: .color(Color(red: 1, green: 200 / 255, blue: 120 / 255).opacity(0.55)))
                    }
                }
            }
        }
        ctx.stroke(kreis(cx, ly, LR), with: .color(.white.opacity(0.35)), lineWidth: 1.5)
        for i in 0..<3 {
            let yy = by + 52 + Double(i) * 6
            ctx.stroke(linie([(cx - 6, yy), (cx - 3, yy + 2.5), (cx + 5, yy - 3)]), with: .color(I(10)), style: rund(1.8))
        }
        leuchte(&ctx, t, bx + bw - 6, by + bh - 7)
    }
}

// MARK: Der Ring des Lebenszeichens

/// DER RING UM DIE FIGUR (Auftrag agentaktiv, 15.09.2026). der Nutzer nach dem ersten echten Chat:
/// „nachdem ich die Nachricht gesendet habe, wusste ich nicht, ob Myproject reagieren wird. Das muss man
/// am Avatar sehen können." Die Figur selbst bleibt unveraendert (ihre Neugestaltung ist gesperrt); das
/// Lebenszeichen legt sich als Ring darum:
///   arbeitet  ein Bogen in der Lauf-Farbe kreist ruhig ueber einem blassen Ring, solange ein Zug laeuft.
///   wartet    ein gepunkteter Ring, still: die Nachricht ist zugestellt, der Traeger hat noch keinen Zug.
/// Bei „Bewegung reduzieren" (System) oder `figurStandbild` steht statt des Bogens ein voller Ring. Der
/// Ring liegt ausserhalb des Rahmens der Figur und veraendert kein Layout; er ist Schmuck neben dem Wort
/// und fuer VoiceOver still wie die Figur.
enum FigurRing: String, Sendable {
    case keiner, arbeitet, wartet
}

struct FigurRingAnsicht: View {
    let ring: FigurRing
    let groesse: CGFloat

    @Environment(\.accessibilityReduceMotion) private var systemRuhig
    @Environment(\.figurStandbild) private var standbild

    /// Ein Umlauf des Bogens in Sekunden: ruhig genug fuer den Blick zur Seite, schnell genug, um Bewegung zu sehen.
    static let umlauf: TimeInterval = 1.8

    var body: some View {
        let breite = max(1.5, groesse * 0.05)
        let abstand = breite + 1
        let farbe = Color(nsColor: FigurZustand.arbeitet.farbe)
        Group {
            switch ring {
            case .keiner:
                EmptyView()
            case .wartet:
                Circle()
                    .strokeBorder(Color(nsColor: .secondaryLabelColor), style: StrokeStyle(lineWidth: breite, lineCap: .round, dash: [0.01, breite * 2.4]))
            case .arbeitet:
                if systemRuhig || standbild {
                    Circle().strokeBorder(farbe, lineWidth: breite)
                } else {
                    TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
                        let winkel = tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.umlauf) / Self.umlauf * 360
                        ZStack {
                            Circle().strokeBorder(farbe.opacity(0.28), lineWidth: breite)
                            Circle().inset(by: breite / 2).trim(from: 0, to: 0.3)
                                .stroke(farbe, style: StrokeStyle(lineWidth: breite, lineCap: .round))
                                .rotationEffect(.degrees(winkel))
                        }
                    }
                }
            }
        }
        .padding(-abstand)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: Die Ansicht

private struct FigurStandbildSchluessel: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// Erzwingt das Standbild, auch ohne „Bewegung reduzieren" im System --
    /// fuer die Vorschau und fuer Belegbilder, die reproduzierbar sein sollen.
    var figurStandbild: Bool {
        get { self[FigurStandbildSchluessel.self] }
        set { self[FigurStandbildSchluessel.self] = newValue }
    }
}

/// Eine Figur: Rolle, Stufe, Name, Team, Zustand -- in einer der fuenf Groessen
/// des Plans (16, 32, 44, 64, 96 Punkt).
struct Agentenfigur: View {
    let rolle: String
    var stufe = "mitglied"
    var name: String? = nil
    var team: String? = nil
    var zustand: FigurZustand = .ruhig
    var groesse: CGFloat = 32
    /// Art je Team (`agents.teams.<name>.art`); leer heisst Vorgabe.
    var arten: [String: String] = [:]

    @Environment(\.accessibilityReduceMotion) private var systemRuhig
    @Environment(\.figurStandbild) private var standbild
    @Environment(\.colorScheme) private var schema

    static let groessen: [CGFloat] = [16, 32, 44, 64, 96]

    var body: some View {
        let ruhig = systemRuhig || standbild
        Group {
            if ruhig {
                Canvas(rendersAsynchronously: false) { ctx, size in zeichner(reduziert: true).zeichnen(&ctx, groesse: size.width, t: 0) }
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
                    Canvas { ctx, size in
                        zeichner(reduziert: false).zeichnen(&ctx, groesse: size.width, t: tl.date.timeIntervalSinceReferenceDate + versatz)
                    }
                }
            }
        }
        .frame(width: groesse, height: groesse)
        .accessibilityHidden(true)
    }

    private var samen: UInt32 { figurHash((name ?? rolle) + "#" + rolle) }
    /// Jede Figur hat ihren eigenen Takt, sonst blinzelten alle zugleich.
    private var versatz: Double { Double(samen % 4000) / 1000 }

    func zeichner(reduziert: Bool) -> FigurZeichner {
        let t = team ?? FigurBibliothek.team(der: rolle)
        return FigurZeichner(plan: FigurBauplan(rolle: rolle, stufe: stufe, name: name),
                             art: FigurArt.fuer(rolle: rolle, team: t, arten: arten), team: t,
                             zustand: zustand, reduziert: reduziert, palette: FigurPalette(dunkel: schema == .dark),
                             samen: samen, u: Double(groesse) / 100)
    }
}
