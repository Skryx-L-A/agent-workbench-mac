// Werkbank -- der Mac-native Mantel um den Kern (app/, kopflos).
//
// Start:  Werkbank [--kopflos] [--terminal strom|attach] [--steuer-socket <pfad>]
// Umgebung: AWB_MANTEL_SOCKET, AWB_MANTEL_TOKEN (der Kern), AWBMAC_CONTROL_SOCKET
// (der eigene Steuerkanal), AWB_TMUX_SOCKET (fuer die attach-Bauart).
//
// AppKit-Hauptprogramm statt `@main App`: nur so laesst sich das Fenster bauen,
// OHNE es zu zeigen -- die Regel jeder Pruefung (regeln/tests-und-eingriffe.md).
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var optionen = Laufoptionen.lesen()
    var kern: KernVerbindung!
    var fenster: Fenster!
    var steuer: MacSteuerkanal?
    /// Der Kern, wenn DIESE App ihn gestartet hat (Doppelklick im Finder,
    /// Auftrag 4.3). Kam er von `mac/bin/starten`, bleibt das hier leer und
    /// niemand raeumt ihn hier ab.
    let kernstart = Kernstart()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // OHNE MANTEL-SOCKET IN DER UMGEBUNG STARTET DIE APP IHREN KERN SELBST.
        // Das ist der Weg des Doppelklicks: kein Skript hat vorher etwas
        // vorbereitet, also holt die App Laufverzeichnis, Token und Sockets
        // hier. Mit Socket in der Umgebung faellt der Aufruf durch (`nil`) und
        // es bleibt bei den gelesenen Optionen.
        if let a = kernstart.starten() {
            optionen.mantelSocket = a.mantelSocket
            optionen.mantelToken = a.mantelToken
            optionen.steuerSocket = a.steuerSocket
            optionen.laufdir = a.laufdir
            FileHandle.standardError.write(Data("Kern selbst gestartet: \(a.kernPfad), Steuerkanal \(a.kernSteuerkanal)\n".utf8))
        } else if let f = kernstart.fehler {
            FileHandle.standardError.write(Data("kein eigener Kern: \(f)\n".utf8))
        } else {
            // Der Kern gehoert einem anderen. Ohne diese Zeile sah ein Protokoll, dessen
            // AWB_MANTEL_SOCKET nur geerbt war, genauso aus wie ein erfolgreicher Start
            // (14.09.2026, test-mac-start.sh unter der laufenden Mac-Werkbank).
            FileHandle.standardError.write(Data("Kern von aussen vorgegeben: AWB_MANTEL_SOCKET=\(optionen.mantelSocket)\n".utf8))
        }
        kern = KernVerbindung(pfad: optionen.mantelSocket, token: optionen.mantelToken)
        fenster = Fenster(optionen: optionen, kern: kern)
        Menueleiste.bauen(fenster: fenster)
        kern.starten()

        if !optionen.steuerSocket.isEmpty {
            let s = MacSteuerkanal(pfad: optionen.steuerSocket, fenster: fenster, kern: kern, optionen: optionen)
            do {
                try s.lauschen()
                steuer = s
                FileHandle.standardError.write(Data("Steuerkanal: \(optionen.steuerSocket)\n".utf8))
            } catch {
                FileHandle.standardError.write(Data("kein Steuerkanal: \(error)\n".utf8))
            }
        }

        if optionen.kopflos {
            // Kein Dock, kein Fenster, kein Fokus. Das Fenster ist gebaut und
            // laesst sich fotografieren (Fenster.schuss), es ist nur nie „on screen".
            NSApp.setActivationPolicy(.accessory)
            fenster.fenster.layoutIfNeeded()
        } else if optionen.ohneFokus {
            // Sichtbar, aber ohne Fokusdiebstahl und HINTER allen anderen Fenstern
            // (regeln/tests-und-eingriffe.md). `orderBack` stellt das Fenster auf den
            // Bildschirm, ohne die App nach vorn zu holen; `orderFrontRegardless`
            // legte es beim Start fuer einige Sekunden vor die Arbeit des Menschen,
            // bis `agents zeigen` es zuruecklegte (16.09.2026). Belegbilder zeichnen
            // es auch verdeckt (Glasbeleg, `screencapture -l`).
            NSApp.setActivationPolicy(.regular)
            fenster.fenster.orderBack(nil)
        } else {
            NSApp.setActivationPolicy(.regular)
            fenster.fenster.makeKeyAndOrderFront(nil)
            NSApp.activate()
        }
        // Der gefuehrte erste Start (Auftrag 3.8): gebaut wird immer, gezeigt nur
        // beim ersten SICHTBAREN Start und nur, solange der Kern ihn nicht als
        // erledigt kennt (Erststart.swift, `erststartPruefen`).
        fenster.erststartPruefen()
        print("awbmac-ready \(optionen.steuerSocket)")
        fflush(stdout)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Kopflos gibt es kein „letztes Fenster"; sichtbar gilt die Mac-Vorgabe: App bleibt.
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        steuer?.schliessen()
        kern.beenden()
        // Wer startet, raeumt auch ab (regeln/prozess-hygiene.md): einen Kern,
        // den ein Skript gestartet hat, laesst diese Zeile in Ruhe -- sie kennt
        // nur den eigenen.
        kernstart.beenden()
    }
}

