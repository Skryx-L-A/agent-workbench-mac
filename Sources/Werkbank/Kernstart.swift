// DIE APP STARTET IHREN KERN SELBST (06.09.2026, Auftrag 4.3).
//
// Bis heute gab es genau einen Weg in die Mac-Fassung: `mac/bin/starten`. Das
// Skript legte das Laufverzeichnis an, wuerfelte den Token, startete den Kern
// (app/, kopflos) und danach die App -- die App fand ihren Mantel-Socket
// fertig in der Umgebung vor. Ein Doppelklick im Finder fand dort nichts und
// zeigte deshalb ein Fenster ohne Kern.
//
// Diese Datei ist der zweite Weg. Fehlt `AWB_MANTEL_SOCKET` in der Umgebung,
// besorgt die App sich alles selbst: Laufverzeichnis, Token, Socketpfade, den
// Kern als eigenes Kind. Ist die Variable gesetzt, faellt hier gar nichts an --
// dann gehoert der Kern dem Skript, und zwei Besitzer fuer denselben Prozess
// waeren genau die Sorte Doppelzustaendigkeit, die beim Beenden schiefgeht.
//
// WER STARTET, RAEUMT AUCH AB (regeln/prozess-hygiene.md): `beenden()` haengt
// an `applicationWillTerminate` und nimmt den ganzen Baum mit -- Electron
// haengt seine Helfer als Kinder darunter, und ein SIGTERM allein an die
// Wurzel liess sie als Waisen stehen (derselbe Befund wie in
// `mac/bin/starten`, Funktion `baum_beenden`).
//
// DIE INSTALLIERTE APP STARTET IHREN KERN FEST (14.10.2026, Entscheidung der Nutzer
// zum Menschen-Nachweis M2, shell/wb-mensch). M2 nimmt einen Klick als menschlich,
// wenn er aus dem Kern kommt, den /Applications/Werkbank.app gestartet hat. Bis
// heute reichte die App ihre eigene Umgebung an den Kern weiter, und den Kernpfad
// nahm sie aus AWB_APP_DIR oder der Einstellung `macKernPfad`. Ein
// `open --env NODE_OPTIONS=--require=<datei> -a Werkbank` brachte so fremden Code
// in den echten Kern unter der echten App. Im installierten Betrieb gilt deshalb:
//   - Kernordner nur aus der Info.plist des Buendels (`WBKernPfad`, gesetzt von
//     mac/bin/installieren VOR dem Signieren), kein AWB_APP_DIR, keine Einstellung;
//   - Programm ist das Kern-Electron mit abgeschalteten Fuses
//     (<kern>/kern-electron, app/tools/kern-electron.mjs), nie node_modules;
//   - Argumente fest (`<kernordner> --headless`), Arbeitsordner der Kernordner;
//   - Umgebung aus einer Positivliste (`kernUmgebung`), HOME/USER/SHELL aus der
//     Benutzerdatenbank, PATH fest. Was die Liste enthaelt, ist am 14.10. am
//     laufenden Kern gemessen: genau die launchd-Umgebung eines Finder-Starts.
// Dev- und Testbuendel (mac/build/Werkbank.app, jedes Buendel ausserhalb von
// /Applications) behalten den bisherigen Weg; sie sind fuer M2 ohnehin kein
// Menschen-Nachweis.
import Foundation

@MainActor
final class Kernstart {
    /// Was der Start ergeben hat -- dieselben Werte, die `mac/bin/starten` sonst
    /// in die Umgebung schreibt.
    struct Aufbau {
        var laufdir: String
        var mantelSocket: String
        var mantelToken: String
        var steuerSocket: String
        /// Der Steuerkanal des KERNS (awb-ctl), nicht der der App.
        var kernSteuerkanal: String
        var kernPfad: String
    }

    /// Wo die installierte App liegt -- derselbe Pfad, den wb-mensch (M2_APP_MAC)
    /// als Elternprozess des Kerns verlangt.
    static let installiertesBuendel = "/Applications/Werkbank.app"

    /// Laeuft DIESES Buendel als installierte App?
    static func istInstalliert(buendel: URL = Bundle.main.bundleURL) -> Bool {
        buendel.resolvingSymlinksInPath().standardizedFileURL.path == installiertesBuendel
    }

