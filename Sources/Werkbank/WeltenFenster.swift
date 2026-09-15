// DAS FENSTER „AGENTS-WELTEN …" (14.09.2026, Auftrag agentsui). Plan Abschnitt
// 12, Schritt 4: „Vorab-Blatt zur Abnahme, dann Umbau des bestehenden
// AgentsBlatt.swift". Bis zur Abnahme stand die Ansicht nach Fassung 28 nur
// hier; seit Abnahme des Nutzers vom 14.09., 20:40 zeigt der Tab „Agents" des
// Hauptfensters dieselbe Ansicht an Ort und Stelle (Fenster.swift), und dieses
// Fenster bleibt als zweiter Zugang (Darstellung > Agents-Welten …, ⌃⌥⌘A).
// Beide teilen EINEN `WeltenZustand`: gewaehlte Welt, Agent, Entwuerfe und
// offene Formulare sind in beiden dieselben.
//
// Dieselbe Auflage wie beim Vorschau-Blatt der Figuren: `bauen` baut ohne zu
// zeigen (der Weg des Steuerkanals), `zeigen` ist der einzige Weg auf den
// Bildschirm und kopflos wirkungslos; unter `--ohne-fokus` steht das Fenster,
// ohne die App zu aktivieren.
import AppKit
import SwiftUI

@MainActor
final class WeltenFenster: NSObject, NSWindowDelegate {
    let zustand: WeltenZustand
    let fenster: NSWindow
    private let optionen: Laufoptionen
    /// Das Hauptfenster erfaehrt, ob die Welten stehen -- der Kern taktet dann schnell.
    var beiSichtbarkeit: () -> Void = {}
    var sichtbar: Bool { fenster.isVisible }

    static let rahmenName = "Werkbank.AgentsWelten"

    init(kern: KernVerbindung, zustand: WeltenZustand, optionen: Laufoptionen) {
        self.optionen = optionen
        self.zustand = zustand
        fenster = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                           backing: .buffered, defer: false)
        super.init()
        fenster.title = "Agents"
        fenster.toolbarStyle = .unified
        fenster.minSize = NSSize(width: 900, height: 560)
        fenster.isReleasedWhenClosed = false
        fenster.tabbingMode = .disallowed
        fenster.delegate = self
        fenster.identifier = NSUserInterfaceItemIdentifier("agents-welten")
        let inhalt = NSHostingController(rootView: WeltenBlatt(kern: kern, zustand: zustand))
        inhalt.sizingOptions = []
        // Symbolleiste und Titel kommen aus SwiftUI (`.toolbar`, `.navigationTitle`).
        inhalt.sceneBridgingOptions = [.toolbars, .title]
        fenster.contentViewController = inhalt
        fenster.setContentSize(NSSize(width: 1280, height: 820))
        // Die Lage merkt sich nur der Betrieb; eine Pruefung faesst die Voreinstellungen nie an (Merker.swift).
        if !optionen.pruefmodus { fenster.setFrameAutosaveName(Self.rahmenName) }
    }

    /// Der einzige Weg auf den Bildschirm. Kopflos wirkungslos.
    func zeigen() {
        guard !optionen.kopflos else { return }
        if optionen.ohneFokus {
            // Eine Sichtpruefung legt dieses Fenster HINTER alle anderen
            // (regeln/tests-und-eingriffe.md): `wb-shot` fotografiert es auch verdeckt.
            if !fenster.isVisible { fenster.center() }
            fenster.orderBack(nil)
        } else {
            fenster.vorZeigen(ohneFokus: false)
        }
        beiSichtbarkeit()
    }

    /// Ein Belegbild dieses Fensters (Glasbeleg unten).
    func schuss(pfad: String) throws -> (breite: Int, hoehe: Int, glas: Int) {
        try Glasbeleg.schuss(fenster, pfad: pfad)
    }

    func sichtbaum(tiefe: Int) -> [String] { Glasbeleg.sichtbaum(fenster, tiefe: tiefe) }

    /// Ist dieses Fenster vorn, zeigt es die Rueckfrage, sonst der Tab (WeltenZustand.rueckfrageImTab).
    func windowDidBecomeKey(_ notification: Notification) { zustand.fensterVorn = true }
    func windowDidResignKey(_ notification: Notification) { zustand.fensterVorn = false }

    func windowWillClose(_ notification: Notification) {
        zustand.fensterVorn = false
        DispatchQueue.main.async { [weak self] in self?.beiSichtbarkeit() }
    }
}

