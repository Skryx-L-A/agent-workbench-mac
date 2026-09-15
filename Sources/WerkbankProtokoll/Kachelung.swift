// Die Kachelrechnung der Buehne -- dieselbe wie in app/src/renderer/paneflaeche.ts
// (`kachelReihen`, `kachelLage`, `kachelAusRaster`, `kachelnAusTeilraster`,
// `zeilenZahlFuer`), nur in Swift und ohne Fenster, damit sie sich mit
// `swift test` pruefen laesst. Wer hier eine Zahl aendert, aendert sie auch dort:
// die Electron-Fassung und der Mantel muessen an EINEM tmux-Fenster dieselben
// Kacheln legen, sonst schreiben beide Zeichner verschiedene Groessen hinein
// (shell/tests/test-fenster-zwei-zeichner.sh).
//
// Die drei Wege einer Lage `tab` (paneflaeche.ts, `zeichneLage`):
//   raster      alle gezeigten Panes liegen in EINEM tmux-Fenster, das genau
//               sie traegt -- die Kachel folgt der Lage des Panes im Fenster.
//   rasterTeil  dasselbe Fenster traegt MEHR Panes als gezeigt (Layout split):
//               die Lage von tmux gilt, fehlende Zellen werden zusammengeschoben.
//   frei/gebunden  Panes aus mehreren Fenstern: Kacheln nach der Reihenfolge,
//               Reihen aus `kachelReihen`, auf ganze Zellen abgerundet.
import CoreGraphics
import Foundation

public enum Kachelung {
    /// Die Fuge zwischen zwei Kacheln (paneflaeche.ts `FUGE`).
    public static let fuge: CGFloat = 4

    /// Ein Rechteck in Bildpunkten, Ursprung oben links (wie der Renderer rechnet).
    public struct Rechteck: Equatable, Sendable {
        public var x: CGFloat
        public var y: CGFloat
        public var b: CGFloat
        public var h: CGFloat
        public init(x: CGFloat, y: CGFloat, b: CGFloat, h: CGFloat) { self.x = x; self.y = y; self.b = b; self.h = h }
    }

    public struct Zelle: Equatable, Sendable {
        public var breite: CGFloat
        public var hoehe: CGFloat
        public init(breite: CGFloat, hoehe: CGFloat) { self.breite = breite; self.hoehe = hoehe }
    }

    /// Wieviele Kacheln in welcher Reihe stehen (capacity.ts `kachelReihen`).
    public static func reihen(anzahl: Int, spalten: Int, frei: Bool) -> [Int] {
        let n = max(0, anzahl)
        if n <= 0 { return [] }
        let s = max(1, spalten)
        let zeilen = max(1, Int((Double(n) / Double(s)).rounded(.up)))
        if !frei { return (0..<zeilen).map { min(s, n - $0 * s) } }
        let grund = n / zeilen
        let rest = n % zeilen
        return (0..<zeilen).map { grund + ($0 < rest ? 1 : 0) }
    }

    /// Wieviele Kachelzeilen eine Lage hat -- VOR der Rechnung, weil je Zeile
    /// eine Kopfzeile von der Flaeche abgeht (paneflaeche.ts `zeilenZahlFuer`).
    public static func zeilenZahl(_ lage: LageNutzlast) -> Int {
        guard lage.art == "tab" else { return 1 }
        if lage.raster != nil || lage.rasterTeil != nil {
            return max(1, Set(lage.panes.map(\.y)).count)
        }
        let anzahl = lage.panes.count + lage.fehlend.count
        return max(1, Int((Double(anzahl) / Double(max(1, lage.spalten))).rounded(.up)))
    }

    /// Die Kachel EINES Panes aus seiner Lage im tmux-Fenster (`kachelAusRaster`).
    /// Die Trennspalte von tmux gehoert zur Kachel links bzw. oben davon, bis auf
    /// die Fuge.
    public static func ausRaster(_ box: LageNutzlast.Kachel, raster: LageNutzlast.Raster, flaeche: CGSize) -> Rechteck {
        let rc = CGFloat(max(1, raster.cols))
        let rr = CGFloat(max(1, raster.rows))
        let trennerRechts: CGFloat = box.x + box.cols >= raster.cols ? 0 : 1
        let trennerUnten: CGFloat = box.y + box.rows >= raster.rows ? 0 : 1
        return Rechteck(
            x: CGFloat(box.x) / rc * flaeche.width,
            y: CGFloat(box.y) / rr * flaeche.height,
            b: max(1, (CGFloat(box.cols) + trennerRechts) / rc * flaeche.width - trennerRechts * fuge),
            h: max(1, (CGFloat(box.rows) + trennerUnten) / rr * flaeche.height - trennerUnten * fuge))
    }