    /// Variablen, die aus der Umgebung der App in den Kern duerfen (installierter
    /// Betrieb). Nur Sprache, Agent-Socket und die launchd-Kennungen; nichts, was
    /// Code laden kann (NODE_*, ELECTRON_*, DYLD_*), kein AWB_*/WB_*.
    static let umgebungDurchlass: Set<String> = [
        "LANG", "LC_ALL", "LC_CTYPE", "LC_MESSAGES", "LC_COLLATE", "LC_NUMERIC", "LC_TIME", "LC_MONETARY",
        "SSH_AUTH_SOCK", "__CF_USER_TEXT_ENCODING", "COMMAND_MODE", "XPC_FLAGS", "XPC_SERVICE_NAME",
        "OSLogRateLimit", "__CFBundleIdentifier",
    ]
    /// Der PATH eines Finder-Starts (launchd). Den vollen PATH holt der Kern sich
    /// selbst ueber die Anmelde-Shell (app/src/main/pfad.ts).
    static let festerPfad = "/usr/bin:/bin:/usr/sbin:/sbin"

    /**
     Die Umgebung des Kerns im installierten Betrieb: Durchlassliste aus `geerbt`,
     dazu HOME, USER, LOGNAME, SHELL aus der Benutzerdatenbank, PATH fest, TMPDIR
     aus dem System. Die AWB_-Werte des Starts setzt `starten` danach.
     */
    static func kernUmgebung(geerbt: [String: String], heim: String, name: String,
                             shell: String, tmp: String) -> [String: String] {
        var u = geerbt.filter { umgebungDurchlass.contains($0.key) }
        u["HOME"] = heim
        u["USER"] = name
        u["LOGNAME"] = name
        u["SHELL"] = shell
        u["PATH"] = festerPfad
        u["TMPDIR"] = tmp
        return u
    }

    /// Heim, Name und Shell aus der Benutzerdatenbank, nie aus $HOME.
    static func konto() -> (heim: String, name: String, shell: String) {
        guard let pw = getpwuid(getuid()) else { return (NSHomeDirectory(), NSUserName(), "/bin/zsh") }
        return (String(cString: pw.pointee.pw_dir), String(cString: pw.pointee.pw_name),
                String(cString: pw.pointee.pw_shell))
    }

    /// Das benutzereigene Temp-Verzeichnis des Systems (confstr), nicht $TMPDIR.
    static func systemTmp() -> String {
        var puffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        let n = confstr(_CS_DARWIN_USER_TEMP_DIR, &puffer, puffer.count)
        return n > 0 ? String(cString: puffer) : NSTemporaryDirectory()
    }

    private var kern: Process?
    private(set) var aufbau: Aufbau?
    /// Was schiefging, falls nichts lief -- das Fenster zeigt es als Kanalfehler.
    private(set) var fehler: String?

    // MARK: - Wo liegt der Kern

    /**
     Der Ordner `app/` mit dem Electron-Kern, in dieser Reihenfolge:

     1. `AWB_APP_DIR` aus der Umgebung -- der ausdrueckliche Weg, den auch eine
        Pruefung nimmt.
     2. Der Schluessel `macKernPfad` in `~/.claude/workbench/settings.json`
        (derselben Datei, die `wb-state settings get` liest). Er hat bewusst
        KEINEN Vorgabewert in `wb-state`: ein Pfad, der von Maschine zu
        Maschine verschieden ist, taugt nicht als Vorgabe -- fehlt der
        Schluessel, sucht Schritt 3.
     3. Neben dem Buendel. `mac/build/Werkbank.app` liegt im Baum, also liegt
        `app/` zwei Ebenen darueber; ein kopiertes Buendel in `/Applications`
        findet auf diesem Weg nichts und braucht Schritt 1 oder 2.

     Genommen wird nur, was wirklich ein gebauter Kern ist: `package.json` UND
     `dist/main/main.js`. Ein halb gebautes `app/` waere sonst ein Kern, der
     sofort wieder stirbt, und die Meldung darueber stuende nur im Protokoll.
     */
    static func kernPfadFinden(env: [String: String] = ProcessInfo.processInfo.environment,
                               buendel: URL = Bundle.main.bundleURL) -> String? {
        // Installiert: nur der Eintrag in der signierten Info.plist (Kopf).
        if istInstalliert(buendel: buendel) {
            guard let p = Bundle(url: buendel)?.infoDictionary?["WBKernPfad"] as? String,
                  p.hasPrefix("/"), istKern(p) else { return nil }
            return p
        }
        var kandidaten: [String] = []
        if let p = env["AWB_APP_DIR"], !p.isEmpty { kandidaten.append(p) }
        if let p = einstellung("macKernPfad", env: env), !p.isEmpty { kandidaten.append(p) }
        // …/mac/build/Werkbank.app -> …/mac/build -> …/mac -> … (Baumwurzel)
        let wurzel = buendel.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        kandidaten.append(wurzel.appendingPathComponent("app").path)
        // Und direkt neben dem Buendel, fuer eine Auslieferung, die beides in
        // denselben Ordner legt.
        kandidaten.append(buendel.deletingLastPathComponent().appendingPathComponent("app").path)
        for k in kandidaten where istKern(k) { return (k as NSString).expandingTildeInPath }
        return nil
    }