/// EIN BELEGBILD EINES ECHTEN FENSTERS MIT GLASFLAECHEN -- fuer das Fenster
/// „Agents-Welten …" und fuer den Tab „Agents" des Hauptfensters (`agents schuss`).
@MainActor
enum Glasbeleg {
    /// EIN BELEGBILD DES ECHTEN FENSTERS, im eigenen Prozess (14.09.2026). `wb-shot`
    /// braucht das Aufnahmerecht des aufrufenden Terminals; ohne es meldet
    /// `screencapture -l` „could not create image from window". Das Fenster
    /// zeichnet sich deshalb selbst mit `cacheDisplay` -- das taugt nur, solange
    /// es wirklich auf dem Bildschirm steht (`--ohne-fokus`).
    ///
    /// GLAS ZEICHNET SICH NICHT MIT (gemessen 14.09.): Leiste und Inspektor
    /// liegen unter macOS 26 in `NSContainerConcentricGlassEffectView`, deren
    /// Inhalt ein Portal zeigt; `cacheDisplay` liefert dort eine leere Flaeche
    /// (Leiste) oder einen Farbverlauf (Inspektor), obwohl die Liste ihre Zeilen
    /// gebaut hat. Der Beleg legt deshalb an jede grosse Glasflaeche eine Karte
    /// in Fensterfarbe und zeichnet die SwiftUI-Inhalte darin einzeln -- dieselben
    /// Views desselben Fensters. Das Glas selbst (Unschaerfe, Rand) fehlt im Bild,
    /// und im Dunkeln stehen manche Beschriftungen dort gedaempft: ihre lebhafte
    /// Mischung mit dem Glas zeichnet `cacheDisplay` nicht nach (gemessen: derselbe
    /// Textstil steht in der Mitte hell, und eine gewoehnliche Erscheinung fuer die
    /// Aufnahme aenderte daran nichts).
    static func schuss(_ fenster: NSWindow, pfad: String) throws -> (breite: Int, hoehe: Int, glas: Int) {
        guard fenster.isVisible, let rahmen = fenster.contentView?.superview else {
            throw NSError(domain: "Werkbank", code: 1, userInfo: [NSLocalizedDescriptionKey: "das Fenster steht nicht auf dem Bildschirm (erst zeigen, sichtbar ohne Fokus)"])
        }
        fenster.displayIfNeeded()
        rahmen.layoutSubtreeIfNeeded()
        guard let rep = rahmen.bitmapImageRepForCachingDisplay(in: rahmen.bounds), let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
            throw NSError(domain: "Werkbank", code: 2, userInfo: [NSLocalizedDescriptionKey: "keine Bitmap"])
        }
        let erscheinung = fenster.effectiveAppearance
        // Sichern und Wiederherstellen AM Bildkontext: die Klassenmethoden sichern den
        // Kontext, der vorher galt, und ein Beschnitt bliebe im Bild fuer alles Weitere stehen.
        func malen(_ block: () -> Void) {
            let vorher = NSGraphicsContext.current
            NSGraphicsContext.current = ctx
            ctx.saveGraphicsState()
            erscheinung.performAsCurrentDrawingAppearance(block)
            ctx.restoreGraphicsState()
            NSGraphicsContext.current = vorher
        }
        malen {
            NSColor.windowBackgroundColor.setFill()
            NSRect(origin: .zero, size: rahmen.bounds.size).fill()
        }
        rahmen.cacheDisplay(in: rahmen.bounds, to: rep)
        var glas: [NSView] = []
        func suche(_ v: NSView) {
            let name = String(describing: type(of: v))
            if name.contains("GlassEffectView"), v.bounds.width > 120, v.bounds.height > 120, !v.isHiddenOrHasHiddenAncestor {
                glas.append(v)
                return
            }
            v.subviews.forEach(suche)
        }
        suche(rahmen)
        // Die Gasse um die Glasflaechen (Unschaerfe) zeichnet sich schwarz: Fensterfarbe darunter.
        func gassen(_ v: NSView) {
            if String(describing: type(of: v)).contains("BlurryAlleyway") {
                let r = v.convert(v.bounds, to: nil)
                malen { NSColor.windowBackgroundColor.setFill(); r.fill() }
                return
            }
            v.subviews.forEach(gassen)
        }
        gassen(rahmen)
        for g in glas {
            let ziel = g.convert(g.bounds, to: nil)
            let karte = NSBezierPath(roundedRect: ziel.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12)
            malen {
                NSColor.controlBackgroundColor.setFill()
                karte.fill()
            }
            var inhalte: [NSView] = []
            func hosts(_ v: NSView) {
                if String(describing: type(of: v)).hasPrefix("NSHostingView") { inhalte.append(v); return }
                v.subviews.forEach(hosts)
            }
            g.subviews.filter { !String(describing: type(of: $0)).contains("CoreHostingView") }.forEach(hosts)
            for h in inhalte where !h.isHiddenOrHasHiddenAncestor {
                // Vorgelegt in Kartenfarbe: lebhafte Schrift mischt sich mit dem Grund darunter,
                // auf leerem Grund wuerde sie im Dunkeln fast schwarz.
                guard let teil = h.bitmapImageRepForCachingDisplay(in: h.bounds), let tctx = NSGraphicsContext(bitmapImageRep: teil) else { continue }
                let vorher = NSGraphicsContext.current
                NSGraphicsContext.current = tctx
                erscheinung.performAsCurrentDrawingAppearance {
                    NSColor.controlBackgroundColor.setFill()
                    NSRect(x: 0, y: 0, width: teil.pixelsWide, height: teil.pixelsHigh).fill()
                }
                NSGraphicsContext.current = vorher
                h.cacheDisplay(in: h.bounds, to: teil)
                let r = h.convert(h.bounds, to: nil)
                malen {
                    karte.addClip()
                    teil.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                }
            }
            malen {
                NSColor.separatorColor.setStroke()
                karte.stroke()
            }
        }
        // Die Symbolleiste liegt ueber dem Glas des Inspektors. Ihre Plaettchen sind
        // wieder Glas: sie bekommen eine Pille in Kartenfarbe, darauf kommen die
        // Elemente, der Titel und die drei Fensterknoepfe einzeln.
        if let leiste = rahmen.subviews.first(where: { String(describing: type(of: $0)).contains("TitlebarContainer") }) {
            var platten: [NSView] = [], teile: [NSView] = []
            func sammle(_ v: NSView) {
                let name = String(describing: type(of: v))
                if name.contains("ToolbarPlatterView") { platten.append(v); return }
                if name.contains("ToolbarItemViewer") || name.contains("ToolbarTitleView") || name.hasPrefix("_NSTheme") { teile.append(v); return }
                v.subviews.forEach(sammle)
            }
            sammle(leiste)
            let streifen = leiste.convert(leiste.bounds, to: nil)
            malen {
                NSColor.windowBackgroundColor.setFill()
                NSRect(x: 0, y: streifen.minY, width: streifen.width, height: streifen.height).intersection(streifen).fill()
            }
            for p in platten where !p.isHiddenOrHasHiddenAncestor {
                let r = p.convert(p.bounds, to: nil)
                malen {
                    let pille = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: r.height / 2, yRadius: r.height / 2)
                    NSColor.controlBackgroundColor.setFill()
                    pille.fill()
                    NSColor.separatorColor.setStroke()
                    pille.stroke()
                }
            }
            for v in teile where !v.isHiddenOrHasHiddenAncestor {
                guard let teil = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { continue }
                v.cacheDisplay(in: v.bounds, to: teil)
                let r = v.convert(v.bounds, to: nil)
                malen { teil.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil) }
            }
        }
        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "Werkbank", code: 4, userInfo: [NSLocalizedDescriptionKey: "kein PNG"])
        }
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: pfad).deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: URL(fileURLWithPath: pfad))
        return (rep.pixelsWide, rep.pixelsHigh, glas.count)
    }

    /// Der Sichtbaum des Rahmens (Klasse, Rahmen, verborgen) -- zur Fehlersuche an Belegbildern.
    static func sichtbaum(_ fenster: NSWindow, tiefe: Int) -> [String] {
        var raus: [String] = []
        func gehe(_ v: NSView, _ t: Int) {
            guard t <= tiefe else { return }
            let r = v.convert(v.bounds, to: nil)
            raus.append(String(repeating: "  ", count: t) + "\(type(of: v)) \(Int(r.minX)),\(Int(r.minY)) \(Int(r.width))x\(Int(r.height))\(v.isHidden ? " verborgen" : "")\(v.layer.map { " layer:\(type(of: $0))" } ?? "")")
            for s in v.subviews { gehe(s, t + 1) }
        }
        if let rahmen = fenster.contentView?.superview { gehe(rahmen, 0) }
        return raus
    }
}
