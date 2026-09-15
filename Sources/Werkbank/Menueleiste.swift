// Die Menueleiste mit den Standardmenues des Mac: Werkbank, Ablage,
// Bearbeiten, Darstellung, Fenster, Hilfe. Die Standardkuerzel bleiben, wo sie
// sind (plattformen.md, macOS): Escape bricht ab, ⌘Z nimmt zurueck, ⌘, oeffnet
// die Einstellungen, ⌃⌘S schaltet die Seitenleiste.
//
// JEDE HANDLUNG DES FENSTERS HAT HIER EINEN PUNKT MIT KUERZEL (Auftrag 2.8,
// abnahme.md Merkmal 11): Ablage (⌘N, ⌃⌘N, ⌃⇧⌘N), Sitzung (⌘R, ⌘⇧R, ⌥⌘R, ⌘⇧W, ⌘⌫), Darstellung (⌃⌘S,
// ⌥⌘A, ⌃⌘← ⌃⌘→ ⌃⇧⌘→, ⌘1, ⌘2, ⌘↩, ⌘] ⌘[, ⌘⇧] ⌘⇧[, ⌥⌘L, ⌥⌘B, ⌃⌘1-3, ⌘⇧H, ⌃⌘F), Gespräch (⌘., ⌘⇧M,
// ⌘⇧F, ⌘⇧Y, ⌘⇧N; Auftrag 3.2), Freigaben (⌥⌘I,
// ⌥⌘Y, ⌥⌘N, ⌥⌘] ⌥⌘[). Das Untermenue „Maschinen“ entsteht beim Aufklappen aus
// dem Modell (Fenster.menuNeedsUpdate). Fensterpunkte zielen ausdruecklich auf
// das Hauptfenster, damit sie auch ohne Schluesselfenster (kopflos) gehen und
// `awbmac-ctl menue` ihren Zustand liest.
import AppKit