    private static func istKern(_ pfad: String) -> Bool {
        let p = (pfad as NSString).expandingTildeInPath
        let f = FileManager.default
        return f.fileExists(atPath: p + "/package.json") && f.fileExists(atPath: p + "/dist/main/main.js")
    }

    /// Die eigentliche Electron-Binaerdatei, nicht `node_modules/.bin/electron`.
    /// Der .bin-Eintrag ist ein Skript mit `#!/usr/bin/env node`; ein Finder-Start
    /// wuerde damit einen beliebigen `node` aus PATH als Zwischenprozess starten.
    /// Die Electron-Binaerdatei ist Teil des zum Kern gehoerenden Pakets und wird
    /// auf Apple Silicon unmittelbar nativ ausgefuehrt.
    static func electronPfad(kernPfad: String) -> String {
        "\(kernPfad)/node_modules/electron/dist/Electron.app/Contents/MacOS/Electron"
    }

    /// Das Kern-Electron mit abgeschalteten Fuses (app/tools/kern-electron.mjs).
    /// Es laedt den Kern wie node_modules-Electron ueber das Ordner-Argument.
    static func kernElectronPfad(kernPfad: String) -> String {
        "\(kernPfad)/kern-electron/Electron.app/Contents/MacOS/Electron"
    }

    /// Ein einzelner Wert aus der Einstellungsdatei, ohne Schema und ohne
    /// Schreibweg: gelesen wird hier nur (geschrieben wird ausschliesslich
    /// ueber `wb-state settings set`, siehe app/src/main/einstellungen.ts).
    private static func einstellung(_ schluessel: String, env: [String: String]) -> String? {
        let heim = env["HOME"] ?? NSHomeDirectory()
        let pfad = env["AWB_SETTINGS_FILE"] ?? "\(heim)/.claude/workbench/settings.json"
        guard let daten = FileManager.default.contents(atPath: pfad),
              let obj = try? JSONSerialization.jsonObject(with: daten) as? [String: Any],
              let wert = obj[schluessel] as? String else { return nil }
        return wert
    }

    // MARK: - Starten