    /// Die Kacheln, wenn der Tab nur einen TEIL eines Fensters zeigt
    /// (`kachelnAusTeilraster`): Reihen auf volle Breite, zusammen auf volle Hoehe.
    public static func ausTeilraster(_ boxen: [LageNutzlast.Kachel], buehneZellen: (cols: Int, rows: Int), flaeche: CGSize) -> [Rechteck] {
        let reihen = Array(Set(boxen.map(\.y))).sorted()
        let hoeheJeReihe = reihen.map { y in boxen.filter { $0.y == y }.map(\.rows).max() ?? 1 }
        let summeHoehe = max(1, hoeheJeReihe.reduce(0, +))
        let hoehePasst = summeHoehe <= buehneZellen.rows
        var lagen: [String: Rechteck] = [:]
        var oben: CGFloat = 0
        for (n, y) in reihen.enumerated() {
            let inReihe = boxen.filter { $0.y == y }.sorted { $0.x < $1.x }
            let summeBreite = max(1, inReihe.map(\.cols).reduce(0, +))
            let breitePasst = summeBreite <= buehneZellen.cols
            let h = hoehePasst ? CGFloat(hoeheJeReihe[n]) / CGFloat(summeHoehe) * flaeche.height : flaeche.height / CGFloat(reihen.count)
            var links: CGFloat = 0
            for box in inReihe {
                let b = breitePasst ? CGFloat(box.cols) / CGFloat(summeBreite) * flaeche.width : flaeche.width / CGFloat(inReihe.count)
                lagen[box.paneId] = Rechteck(x: links, y: oben, b: b, h: h)
                links += b
            }
            oben += h
        }
        return boxen.map { lagen[$0.paneId] ?? Rechteck(x: 0, y: 0, b: flaeche.width, h: flaeche.height) }
    }

    /// Die freie oder gebundene Kachelung nach Reihenfolge (`kachelLage`): Fugen
    /// zuerst ab, dann auf ganze Zellen abgerundet; der Rest wird Fuge. `breiten`
    /// (Spalten je Pane) bleibt der Riegel gegen abgeschnittenen Text, wenn tmux
    /// eine Reihe ungleich verteilt hat.
    public static func nachReihenfolge(anzahl: Int, spalten: Int, frei: Bool, zelle: Zelle, flaeche: CGSize,
                                       breiten: [Int]? = nil, flaecheCols: Int? = nil) -> [Rechteck] {
        let reihen = reihen(anzahl: anzahl, spalten: spalten, frei: frei)
        if reihen.isEmpty { return [] }
        let nutzH = max(1, flaeche.height - CGFloat(reihen.count - 1) * fuge)
        let zeilenZellen = zelle.hoehe > 0 ? max(1, Int(floor(nutzH / CGFloat(reihen.count) / zelle.hoehe))) : 0
        let kachelH = zeilenZellen > 0 ? min(nutzH, CGFloat(zeilenZellen) * zelle.hoehe) : nutzH / CGFloat(reihen.count)
        let fugeH: CGFloat = reihen.count > 1 ? fuge + max(0, (nutzH - CGFloat(reihen.count) * kachelH) / CGFloat(reihen.count - 1)) : 0
        var lagen: [Rechteck] = []
        var n = 0
        var oben: CGFloat = 0
        for inZeile in reihen {
            let nutzB = max(1, flaeche.width - CGFloat(inZeile - 1) * fuge)
            let zellenB = zelle.breite > 0 ? max(1, Int(floor(nutzB / CGFloat(inZeile) / zelle.breite))) : 0
            let kachelB = zellenB > 0 ? min(nutzB, CGFloat(zellenB) * zelle.breite) : nutzB / CGFloat(inZeile)
            let cols: [Int] = breiten.map { Array($0.dropFirst(n).prefix(inZeile)) } ?? []
            let summe = cols.reduce(0, +)
            let zuBreit = cols.count == inZeile && zellenB > 0 && cols.contains { $0 > zellenB }
            let nachMass = zuBreit && cols.allSatisfy { $0 > 0 } && (flaecheCols ?? 0) > 0 && summe <= (flaecheCols ?? 0)
            let fugeB: CGFloat = inZeile <= 1 ? 0 : (nachMass ? fuge : fuge + max(0, (nutzB - CGFloat(inZeile) * kachelB) / CGFloat(inZeile - 1)))
            var x: CGFloat = 0
            for i in 0..<inZeile {
                let breite = nachMass ? CGFloat(cols[i]) / CGFloat(max(1, summe)) * nutzB : kachelB
                lagen.append(Rechteck(x: x, y: oben, b: breite, h: kachelH))
                x += breite + fugeB
            }
            oben += kachelH + fugeH
            n += inZeile
        }
        return lagen
    }