// AUS EINER AGENTEN-UMGEBUNG GESTARTET? DANN SAUBER NEU STARTEN (2026-09-10, gemessen).
// Ein Agent (Claude Code, pi) hat die Werkbank am 08.09. aus seiner Shell gestartet;
// die App trug seither CLAUDECODE=1 und die Sitzungsvariablen dieses Agenten. Jeder
// Kern und jede Freigabe aus dem Fenster erbte sie, und `wb-mensch` stufte des Nutzers
// Klick als Agent ein (Regel A1) -- drei Freigaben abgelehnt, "kein Mensch". Das
// Fenster gehoert dem Menschen; eine Agenten-Variable in seiner Umgebung ist immer ein
// Startfehler, nie ein Nachweis. Deshalb: einmal erkannt, startet sich die App ueber
// launchd (`open -n -a`) mit einer gesaeuberten Umgebung neu und beendet sich. Der
// Neustart bekommt keine der Variablen mit, also gibt es keine Schleife; sicherheitshalber
// verhindert WB_MANTEL_NEUSTART=1 einen zweiten Versuch. Was ein Mensch im Terminal
// startet (`mac/bin/starten`), traegt diese Variablen nie -- der Weg bleibt unberuehrt.
// AUSNAHME, gemessen 2026-09-10, 14:28: eine GESTEUERTE Instanz startet sich nie neu. Die
// Testsuite (test-mac-*.sh) oeffnet das Buendel per `open --env AWBMAC_CONTROL_SOCKET=...`
// aus einer Agenten-Shell; jede dieser Instanzen erkannte CLAUDECODE, startete sich sauber
// neu -- ohne den Steuersocket -- und blieb als Fenster stehen: elf Werkbank-Fenster auf
// Schirm des Nutzers, die Tests fanden ihre Instanz nicht. Eine Instanz mit
// AWBMAC_CONTROL_SOCKET oder AWBMAC_LAUFDIR ist kein Menschenfenster, sondern ein
// Pruefling; fuer sie gilt der Neustart nicht. Der Menschen-Nachweis (wb-mensch M2) haengt
// am Kern und an WB_APP_PID, nicht an dieser Ausnahme.
let agentenVariablen = ["CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT", "CLAUDE_CODE_SESSION_ID", "PI_AGENT", "WB_AGENT"]
let startUmgebung = ProcessInfo.processInfo.environment
let gesteuert = startUmgebung["AWBMAC_CONTROL_SOCKET"] != nil || startUmgebung["AWBMAC_LAUFDIR"] != nil
if startUmgebung["WB_MANTEL_NEUSTART"] == nil, !gesteuert,
   let treffer = agentenVariablen.first(where: { startUmgebung[$0] != nil }) {
    FileHandle.standardError.write(Data("Werkbank: aus einer Agenten-Umgebung gestartet (\(treffer) gesetzt) -- starte sauber neu.\n".utf8))
    let neu = Process()
    neu.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    neu.arguments = ["-n", "-a", Bundle.main.bundlePath]
    var sauber: [String: String] = ["WB_MANTEL_NEUSTART": "1"]
    for k in ["HOME", "USER", "LOGNAME", "SHELL", "LANG", "TMPDIR", "PATH"] {
        if let v = startUmgebung[k] { sauber[k] = v }
    }
    neu.environment = sauber
    do { try neu.run(); exit(0) } catch {
        FileHandle.standardError.write(Data("Werkbank: sauberer Neustart fehlgeschlagen (\(error)); laufe weiter, Freigaben bleiben ohne Menschen-Nachweis.\n".utf8))
    }
}

// Vor dem Kernstart: ein Finder-/Dock-Start hat weder node noch tmux im PATH (Umgebung.swift).
FileHandle.standardError.write(Data(Umgebung.herrichten().utf8))

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