    /**
     Kern starten und die Pfade dafuer festlegen. Gibt `nil` zurueck, wenn die
     Umgebung schon einen Mantel-Socket mitbringt (dann gehoert der Kern einem
     anderen) -- der Aufrufer nimmt in dem Fall seine bisherigen Optionen.
     */
    func starten(env geerbt: [String: String] = ProcessInfo.processInfo.environment,
                 optionen: Laufoptionen? = nil) -> Aufbau? {
        guard (geerbt["AWB_MANTEL_SOCKET"] ?? "").isEmpty else { return nil }

        // Installiert zaehlt von der geerbten Umgebung nur die Durchlassliste --
        // auch fuer Laufverzeichnis und Steuerkanal, damit kein AWBMAC_*/AWB_*
        // aus `open --env` den Start lenkt.
        let installiert = Self.istInstalliert()
        let k = Self.konto()
        let env = installiert
            ? Self.kernUmgebung(geerbt: geerbt, heim: k.heim, name: k.name, shell: k.shell, tmp: Self.systemTmp())
            : geerbt
        // Der eigene Steuerkanal nur ausdruecklich oder in einer Pruefung (Laufoptionen.steuerkanal).
        // Installiert zaehlt dafuer nur, was die gefilterte Umgebung und die Befehlszeile hergeben:
        // ein AWBMAC_CONTROL_SOCKET aus `open --env` oeffnet keinen Steuerkanal.
        let optionen = installiert ? Laufoptionen.lesen(env: env) : (optionen ?? Laufoptionen.lesen(env: env))
        let heim = env["HOME"] ?? NSHomeDirectory()
        let laufdir = env["AWBMAC_LAUFDIR"] ?? "\(heim)/.config/agent-workbench/mac-lauf"
        guard let kernPfad = Self.kernPfadFinden(env: env) else {
            fehler = installiert
                ? "kein Kern gefunden -- WBKernPfad fehlt in der Info.plist oder zeigt auf keinen gebauten Kern (mac/bin/installieren)"
                : "kein Kern gefunden -- 'app/' liegt weder neben dem Buendel noch unter der Einstellung 'macKernPfad'"
            return nil
        }
        do {
            try FileManager.default.createDirectory(atPath: laufdir, withIntermediateDirectories: true)
        } catch {
            fehler = "Laufverzeichnis \(laufdir) nicht anlegbar: \(error.localizedDescription)"
            return nil
        }

        let a = Aufbau(laufdir: laufdir,
                       mantelSocket: "\(laufdir)/mantel.sock",
                       mantelToken: Self.token(),
                       // Leer, wenn weder ausdruecklich verlangt noch Pruefung (Laufoptionen.steuerkanal).
                       steuerSocket: Laufoptionen.steuerkanal(optionen, laufdir: laufdir),
                       kernSteuerkanal: Self.kernSteuerkanalWaehlen(env: env, laufdir: laufdir),
                       kernPfad: kernPfad)

        // Ein Unix-Socketpfad traegt hoechstens 103 Bytes (sun_path). Ein
        // laengerer liesse den Kern anlaufen und die App an `listen` scheitern
        // -- dieselbe Vorpruefung wie in `mac/bin/starten`, hier VOR dem
        // ersten Prozess.
        for p in [a.mantelSocket, a.steuerSocket, a.kernSteuerkanal] where p.utf8.count > 103 {
            fehler = "Socketpfad laenger als 103 Bytes (sun_path): \(p)"
            return nil
        }

        let elektron = installiert ? Self.kernElectronPfad(kernPfad: kernPfad) : Self.electronPfad(kernPfad: kernPfad)
        guard FileManager.default.isExecutableFile(atPath: elektron) else {
            fehler = installiert
                ? "\(elektron) fehlt -- 'npm run kern-electron' in \(kernPfad), dann mac/bin/installieren"
                : "\(elektron) fehlt oder ist nicht ausfuehrbar -- 'npm install' in \(kernPfad)"
            return nil
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: elektron)
        // Beide Wege laden den Kern ueber das Ordner-Argument; wb-mensch verlangt genau
        // diese Argumente mit dem Kernordner aus seiner festen Liste.
        p.arguments = [kernPfad, "--headless"]
        p.currentDirectoryURL = URL(fileURLWithPath: kernPfad)
        var u = env
        u["AWB_MANTEL_SOCKET"] = a.mantelSocket
        u["AWB_MANTEL_TOKEN"] = a.mantelToken
        u["AWB_CONTROL_SOCKET"] = a.kernSteuerkanal
        p.environment = u
        // Das Protokoll des Kerns landet im Laufverzeichnis, nicht in der
        // Konsole der App: wer nach einem Fehlstart sucht, sucht dort, und ein
        // per `open` gestartetes Buendel hat ohnehin kein Terminal.
        let logPfad = "\(laufdir)/kern.log"
        FileManager.default.createFile(atPath: logPfad, contents: nil)
        if let log = FileHandle(forWritingAtPath: logPfad) {
            p.standardOutput = log
            p.standardError = log
        }
        do {
            try p.run()
        } catch {
            fehler = "Kern nicht gestartet: \(error.localizedDescription)"
            return nil
        }
        kern = p
        try? "\(p.processIdentifier)".write(toFile: "\(laufdir)/kern.pid", atomically: true, encoding: .utf8)
        // Der Token gehoert nur diesen beiden Prozessen.
        try? a.mantelToken.write(toFile: "\(laufdir)/mantel.token", atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: "\(laufdir)/mantel.token")
        // NICHT auf `awb-ready` gewartet: `KernVerbindung` versucht es jede
        // Sekunde von selbst, und ein Fenster, das eine Minute lang gar nichts
        // zeichnet, sieht fuer einen Menschen aus wie ein Absturz. Bis der Kern
        // steht, sagt die Oberflaeche „nicht verbunden" -- das ist die Wahrheit.
        aufbau = a
        return a
    }