@MainActor
enum Menueleiste {
    static func bauen(fenster: Fenster) {
        let haupt = NSMenu()

        // Werkbank
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Über Werkbank", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let einst = NSMenuItem(title: "Einstellungen …", action: #selector(Fenster.einstellungenZeigen(_:)), keyEquivalent: ",")
        einst.target = fenster
        appMenu.addItem(einst)
        // Die Verbrauchsseite (Auftrag 3.8) neben den Einstellungen: beides sind
        // Fenster ueber das Programm als Ganzes, nicht ueber eine Sitzung.
        let verbrauch = NSMenuItem(title: "Verbrauch …", action: #selector(Fenster.verbrauchZeigen(_:)), keyEquivalent: "v")
        verbrauch.keyEquivalentModifierMask = [.command, .option]
        verbrauch.target = fenster
        appMenu.addItem(verbrauch)
        appMenu.addItem(.separator())
        let dienste = NSMenuItem(title: "Dienste", action: nil, keyEquivalent: "")
        dienste.submenu = NSMenu()
        NSApp.servicesMenu = dienste.submenu
        appMenu.addItem(dienste)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Werkbank ausblenden", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let andere = appMenu.addItem(withTitle: "Andere ausblenden", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        andere.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Alle einblenden", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Werkbank beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        eintragen(haupt, "Werkbank", appMenu)

        // Ablage
        let ablage = NSMenu(title: "Ablage")
        // ⌘N: das Sitzungsfenster (Sitzungsblatt.swift, Auftrag 2.7) -- neu, fortsetzen, beenden.
        let neu = NSMenuItem(title: "Neue Sitzung …", action: #selector(Fenster.sitzungenZeigen(_:)), keyEquivalent: "n")
        neu.target = fenster
        ablage.addItem(neu)
        // DIE BEIDEN PLUSKNOEPFE DER LEISTE, auch ohne Maus (08.09.2026).
        //
        // DREI KUERZEL MIT N WAREN SCHON VERGEBEN, und zwei davon haetten still
        // gewonnen: ⌘N oeffnet das Sitzungsfenster, ⌥⌘N lehnt eine Freigabe ab
        // (Menue Freigaben), ⌘⇧N lehnt eine Freigabe im Gespraech ab. Frei sind
        // die Kombinationen mit ⌃, die hier bisher nur an der Seitenleiste
        // (⌃⌘S), an der Sortierung (⌃⌘1-3) und am Vollbild (⌃⌘F) haengen.
        let neuOrdner = NSMenuItem(title: "Neue Sitzung in einem Ordner …",
                                   action: #selector(Fenster.neueSitzungImOrdner(_:)), keyEquivalent: "n")
        neuOrdner.keyEquivalentModifierMask = [.command, .control]
        neuOrdner.target = fenster
        ablage.addItem(neuOrdner)
        let neuProjekt = NSMenuItem(title: "Neue Sitzung in diesem Projekt",
                                    action: #selector(Fenster.neueSitzungImProjekt(_:)), keyEquivalent: "N")
        neuProjekt.keyEquivalentModifierMask = [.command, .control, .shift]
        neuProjekt.target = fenster
        ablage.addItem(neuProjekt)
        ablage.addItem(.separator())
        // DIE AGENTS OHNE MAUS (Auftrag agentsux Nr. 1): eine Welt und einen Agenten anlegen.
        // Frei waren noch ⌃⌥⌘N und ⌥⇧⌘N; die anderen N-Kuerzel stehen oben beschrieben.
        let weltNeu = NSMenuItem(title: "Neue Welt in einem Projektordner …", action: #selector(Fenster.weltNeuImOrdner(_:)), keyEquivalent: "n")
        weltNeu.keyEquivalentModifierMask = [.command, .option, .control]
        weltNeu.target = fenster
        ablage.addItem(weltNeu)
        let agentNeu = NSMenuItem(title: "Agent anlegen …", action: #selector(Fenster.agentAnlegenMenue(_:)), keyEquivalent: "N")
        agentNeu.keyEquivalentModifierMask = [.command, .option, .shift]
        agentNeu.target = fenster
        ablage.addItem(agentNeu)
        ablage.addItem(.separator())
        // Der Editor (Auftrag 3.4): speichern, die Auswahl in den Orchestrator-
        // Pane, ein- und ausklappen, neu laden. ⌘⇧↩ ist der Weg des MENSCHEN in
        // den Orchestrator-Pane -- ueber den Steuerkanal bleibt er zu.
        let speichern = NSMenuItem(title: "Datei sichern", action: #selector(Fenster.dateiSpeichern(_:)), keyEquivalent: "s")
        speichern.target = fenster
        ablage.addItem(speichern)
        let senden = NSMenuItem(title: "Auswahl an den Orchestrator", action: #selector(Fenster.auswahlSenden(_:)), keyEquivalent: "\r")
        senden.keyEquivalentModifierMask = [.command, .shift]
        senden.target = fenster
        ablage.addItem(senden)
        let klappen = NSMenuItem(title: "Editor einklappen", action: #selector(Fenster.editorKlappen(_:)), keyEquivalent: "e")
        klappen.keyEquivalentModifierMask = [.command, .option]
        klappen.target = fenster
        ablage.addItem(klappen)
        let neuLaden = NSMenuItem(title: "Von der Platte neu laden", action: #selector(Fenster.editorNeuLaden(_:)), keyEquivalent: "u")
        neuLaden.keyEquivalentModifierMask = [.command, .option]
        neuLaden.target = fenster
        ablage.addItem(neuLaden)
        ablage.addItem(.separator())
        // ⌘W trifft die offene Datei, solange eine da ist, sonst das Fenster
        // (Fenster.dateiOderFensterSchliessen; der Titel folgt in validateMenuItem).
        let zuFenster = NSMenuItem(title: "Schließen", action: #selector(Fenster.dateiOderFensterSchliessen(_:)), keyEquivalent: "w")
        zuFenster.target = fenster
        ablage.addItem(zuFenster)
        eintragen(haupt, "Ablage", ablage)

        // Bearbeiten -- die Standardselektoren, damit Terminal und Textfelder sie bekommen.
        let bearbeiten = NSMenu(title: "Bearbeiten")
        bearbeiten.addItem(withTitle: "Widerrufen", action: Selector(("undo:")), keyEquivalent: "z")
        let wieder = bearbeiten.addItem(withTitle: "Wiederholen", action: Selector(("redo:")), keyEquivalent: "z")
        wieder.keyEquivalentModifierMask = [.command, .shift]
        bearbeiten.addItem(.separator())
        bearbeiten.addItem(withTitle: "Ausschneiden", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        bearbeiten.addItem(withTitle: "Kopieren", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        bearbeiten.addItem(withTitle: "Einfügen", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        bearbeiten.addItem(withTitle: "Alles auswählen", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        eintragen(haupt, "Bearbeiten", bearbeiten)

        // Sitzung -- dieselben fuenf Punkte wie das Kontextmenue der Leiste,
        // damit jede Handlung auch ohne Maus erreichbar ist (abnahme.md, Merkmal 11).
        let sitzung = NSMenu(title: "Sitzung")
        let fort = NSMenuItem(title: "Fortsetzen", action: #selector(Fenster.sitzungFortsetzen(_:)), keyEquivalent: "r")
        fort.target = fenster
        sitzung.addItem(fort)
        let name = NSMenuItem(title: "Namen ändern …", action: #selector(Fenster.sitzungUmbenennen(_:)), keyEquivalent: "r")
        name.keyEquivalentModifierMask = [.command, .shift]
        name.target = fenster
        sitzung.addItem(name)
        let ordner = NSMenuItem(title: "Ordner im Finder zeigen", action: #selector(Fenster.sitzungOrdnerZeigen(_:)), keyEquivalent: "r")
        ordner.keyEquivalentModifierMask = [.command, .option]
        ordner.target = fenster
        sitzung.addItem(ordner)
        sitzung.addItem(.separator())
        let zu = NSMenuItem(title: "Sitzung schließen", action: #selector(Fenster.sitzungSchliessen(_:)), keyEquivalent: "w")
        zu.keyEquivalentModifierMask = [.command, .shift]
        zu.target = fenster
        sitzung.addItem(zu)
        let weg = NSMenuItem(title: "Endgültig löschen …", action: #selector(Fenster.sitzungLoeschen(_:)), keyEquivalent: "\u{8}")
        weg.keyEquivalentModifierMask = [.command]
        weg.target = fenster
        sitzung.addItem(weg)
        eintragen(haupt, "Sitzung", sitzung)

        // Darstellung
        let darstellung = NSMenu(title: "Darstellung")
        let leiste = NSMenuItem(title: "Seitenleiste ein-/ausblenden", action: #selector(Fenster.seitenleisteUmschalten(_:)), keyEquivalent: "s")
        leiste.keyEquivalentModifierMask = [.command, .control]
        leiste.target = fenster
        darstellung.addItem(leiste)
        // Projekte zu- und aufklappen (Politur 08.09.). Das Chevron am
        // Abschnittskopf ist der Weg mit der Maus; hier steht derselbe Weg fuer
        // die Tastatur -- auf dem Mac ist jede Handlung ohne Maus erreichbar
        // (plattformen.md, macOS). Die Pfeiltasten mit ⌃⌘ waren frei.
        let projektZu = NSMenuItem(title: "Projekt einklappen", action: #selector(Fenster.projektEinklappen(_:)), keyEquivalent: "\u{F702}")
        projektZu.keyEquivalentModifierMask = [.command, .control]
        projektZu.target = fenster
        darstellung.addItem(projektZu)
        let projektAuf = NSMenuItem(title: "Projekt aufklappen", action: #selector(Fenster.projektAufklappen(_:)), keyEquivalent: "\u{F703}")
        projektAuf.keyEquivalentModifierMask = [.command, .control]
        projektAuf.target = fenster
        darstellung.addItem(projektAuf)
        let alleAuf = NSMenuItem(title: "Alle Projekte aufklappen", action: #selector(Fenster.alleProjekteAufklappen(_:)), keyEquivalent: "\u{F703}")
        alleAuf.keyEquivalentModifierMask = [.command, .control, .shift]
        alleAuf.target = fenster
        darstellung.addItem(alleAuf)
        darstellung.addItem(.separator())
        // Der Umschalter Code | Agents (Auftrag macagents): ⌥⌘A, weil ⌘1 bis
        // ⌘2 die Buehne DIESER Sitzung belegen, ⌥⌘1 bis ⌥⌘4 die Blaetter des
        // Inspektors und ⌃⌘1 bis ⌃⌘3 die Sortierung. Ein Haken sagt, welche
        // Buehne steht; derselbe Punkt schaltet zurueck.
        let agents = NSMenuItem(title: "Agents", action: #selector(Fenster.agentsUmschalten(_:)), keyEquivalent: "a")
        agents.keyEquivalentModifierMask = [.command, .option]
        agents.target = fenster
        darstellung.addItem(agents)
        // Das Vorschau-Blatt der Figuren (Bau-Schritt 4): ⇧⌥⌘A, gleich neben
        // Agents -- jeder eigene Punkt traegt ein Kuerzel (abnahme.md, Merkmal 11).
        let figuren = NSMenuItem(title: "Agentenfiguren …", action: #selector(Fenster.figurenZeigen(_:)), keyEquivalent: "a")
        figuren.keyEquivalentModifierMask = [.command, .option, .shift]
        figuren.target = fenster
        darstellung.addItem(figuren)
        // Das Vorab-Blatt der Agents nach Fassung 28 (WeltenFenster.swift): ⌃⌥⌘A, gleich daneben.
        let welten = NSMenuItem(title: "Agents-Welten …", action: #selector(Fenster.weltenZeigen(_:)), keyEquivalent: "a")
        welten.keyEquivalentModifierMask = [.command, .option, .control]
        welten.target = fenster
        darstellung.addItem(welten)
        let orch = NSMenuItem(title: "Orchestrator", action: #selector(Fenster.orchestratorZeigen(_:)), keyEquivalent: "1")
        orch.target = fenster
        darstellung.addItem(orch)
        let worker = NSMenuItem(title: "Worker", action: #selector(Fenster.workerZeigen(_:)), keyEquivalent: "2")
        worker.target = fenster
        darstellung.addItem(worker)
        // Die Kachel mit der Tastatur allein, und zurueck zu allen (Auftrag 2.3):
        // ⌘↩, weil Escape im Terminal der Anwendung dort gehoert.
        let zoom = NSMenuItem(title: "Kachel zoomen", action: #selector(Fenster.kachelZoomUmschalten(_:)), keyEquivalent: "\r")
        zoom.target = fenster
        darstellung.addItem(zoom)
        // Die Worker-Liste hinter der Pille, auch ohne Maus (abnahme.md, Merkmal 11).
        // Die Tastatur von Kachel zu Kachel und von Tab zu Tab (Auftrag 2.8).
        let kachelVor = NSMenuItem(title: "Nächste Kachel", action: #selector(Fenster.naechsteKachel(_:)), keyEquivalent: "]")
        kachelVor.target = fenster
        darstellung.addItem(kachelVor)
        let kachelZurueck = NSMenuItem(title: "Vorige Kachel", action: #selector(Fenster.vorigeKachel(_:)), keyEquivalent: "[")
        kachelZurueck.target = fenster
        darstellung.addItem(kachelZurueck)
        let tabVor = NSMenuItem(title: "Nächster Worker-Tab", action: #selector(Fenster.naechsterTab(_:)), keyEquivalent: "]")
        tabVor.keyEquivalentModifierMask = [.command, .shift]
        tabVor.target = fenster
        darstellung.addItem(tabVor)
        let tabZurueck = NSMenuItem(title: "Voriger Worker-Tab", action: #selector(Fenster.vorigerTab(_:)), keyEquivalent: "[")
        tabZurueck.keyEquivalentModifierMask = [.command, .shift]
        tabZurueck.target = fenster
        darstellung.addItem(tabZurueck)
        let liste = NSMenuItem(title: "Worker-Liste", action: #selector(Fenster.workerListeUmschalten(_:)), keyEquivalent: "l")
        liste.keyEquivalentModifierMask = [.command, .option]
        liste.target = fenster
        darstellung.addItem(liste)
        darstellung.addItem(.separator())
        // Was die Leiste zeigt und wie sie ordnet -- `showStopped` und `ui.sort` des Kerns.
        let beendete = NSMenuItem(title: "Beendete Sitzungen einblenden", action: #selector(Fenster.beendeteUmschalten(_:)), keyEquivalent: "b")
        beendete.keyEquivalentModifierMask = [.command, .option]
        beendete.target = fenster
        darstellung.addItem(beendete)
        let sortieren = NSMenuItem(title: "Sortieren nach", action: nil, keyEquivalent: "")
        let sortMenu = NSMenu(title: "Sortieren nach")
        // ⌃⌘1 bis ⌃⌘3, wie der Finder seine Sortierung belegt.
        for (i, (schluessel, titel)) in [("recent", "Zuletzt benutzt"), ("folder", "Ordner"), ("name", "Name")].enumerated() {
            let it = NSMenuItem(title: titel, action: #selector(Fenster.sortierungWaehlen(_:)), keyEquivalent: String(i + 1))
            it.keyEquivalentModifierMask = [.command, .control]
            it.representedObject = schluessel
            it.target = fenster
            sortMenu.addItem(it)
        }
        sortieren.submenu = sortMenu
        darstellung.addItem(sortieren)
        // Der Fuss ohne Maus: die Maschinenkarten (aus dem Modell, beim
        // Aufklappen gebaut) und der Hinweis.
        let maschinen = NSMenuItem(title: "Maschinen", action: nil, keyEquivalent: "")
        let maschinenMenu = NSMenu(title: "Maschinen")
        maschinenMenu.delegate = fenster
        maschinen.submenu = maschinenMenu
        darstellung.addItem(maschinen)
        let hinweis = NSMenuItem(title: "Hinweis ausblenden", action: #selector(Fenster.hinweisAusblenden(_:)), keyEquivalent: "h")
        hinweis.keyEquivalentModifierMask = [.command, .shift]
        hinweis.target = fenster
        darstellung.addItem(hinweis)
        darstellung.addItem(.separator())
        let voll = darstellung.addItem(withTitle: "Vollbild", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        voll.keyEquivalentModifierMask = [.command, .control]
        voll.target = fenster.fenster
        eintragen(haupt, "Darstellung", darstellung)

        // Blätter (Auftraege 3.5/3.6): welches der vier Blaetter der Inspektor
        // zeigt. ⌥⌘1 bis ⌥⌘4 wie Xcode seine Inspektoren belegt; ein zweites
        // Mal auf dasselbe Blatt klappt den Inspektor wieder ein.
        let blaetter = NSMenu(title: "Blätter")
        for (i, w) in BlattWahl.allCases.enumerated() {
            let aktion: Selector
            switch w {
            case .freigaben: aktion = #selector(Fenster.blattFreigaben(_:))
            case .ordner: aktion = #selector(Fenster.blattOrdner(_:))
            case .aktivitaet: aktion = #selector(Fenster.blattAktivitaet(_:))
            case .protokolle: aktion = #selector(Fenster.blattProtokolle(_:))
            }
            let it = NSMenuItem(title: w.titel, action: aktion, keyEquivalent: String(i + 1))
            it.keyEquivalentModifierMask = [.command, .option]
            it.target = fenster
            blaetter.addItem(it)
        }
        eintragen(haupt, "Blätter", blaetter)

        // Freigaben (Auftrag 2.4): das Blatt, und die Leiste ohne Maus.
        let freigaben = NSMenu(title: "Freigaben")
        // Er schaltet den INSPEKTOR, nicht nur die Freigaben: dieselben vier
        // Blaetter, die auch der Knopf oben rechts oeffnet (Politur 08.09.).
        let blatt = NSMenuItem(title: "Inspektor ein-/ausblenden", action: #selector(Fenster.freigabenUmschalten(_:)), keyEquivalent: "i")
        blatt.keyEquivalentModifierMask = [.command, .option]
        blatt.target = fenster
        freigaben.addItem(blatt)
        freigaben.addItem(.separator())
        let frei = NSMenuItem(title: "Freigeben", action: #selector(Fenster.freigabeFreigeben(_:)), keyEquivalent: "y")
        frei.keyEquivalentModifierMask = [.command, .option]
        frei.target = fenster
        freigaben.addItem(frei)
        let ab = NSMenuItem(title: "Ablehnen", action: #selector(Fenster.freigabeAblehnen(_:)), keyEquivalent: "n")
        ab.keyEquivalentModifierMask = [.command, .option]
        ab.target = fenster
        freigaben.addItem(ab)
        freigaben.addItem(.separator())
        let vor = NSMenuItem(title: "Nächste Freigabe", action: #selector(Fenster.freigabeVor(_:)), keyEquivalent: "]")
        vor.keyEquivalentModifierMask = [.command, .option]
        vor.target = fenster
        freigaben.addItem(vor)
        let zurueck = NSMenuItem(title: "Vorige Freigabe", action: #selector(Fenster.freigabeZurueck(_:)), keyEquivalent: "[")
        zurueck.keyEquivalentModifierMask = [.command, .option]
        zurueck.target = fenster
        freigaben.addItem(zurueck)
        eintragen(haupt, "Freigaben", freigaben)

        // Gespraech (Auftrag 3.2): jede Handlung der Chat-Buehne ohne Maus --
        // Halt ⌘., Freigabe erlauben ⌘⇧Y / ablehnen ⌘⇧N, Modus ⌘⇧M, frisch starten ⌘⇧F.
        // Grau, solange kein Gespraech liegt (Fenster.validateMenuItem).
        let gespraech = NSMenu(title: "Gespräch")
        let halt = NSMenuItem(title: "Zug unterbrechen", action: #selector(Fenster.chatHalt(_:)), keyEquivalent: ".")
        halt.target = fenster
        gespraech.addItem(halt)
        let modus = NSMenuItem(title: "Freigabemodus weiterschalten", action: #selector(Fenster.chatModusWeiter(_:)), keyEquivalent: "m")
        modus.keyEquivalentModifierMask = [.command, .shift]
        modus.target = fenster
        gespraech.addItem(modus)
        let frisch = NSMenuItem(title: "Frisch starten", action: #selector(Fenster.chatNeustart(_:)), keyEquivalent: "f")
        frisch.keyEquivalentModifierMask = [.command, .shift]
        frisch.target = fenster
        gespraech.addItem(frisch)
        gespraech.addItem(.separator())
        let erlauben = NSMenuItem(title: "Freigabe erlauben", action: #selector(Fenster.chatFreigabeErlauben(_:)), keyEquivalent: "y")
        erlauben.keyEquivalentModifierMask = [.command, .shift]
        erlauben.target = fenster
        gespraech.addItem(erlauben)
        let ablehnen = NSMenuItem(title: "Freigabe ablehnen", action: #selector(Fenster.chatFreigabeAblehnen(_:)), keyEquivalent: "n")
        ablehnen.keyEquivalentModifierMask = [.command, .shift]
        ablehnen.target = fenster
        gespraech.addItem(ablehnen)
        eintragen(haupt, "Gespräch", gespraech)

        // Fenster
        let fensterMenu = NSMenu(title: "Fenster")
        let dock = fensterMenu.addItem(withTitle: "Im Dock ablegen", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        dock.target = fenster.fenster
        let zoomen = fensterMenu.addItem(withTitle: "Zoomen", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        zoomen.target = fenster.fenster
        fensterMenu.addItem(.separator())
        fensterMenu.addItem(withTitle: "Alle nach vorne bringen", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        NSApp.windowsMenu = fensterMenu
        eintragen(haupt, "Fenster", fensterMenu)

        // Hilfe
        let hilfe = NSMenu(title: "Hilfe")
        hilfe.addItem(withTitle: "Werkbank-Hilfe", action: #selector(NSApplication.showHelp(_:)), keyEquivalent: "?")
        NSApp.helpMenu = hilfe
        eintragen(haupt, "Hilfe", hilfe)

        NSApp.mainMenu = haupt
    }

    private static func eintragen(_ haupt: NSMenu, _ titel: String, _ menu: NSMenu) {
        let item = NSMenuItem(title: titel, action: nil, keyEquivalent: "")
        item.submenu = menu
        menu.title = titel
        haupt.addItem(item)
    }
}