    /// Die Kacheln einer ganzen Lage in TERMINALFLAECHE (ohne Kopfzeilen), je
    /// gezeigtem Pane in Lage-Reihenfolge, danach je fehlendem Pane. `flaeche`
    /// ist die Flaeche fuer Terminals, also schon um die Kopfzeilen verkleinert.
    public static func kacheln(_ lage: LageNutzlast, zelle: Zelle, flaeche: CGSize) -> [Rechteck] {
        guard lage.art == "tab" else { return [Rechteck(x: 0, y: 0, b: flaeche.width, h: flaeche.height)] }
        if let r = lage.raster {
            return lage.panes.map { ausRaster($0, raster: r, flaeche: flaeche) }
        }
        if lage.rasterTeil != nil {
            return ausTeilraster(lage.panes, buehneZellen: (lage.cols, lage.rows), flaeche: flaeche)
        }
        return nachReihenfolge(anzahl: lage.panes.count + lage.fehlend.count, spalten: lage.spalten, frei: lage.frei,
                               zelle: zelle, flaeche: flaeche,
                               breiten: lage.panes.map(\.cols) + lage.fehlend.map { _ in 0 }, flaecheCols: lage.cols)
    }

    /// Die Kachelzeilen aus den Oberkanten der Kacheln (`reihenAus`): welche
    /// Kachel in welcher Zeile liegt, entscheidet ueber ihren Kopfzeilen-Versatz.
    public static func reihenIndex(_ kacheln: [Rechteck]) -> [Int] {
        let kanten = Array(Set(kacheln.map { Int(($0.y * 2).rounded()) })).sorted()
        return kacheln.map { k in kanten.firstIndex(of: Int((k.y * 2).rounded())) ?? 0 }
    }

    /// Die Flaeche fuer Terminals: die rohe Buehne minus eine Kopfzeile je
    /// Kachelzeile (`gitterFlaeche`). Beide Abnehmer -- die Meldung an tmux und
    /// die Kachelrechnung -- rechnen mit derselben Zahl.
    public static func terminalflaeche(roh: CGSize, kopf: CGFloat, kachelZeilen: Int) -> CGSize {
        CGSize(width: roh.width, height: max(1, roh.height - kopf * CGFloat(max(1, kachelZeilen))))
    }

    /// Wieviele Fugen eine Lage traegt: zwischen den Kachelzeilen und zwischen
    /// den Kacheln der dichtesten Zeile. Der Kern kennt die Fuge nicht -- er
    /// teilt die gemeldeten Zellen gleichmaessig (capacity.ts `kachelZellen`).
    /// Zieht die Meldung die Fugen vorher ab, ist jede Kachel so gross wie ihr
    /// Pane, und kein Terminal ragt um eine Zeile ueber seine Kachel hinaus
    /// (gemessen 06.09.: 24 Zeilen Pane in einer Kachel fuer 23).
    public static func fugen(_ lage: LageNutzlast) -> (waagerecht: Int, senkrecht: Int) {
        guard lage.art == "tab" else { return (0, 0) }
        if lage.raster != nil || lage.rasterTeil != nil {
            var jeZeile: [Int: Int] = [:]
            for p in lage.panes { jeZeile[p.y, default: 0] += 1 }
            return (max(0, (jeZeile.values.max() ?? 1) - 1), max(0, jeZeile.count - 1))
        }
        let r = reihen(anzahl: lage.panes.count + lage.fehlend.count, spalten: lage.spalten, frei: lage.frei)
        return (max(0, (r.max() ?? 1) - 1), max(0, r.count - 1))
    }

    /// Die Buehne in Zellen, wie sie dem Kern gemeldet wird (`flaecheInZellen`).
    public static func zellen(flaeche: CGSize, zelle: Zelle) -> (cols: Int, rows: Int)? {
        guard zelle.breite > 0, zelle.hoehe > 0, flaeche.width > 0, flaeche.height > 0 else { return nil }
        return (max(20, Int(floor(flaeche.width / zelle.breite))), max(5, Int(floor(flaeche.height / zelle.hoehe))))
    }
}