    /**
     Der Steuerkanal des Kerns: der VORGABEPFAD (`awb-<uid>.sock`), solange dort
     niemand lauscht -- dann finden `awb-ctl`, `wb-code` und jedes andere
     Werkzeug diesen Kern ohne Zutun. Lauscht dort schon eine Electron-Fassung,
     bekommt dieser Kern seinen eigenen Pfad im Laufverzeichnis: zwei Kerne an
     einem Pfad gibt es nicht (control.ts, `clearStaleSocket`), und laufende des Nutzers Werkbank hat Vorrang vor einem zweiten Start.
     */
    private static func kernSteuerkanalWaehlen(env: [String: String], laufdir: String) -> String {
        if let p = env["AWB_CONTROL_SOCKET"], !p.isEmpty { return p }
        let basis = env["XDG_RUNTIME_DIR"] ?? NSTemporaryDirectory()
        let vorgabe = (basis as NSString).appendingPathComponent("awb-\(getuid()).sock")
        return belegt(vorgabe) ? "\(laufdir)/awb.sock" : vorgabe
    }

    /// Lauscht jemand an diesem Pfad? Eine Verbindung, die zustande kommt, ist
    /// der einzige ehrliche Beweis -- eine liegengebliebene Socketdatei sieht
    /// im Dateisystem genauso aus wie eine bediente.
    private static func belegt(_ pfad: String) -> Bool {
        guard FileManager.default.fileExists(atPath: pfad) else { return false }
        guard let fd = try? UnixSocket.verbinden(pfad) else { return false }
        close(fd)
        return true
    }

    private static func token() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Beenden

    /**
     Den Kern beenden, den DIESE App gestartet hat -- und nur den. Erst SIGTERM
     an die Wurzel und ihre Kinder (Electron haengt seine Helfer darunter), dann
     bis zu drei Sekunden warten, dann SIGKILL an alles, was noch lebt. Danach
     sind Sockets und PID-Datei weg.

     Synchron, ohne Warteschlange: das hier laeuft in `applicationWillTerminate`,
     und danach gibt es keinen Lauf mehr, in dem etwas nachkommen koennte.
     */
    func beenden() {
        guard let p = kern else { return }
        kern = nil
        let wurzel = p.processIdentifier
        let kinder = Self.kindPids(von: wurzel)

        // ZUERST HOEFLICH, UEBER DEN STEUERKANAL. Ein `quit` dort laesst den
        // Kern seinen eigenen Ausstieg gehen: tmux-Groessen zurueckstellen,
        // Chat-Kinder beenden, die Socketdatei loeschen. Ein SIGTERM als
        // erster Schritt liefe an all dem vorbei -- gemessen blieb dabei die
        // Socketdatei des Steuerkanals liegen, und der naechste Start haette
        // sie fuer einen laufenden Kern gehalten.
        if let a = aufbau, let fd = try? UnixSocket.verbinden(a.kernSteuerkanal) {
            _ = UnixSocket.schreiben(fd, Data("{\"cmd\":\"quit\"}\n".utf8))
            close(fd)
        }
        let hoeflichBis = Date().addingTimeInterval(3)
        while p.isRunning && Date() < hoeflichBis { usleep(100_000) }

        // Und dann bestimmt: erst SIGTERM an Wurzel und Kinder, dann SIGKILL an
        // alles, was das ueberlebt hat.
        if p.isRunning {
            for pid in [wurzel] + kinder { kill(pid, SIGTERM) }
            let bis = Date().addingTimeInterval(3)
            while p.isRunning && Date() < bis { usleep(100_000) }
        }
        for pid in [wurzel] + kinder where kill(pid, 0) == 0 { kill(pid, SIGKILL) }
        if let a = aufbau {
            for datei in ["kern.pid", "mantel.sock", "mantel.token"] {
                try? FileManager.default.removeItem(atPath: "\(a.laufdir)/\(datei)")
            }
        }
    }

    /// Die direkten Kinder eines Prozesses. `pgrep -P` statt einer eigenen
    /// Prozesstabelle: dasselbe Werkzeug, das `mac/bin/starten` dafuer nimmt.
    private static func kindPids(von: pid_t) -> [pid_t] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        p.arguments = ["-P", "\(von)"]
        let rohr = Pipe()
        p.standardOutput = rohr
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [] }
        let daten = rohr.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: daten, as: UTF8.self)
            .split(separator: "\n")
            .compactMap { pid_t($0.trimmingCharacters(in: .whitespaces)) }
    }
}
