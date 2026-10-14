// Umgebung eines aus dem Finder oder Dock gestarteten Mantels herrichten.
//
// BEFUND VOM 13.09. der Nutzer startete die Werkbank.app per Doppelklick; keine
// Sitzung liess sich fortsetzen oder neu starten. `mac-lauf/kern.log` enthielt
// nur `env: node: No such file or directory`: der Mantel startete den Kern
// damals ueber `node_modules/.bin/electron`, ein Skript mit
// `#!/usr/bin/env node`. launchd gibt einer GUI-Anwendung nur
// `PATH=/usr/bin:/bin:/usr/sbin:/sbin` (gemessen am laufenden Mantel).
// Homebrew mit `tmux` und den Werkbankwerkzeugen liegt nicht darin. Der Kern
// startet Electron inzwischen unmittelbar aus seinem Paket; ein `node` im PATH
// ist dafuer nicht mehr erforderlich. Aus einem Terminal gestartet erbte die
// App den vollen PATH, deshalb fiel es vorher nicht auf.
//
// Derselbe Weg wie im Kern (`app/src/main/pfad.ts`, Befund vom 07.08.): die
// Anmelde-Shell nach PATH und Sprachumgebung fragen, Fehlendes ANHAENGEN (nie
// voranstellen, damit Stellvertreter der Tests vorn bleiben), und eine
// UTF-8-Sprachumgebung nur setzen, wenn keine der drei Variablen gesetzt ist.
// Ergebnis per `setenv`, damit jeder Kindprozess (Kern, tmux-Client) es erbt.
import Foundation

enum Umgebung {
    static let marke = "__AWB_UMGEBUNG__"
    static let localeVariablen = ["LC_ALL", "LC_CTYPE", "LANG"]

    /// DER ORDNER DER HARNESS-SYMLINKS GEHOERT NICHT IN DEN PATH DER WERKBANK (11.10.2026, Auftrag
    /// app-path). `shell/wb-harness-run` stellt `~/.local/state/wb-harness-bin` vor den PATH eines
    /// Harness-Starts; eine aus so einem Pane gestartete Werkbank erbte ihn, und der Harness-Updater
    /// des Kerns fand auf peer die Symlinks statt der mise-Shims. Entfernt wird jeder Eintrag, dessen
    /// realpath dem des Ordners entspricht (auch mit `~/` vorn oder `/` hinten); sonst bleibt der PATH
    /// unveraendert. Dasselbe tut `app/src/main/pfad.ts` fuer den Kern.
    static func harnessBinEntfernen(pfad: String, heim: String = NSHomeDirectory()) -> String {
        func echt(_ p: String) -> String {
            URL(fileURLWithPath: p).resolvingSymlinksInPath().standardizedFileURL.path
        }
        let ziel = echt((heim as NSString).appendingPathComponent(".local/state/wb-harness-bin"))
        return pfad.split(separator: ":", omittingEmptySubsequences: false).map(String.init).filter { e in
            if e.isEmpty { return true }
            let voll = e == "~" ? heim : e.hasPrefix("~/") ? (heim as NSString).appendingPathComponent(String(e.dropFirst(2))) : e
            return echt(voll) != ziel
        }.joined(separator: ":")
    }

    /// PATH-Eintraege aus `dazu`, die in `geerbt` fehlen, hinten angehaengt.
    static func pfadZusammenfuehren(geerbt: String, dazu: String) -> String {
        var teile = geerbt.split(separator: ":").map(String.init).filter { !$0.isEmpty }
        for t in dazu.split(separator: ":").map(String.init) where !t.isEmpty && !teile.contains(t) {
            teile.append(t)
        }
        return teile.joined(separator: ":")
    }

    /// Zeilen mit der Marke aus der Ausgabe der Anmelde-Shell; je Variable die letzte.
    static func zerlegen(_ ausgabe: String) -> [String: String] {
        var werte: [String: String] = [:]
        for zeile in ausgabe.split(separator: "\n") where zeile.hasPrefix(marke) {
            let rest = zeile.dropFirst(marke.count)
            guard let gleich = rest.firstIndex(of: "="), gleich != rest.startIndex else { continue }
            werte[String(rest[..<gleich])] = String(rest[rest.index(after: gleich)...]).trimmingCharacters(in: .whitespaces)
        }
        return werte
    }

    /// Die Anmelde-Shell fragen. `-lc`, nicht `-ilc`: eine interaktive Shell kann
    /// auf Eingabe warten. Nach `zeitlimit` Sekunden geht der Start ohne sie weiter.
    static func anmeldeShellWerte(env: [String: String], zeitlimit: TimeInterval = 5) -> [String: String] {
        let s = (env["SHELL"] ?? "").trimmingCharacters(in: .whitespaces)
        let shell = s.hasPrefix("/") ? s : "/bin/sh"
        guard FileManager.default.isExecutableFile(atPath: shell) else { return [:] }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: shell)
        p.arguments = ["-lc", "printf '\(marke)%s\\n' \"PATH=$PATH\" \"LC_ALL=${LC_ALL-}\" \"LC_CTYPE=${LC_CTYPE-}\" \"LANG=${LANG-}\""]
        p.environment = env
        let rohr = Pipe()
        p.standardOutput = rohr
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return [:] }
        let ende = Date().addingTimeInterval(zeitlimit)
        while p.isRunning && Date() < ende { usleep(10_000) }
        if p.isRunning { p.terminate(); return [:] }
        let daten = rohr.fileHandleForReading.readDataToEndOfFile()
        return zerlegen(String(decoding: daten, as: UTF8.self))
    }

    /// PATH und Sprachumgebung im eigenen Prozess setzen. Gibt eine Zeile fuer stderr zurueck.
    @discardableResult
    static func herrichten(env: [String: String] = ProcessInfo.processInfo.environment) -> String {
        let werte = anmeldeShellWerte(env: env)
        let geerbt = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let heim = (env["HOME"] ?? "").hasPrefix("/") ? env["HOME"]! : NSHomeDirectory()
        let bereinigt = harnessBinEntfernen(pfad: geerbt, heim: heim)
        let neu = pfadZusammenfuehren(geerbt: bereinigt, dazu: harnessBinEntfernen(pfad: werte["PATH"] ?? "", heim: heim))
        if neu != geerbt { setenv("PATH", neu, 1) }
        var locale = ""
        if !localeVariablen.contains(where: { !(env[$0] ?? "").isEmpty }) {
            if let k = localeVariablen.first(where: { !(werte[$0] ?? "").isEmpty }), let w = werte[k] {
                setenv(k, w, 1); locale = "\(k)=\(w)"
            } else {
                setenv("LC_CTYPE", "UTF-8", 1); locale = "LC_CTYPE=UTF-8"
            }
        }
        return "Umgebung: PATH \(neu == geerbt ? "unveraendert" : "ergaenzt")\(werte.isEmpty ? " (Anmelde-Shell ohne Antwort)" : "")\(locale.isEmpty ? "" : ", \(locale)")\n"
    }
}
