import AppKit
import Foundation

// ──────────────────────────────────────────────────────────────────────────────
// Configuration — edit these if your project lives elsewhere.
// ──────────────────────────────────────────────────────────────────────────────
let kProjectPath = "\(NSHomeDirectory())/Projects/agentwatch"
let kPythonBin    = "\(kProjectPath)/.venv/bin/python"
let kAgentWatchBin = "\(kProjectPath)/.venv/bin/agentwatch"
let kFallbackBin   = "/usr/bin/env agentwatch"
let kConfigPath    = "\(kProjectPath)/config.json"
let kEventsLog     = "\(kProjectPath)/logs/agentwatch_events.jsonl"
let kStateFile     = "\(kProjectPath)/logs/state.json"
let kClaudeSettings = "\(NSHomeDirectory())/.claude/settings.json"
let kInstallHooksScript = "\(kProjectPath)/install_claude_hooks.sh" // legacy shell; prefer CLI

// ──────────────────────────────────────────────────────────────────────────────
// Helpers
// ──────────────────────────────────────────────────────────────────────────────

/// Run a subprocess, return (stdout, stderr, exitCode) or nil on timeout / error.
func runCommand(
    executable: String,
    arguments: [String],
    workingDir: String = kProjectPath,
    timeoutSec: Double = 15.0,
    env: [String: String] = [:]
) -> (stdout: String, stderr: String, exitCode: Int32)? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.currentDirectoryURL = URL(fileURLWithPath: workingDir)

    var fullEnv = ProcessInfo.processInfo.environment
    for (k, v) in env { fullEnv[k] = v }
    // Ensure .venv Python comes first in PATH
    let venvBin = "\(kProjectPath)/.venv/bin"
    if let path = fullEnv["PATH"] {
        fullEnv["PATH"] = "\(venvBin):\(path)"
    } else {
        fullEnv["PATH"] = venvBin
    }
    process.environment = fullEnv

    let outPipe = Pipe(), errPipe = Pipe()
    process.standardOutput = outPipe
    process.standardError  = errPipe

    do {
        try process.run()
    } catch {
        return nil
    }

    let deadline = DispatchTime.now() + timeoutSec
    let group = DispatchGroup()
    group.enter()
    DispatchQueue.global().async {
        process.waitUntilExit()
        group.leave()
    }
    if group.wait(timeout: deadline) == .timedOut {
        process.terminate()
        return nil
    }

    let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
    return (
        String(data: outData, encoding: .utf8) ?? "",
        String(data: errData, encoding: .utf8) ?? "",
        process.terminationStatus
    )
}

/// Call the agentwatch CLI (prefer .venv, fall back to PATH).
func callAgentWatch(_ args: [String], timeoutSec: Double = 15.0) -> (stdout: String, stderr: String, exitCode: Int32)? {
    let bin = FileManager.default.fileExists(atPath: kAgentWatchBin) ? kAgentWatchBin : kFallbackBin
    let executable: String
    let fullArgs: [String]
    if bin == kAgentWatchBin {
        executable = bin
        fullArgs = args
    } else {
        // /usr/bin/env agentwatch args...
        executable = "/usr/bin/env"
        fullArgs = ["agentwatch"] + args
    }
    return runCommand(executable: executable, arguments: fullArgs, timeoutSec: timeoutSec)
}

/// Mask a string for display: show first 4 + last 3, middle replaced with *.
func maskKey(_ key: String) -> String {
    if key.isEmpty || key == "YOUR_BARK_KEY" { return "NOT SET" }
    if key.count <= 7 { return String(repeating: "*", count: key.count) }
    let prefix = key.prefix(4)
    let suffix = key.suffix(3)
    let stars = String(repeating: "*", count: max(0, key.count - 7))
    return "\(prefix)\(stars)\(suffix)"
}

/// Read a JSON file, returning the parsed dictionary or nil.
func readJSON(_ path: String) -> [String: Any]? {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
          let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }
    return obj
}

// ──────────────────────────────────────────────────────────────────────────────
// Status
// ──────────────────────────────────────────────────────────────────────────────

enum OverallStatus: String {
    case ready       = "Ready"
    case needsSetup  = "Needs Setup"
    case hooksMissing = "Hooks Missing"
    case noBark      = "No Bark Key"
    case recentRisk  = "Recent Risk"

    var icon: String {
        switch self {
        case .ready:        return "●"
        case .needsSetup:   return "○"
        case .hooksMissing: return "◐"
        case .noBark:       return "◌"
        case .recentRisk:   return "⚠"
        }
    }
}

struct AgentHookStatus {
    var id: String
    var display: String
    var available: Bool
    var installed: Bool
    var hookCount: Int
    var required: Int
}

struct AppStatus {
    var barkOk: Bool
    var barkDisplay: String        // redacted key
    var hooksInstalled: Bool
    var hookCount: Int        // number of agentwatch hooks found (claude legacy)
    var agentHooks: [AgentHookStatus]
    var hooksSummary: String
    var taskName: String?
    var allowedPaths: [String]
    var forbiddenPaths: [String]
    var recentEvents: [EventSummary]
    var overall: OverallStatus
    var notificationMode: String   // "actionable" or "verbose"
    var personaTheme: String       // "off", "boss", "heir_male", ...
    var timeoutWatchNotify: Bool   // approval_detection.timeout_watch_notify
}

struct EventSummary: Identifiable {
    let id: String  // timestamp
    let time: String
    let eventType: String
    let title: String
    let risk: String
    let bodyFirstLine: String
    let notified: Bool
}

// ──────────────────────────────────────────────────────────────────────────────
// Status reader — reads files directly (fast, no subprocess).
// ──────────────────────────────────────────────────────────────────────────────

func readAppStatus() -> AppStatus {
    // --- Bark ---
    var barkOk = false
    var barkDisplay = "NOT SET"
    var configDict: [String: Any]? = nil
    if let config = readJSON(kConfigPath),
       let notifier = config["notifier"] as? [String: Any] {
        configDict = config
        let key = notifier["bark_key"] as? String ?? ""
        barkOk = (!key.isEmpty && key != "YOUR_BARK_KEY")
        barkDisplay = maskKey(key)
    }

    // --- Notification mode ---
    var notificationMode = "actionable"
    if let np = configDict?["notification_policy"] as? [String: Any] {
        notificationMode = np["mode"] as? String ?? "actionable"
    }

    // --- Persona theme ---
    var personaTheme = "off"
    if let pers = configDict?["persona"] as? [String: Any] {
        let enabled = pers["enabled"] as? Bool ?? false
        let theme = pers["theme"] as? String ?? "off"
        personaTheme = enabled ? theme : "off"
    }

    // --- Approval timeout notify ---
    var timeoutWatchNotify = false
    if let ad = configDict?["approval_detection"] as? [String: Any] {
        timeoutWatchNotify = ad["timeout_watch_notify"] as? Bool ?? false
    }

    // --- Hooks (multi-agent, read-only) ---
    let agentHooks = readMultiAgentHookStatus()
    let availableAgents = agentHooks.filter { $0.available }
    let installedAgents = availableAgents.filter { $0.installed }
    let hooksInstalled = !availableAgents.isEmpty && installedAgents.count == availableAgents.count
    let hookCount = agentHooks.reduce(0) { $0 + $1.hookCount }
    let hooksSummary: String = {
        if availableAgents.isEmpty { return "No agents detected" }
        return availableAgents.map { a in
            "\(a.display)\(a.installed ? "✓" : "✗")"
        }.joined(separator: " ")
    }()

    // --- Task ---
    var taskName: String? = nil
    var allowedPaths: [String] = []
    var forbiddenPaths: [String] = []
    if let state = readJSON(kStateFile),
       let task = state["active_task"] as? [String: Any] {
        taskName = task["name"] as? String
        allowedPaths = task["allowed_paths"] as? [String] ?? []
        forbiddenPaths = task["forbidden_paths"] as? [String] ?? []
    }

    // --- Recent events (last 5 non-info) ---
    var recent: [EventSummary] = []
    if let data = try? String(contentsOfFile: kEventsLog, encoding: .utf8) {
        let lines = data.components(separatedBy: "\n").filter { !$0.isEmpty }
        var parsed: [[String: Any]] = []
        for line in lines.suffix(50) {
            if let d = line.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                parsed.append(obj)
            }
        }
        for ev in parsed.reversed() {
            let etype = ev["event_type"] as? String ?? "info"
            if etype == "info" { continue }
            let ts = ev["timestamp"] as? String ?? ""
            let time = ts.count >= 19 ? String(ts.prefix(19).suffix(8)) : ""
            let body = ev["body"] as? String ?? ""
            let firstLine = body.components(separatedBy: "\n").first ?? ""
            let wasNotified = ev["notified"] as? Bool ?? false
            recent.append(EventSummary(
                id: ts,
                time: time,
                eventType: etype,
                title: ev["title"] as? String ?? "",
                risk: ev["risk"] as? String ?? "低",
                bodyFirstLine: firstLine,
                notified: wasNotified
            ))
            if recent.count >= 5 { break }
        }
    }

    // --- Overall ---
    let hasRecentRisk = recent.contains { ["danger", "drift", "failure"].contains($0.eventType) }
    let overall: OverallStatus
    if !barkOk {
        overall = .noBark
    } else if !hooksInstalled {
        overall = .hooksMissing
    } else if hasRecentRisk {
        overall = .recentRisk
    } else if !barkOk && !hooksInstalled {
        overall = .needsSetup
    } else {
        overall = .ready
    }

    return AppStatus(
        barkOk: barkOk,
        barkDisplay: barkDisplay,
        hooksInstalled: hooksInstalled,
        hookCount: hookCount,
        agentHooks: agentHooks,
        hooksSummary: hooksSummary,
        taskName: taskName,
        allowedPaths: allowedPaths,
        forbiddenPaths: forbiddenPaths,
        recentEvents: recent,
        overall: overall,
        notificationMode: notificationMode,
        personaTheme: personaTheme,
        timeoutWatchNotify: timeoutWatchNotify
    )
}

/// Count agentwatch commands under a Claude-style hooks object for the given event names.
private func countHooksInObject(_ hooks: [String: Any]?, events: [String]) -> Int {
    guard let hooks = hooks else { return 0 }
    var count = 0
    for eventName in events {
        guard let groups = hooks[eventName] as? [[String: Any]] else { continue }
        var hit = false
        for g in groups {
            if let inner = g["hooks"] as? [[String: Any]] {
                for h in inner {
                    if let cmd = h["command"] as? String, cmd.contains("agentwatch") {
                        hit = true; break
                    }
                }
            }
            if hit { break }
        }
        if hit { count += 1 }
    }
    return count
}

func readMultiAgentHookStatus() -> [AgentHookStatus] {
    let home = NSHomeDirectory()
    var result: [AgentHookStatus] = []

    // Claude
    let claudeSettings = "\(home)/.claude/settings.json"
    let claudeEvents = ["PreToolUse", "PostToolUse", "Notification", "Stop", "PermissionRequest", "PermissionDenied"]
    let claudeHooks = readJSON(claudeSettings)?["hooks"] as? [String: Any]
    let claudeCount = countHooksInObject(claudeHooks, events: claudeEvents)
    let claudeAvail = FileManager.default.fileExists(atPath: "\(home)/.claude")
        || FileManager.default.fileExists(atPath: claudeSettings)
    result.append(AgentHookStatus(
        id: "claude", display: "Claude", available: claudeAvail,
        installed: claudeCount >= 6, hookCount: claudeCount, required: 6
    ))

    // Grok
    let grokFile = "\(home)/.grok/hooks/agentwatch.json"
    let grokEvents = ["PreToolUse", "PostToolUse", "Notification", "Stop", "SessionEnd", "PermissionDenied"]
    let grokHooks = readJSON(grokFile)?["hooks"] as? [String: Any]
    let grokCount = countHooksInObject(grokHooks, events: grokEvents)
    let grokAvail = FileManager.default.fileExists(atPath: "\(home)/.grok")
    result.append(AgentHookStatus(
        id: "grok", display: "Grok", available: grokAvail,
        installed: grokCount >= 4, hookCount: grokCount, required: grokEvents.count
    ))

    // Codex
    let codexFile = "\(home)/.codex/hooks.json"
    let codexEvents = ["PreToolUse", "PostToolUse", "Notification", "Stop", "PermissionRequest"]
    let codexHooks = readJSON(codexFile)?["hooks"] as? [String: Any]
    let codexCount = countHooksInObject(codexHooks, events: codexEvents)
    let codexAvail = FileManager.default.fileExists(atPath: "\(home)/.codex")
    result.append(AgentHookStatus(
        id: "codex", display: "Codex", available: codexAvail,
        installed: codexCount >= 4, hookCount: codexCount, required: codexEvents.count
    ))

    // Gemini
    let geminiSettings = "\(home)/.gemini/settings.json"
    let geminiEvents = ["BeforeTool", "AfterTool", "Notification", "AfterAgent"]
    let geminiHooks = readJSON(geminiSettings)?["hooks"] as? [String: Any]
    let geminiCount = countHooksInObject(geminiHooks, events: geminiEvents)
    let geminiAvail = FileManager.default.fileExists(atPath: "\(home)/.gemini")
    result.append(AgentHookStatus(
        id: "gemini", display: "Gemini", available: geminiAvail,
        installed: geminiCount >= 3, hookCount: geminiCount, required: geminiEvents.count
    ))

    return result
}

// ──────────────────────────────────────────────────────────────────────────────
// App Delegate
// ──────────────────────────────────────────────────────────────────────────────

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var lastActionResult: String = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "AW"
        statusItem.button?.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .bold)

        rebuildMenu()
    }

    // ── Menu building ────────────────────────────────────────────────────

    private func rebuildMenu() {
        let menu = NSMenu(title: "AgentWatch")
        let status = readAppStatus()
        statusItem.button?.title = "\(status.overall.icon) AW"

        // ── Header ──
        addDisabled(menu, "AgentWatch — \(status.overall.rawValue)")
        menu.addItem(.separator())

        // ── Status ──
        addDisabled(menu, "Bark: \(status.barkOk ? "✓ OK" : "✗ \(status.barkDisplay)")")
        addDisabled(menu, "Hooks: \(status.hooksInstalled ? "✓ \(status.hooksSummary)" : "✗ \(status.hooksSummary)")")
        for a in status.agentHooks where a.available {
            let mark = a.installed ? "✓" : "✗"
            addDisabled(menu, "  \(a.display): \(mark) \(a.hookCount)/\(a.required)")
        }
        addDisabled(menu, "Notif Mode: \(status.notificationMode)")
        addDisabled(menu, "Persona: \(personaDisplayName(status.personaTheme))")
        addDisabled(menu, "Approval Timeout Notify: \(status.timeoutWatchNotify ? "On" : "Off")")
        if let task = status.taskName {
            addDisabled(menu, "Task: \(task)")
            let allowed = status.allowedPaths.prefix(4).joined(separator: ", ")
            let forbidden = status.forbiddenPaths.prefix(4).joined(separator: ", ")
            if !allowed.isEmpty { addDisabled(menu, "  Allowed: \(allowed)") }
            if !forbidden.isEmpty { addDisabled(menu, "  Forbidden: \(forbidden)") }
        } else {
            addDisabled(menu, "Task: (none)")
        }

        menu.addItem(.separator())

        // ── Recent Events ──
        addDisabled(menu, "Recent Events:")
        if status.recentEvents.isEmpty {
            addDisabled(menu, "  (no events yet)")
        } else {
            for ev in status.recentEvents {
                let icon = eventIcon(ev.eventType)
                let tag = ev.notified ? "notified" : "logged"
                let line = "\(icon) [\(ev.time)] \(ev.title) | \(tag)"
                addDisabled(menu, "  \(line)")
            }
        }

        menu.addItem(.separator())

        // ── Persona Theme ──
        let personaMenu = NSMenuItem(title: "Persona Theme", action: nil, keyEquivalent: "")
        let personaSubmenu = NSMenu(title: "Persona Theme")
        let themes: [(String, String)] = [
            ("off", "Off"), ("boss", "总裁版"), ("heir_male", "少爷版"),
            ("heir_female", "大小姐版"), ("emperor", "皇上版"), ("palace", "甄嬛版"),
        ]
        let currentTheme = status.personaTheme
        for (key, name) in themes {
            let item = NSMenuItem(title: name, action: #selector(selectPersonaTheme(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = key
            item.state = (key == currentTheme) ? .on : .off
            personaSubmenu.addItem(item)
        }
        personaMenu.submenu = personaSubmenu
        menu.addItem(personaMenu)
        menu.addItem(.separator())

        // ── Actions ──
        addAction(menu, "Refresh Status",          #selector(refreshStatus))
        addAction(menu, "Add / Update Bark Key...", #selector(updateBarkKey))
        addAction(menu, "Show Bark Config",         #selector(showBarkConfig))
        addAction(menu, "Test Push",               #selector(testPush))
        addAction(menu, "Install / Update Hooks",  #selector(installOrUpdateHooks))
        addAction(menu, "Set Task Boundary...",    #selector(setTaskBoundary))
        addAction(menu, "Clear Task Boundary",     #selector(clearTaskBoundary))

        menu.addItem(.separator())

        addAction(menu, "Open Monitor in Terminal", #selector(openMonitor))
        addAction(menu, "Open Logs Folder",         #selector(openLogsFolder))
        addAction(menu, "Open README",              #selector(openReadme))
        addAction(menu, "Open config.json",         #selector(openConfig))
        addAction(menu, "Copy Setup Commands",      #selector(copySetupCommands))

        menu.addItem(.separator())

        // Last action feedback (if any)
        if !lastActionResult.isEmpty {
            addDisabled(menu, lastActionResult)
            menu.addItem(.separator())
        }

        addAction(menu, "Quit", #selector(quitApp))

        statusItem.menu = menu
    }

    // ── Helpers ──────────────────────────────────────────────────────────

    private func addDisabled(_ menu: NSMenu, _ title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    private func addAction(_ menu: NSMenu, _ title: String, _ sel: Selector) {
        let item = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }

    @MainActor private func refreshUI(with result: String? = nil) {
        if let r = result { lastActionResult = r }
        rebuildMenu()
    }

    private func eventIcon(_ type: String) -> String {
        switch type {
        case "danger":                     return "⚠"
        case "drift":                      return "↗"
        case "failure":                    return "✗"
        case "task_done":                  return "✓"
        case "attention_required":         return "‼"
        case "permission_required":        return "‼"
        case "possible_permission_wait":   return "⏳"
        case "permission_denied":          return "✕"
        default:                           return "·"
        }
    }

    // ── Persona helpers ─────────────────────────────────────────────────

    private func personaDisplayName(_ theme: String) -> String {
        switch theme {
        case "off":         return "Off"
        case "boss":        return "总裁版"
        case "heir_male":   return "少爷版"
        case "heir_female": return "大小姐版"
        case "emperor":     return "皇上版"
        case "palace":      return "甄嬛版"
        default:            return theme
        }
    }

    @objc private func selectPersonaTheme(_ sender: NSMenuItem) {
        guard let theme = sender.representedObject as? String else { return }
        let name = personaDisplayName(theme)
        lastActionResult = "Setting persona: \(name)..."
        rebuildMenu()
        DispatchQueue.global().async { [weak self] in
            let args: [String]
            if theme == "off" {
                args = ["persona", "off"]
            } else {
                args = ["persona", "set", theme]
            }
            let result = callAgentWatch(args, timeoutSec: 10.0)
            DispatchQueue.main.async {
                let ok = (result?.exitCode == 0)
                let msg = ok ? "Persona theme updated: \(name)" : "Persona update failed."
                if ok {
                    // Brief feedback via last result; full status already refreshed below.
                    self?.showInfoDialog("Persona Theme Updated", message: msg)
                }
                self?.refreshUI(with: msg)
            }
        }
    }

    // ── Actions ──────────────────────────────────────────────────────────

    @objc private func refreshStatus() {
        DispatchQueue.global().async { [weak self] in
            // No subprocess needed — readAppStatus reads files directly.
            DispatchQueue.main.async {
                self?.refreshUI()
            }
        }
    }

    @objc private func testPush() {
        lastActionResult = "Testing push..."
        rebuildMenu()
        DispatchQueue.global().async { [weak self] in
            let result = callAgentWatch(["test-push"], timeoutSec: 20.0)
            DispatchQueue.main.async {
                let ok = (result?.exitCode == 0)
                self?.refreshUI(with: ok ? "Last: Test push sent ✓" : "Last: Test push failed ✗")
            }
        }
    }

    @objc private func installOrUpdateHooks() {
        let alert = NSAlert()
        alert.messageText = "Install / Update Hooks"
        alert.informativeText = """
        Install AgentWatch hooks for all detected agents:

          • Claude  → ~/.claude/settings.json
          • Grok    → ~/.grok/hooks/agentwatch.json
          • Codex   → ~/.codex/hooks.json
          • Gemini  → ~/.gemini/settings.json

        Existing settings are backed up; non-AgentWatch hooks are preserved.

        After installing, start a new session in each CLI.

        Continue?
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Install All")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() != .alertFirstButtonReturn { return }

        lastActionResult = "Installing multi-agent hooks..."
        rebuildMenu()

        DispatchQueue.global().async { [weak self] in
            // Prefer unified CLI installer (Claude + Grok + Codex + Gemini).
            let result = callAgentWatch(["hooks", "install"], timeoutSec: 60.0)
            DispatchQueue.main.async {
                let ok = (result?.exitCode == 0)
                let stdout = (result?.stdout ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let stderr = (result?.stderr ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let combined = [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")

                if ok {
                    let status = readAppStatus()
                    let lines = status.agentHooks
                        .filter { $0.available }
                        .map { "\($0.display): \($0.installed ? "✓" : "✗") \($0.hookCount)/\($0.required)" }
                        .joined(separator: "\n")
                    self?.showInfoDialog(
                        "Hooks Updated",
                        message: "\(status.hooksSummary)\n\n\(lines)\n\nRestart each CLI session to load hooks."
                    )
                    self?.refreshUI(with: status.hooksInstalled
                        ? "Last: Multi-agent hooks installed ✓"
                        : "Last: Hooks install finished — some agents incomplete")
                } else {
                    let detail = combined.isEmpty ? "Unknown error (exit \(result?.exitCode ?? -1))" : combined
                    self?.showInfoDialog("Hooks Install Failed", message: detail)
                    self?.refreshUI(with: "Last: Hooks install failed ✗")
                }
            }
        }
    }

    @objc private func setTaskBoundary() {
        // Open Terminal with agentwatch task quick
        let script = """
        cd '\(kProjectPath)' && source .venv/bin/activate && agentwatch task quick
        """
        runTerminalScript(script)
        // Schedule a refresh after a few seconds to pick up the new task
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            self?.refreshUI()
        }
    }

    @objc private func clearTaskBoundary() {
        DispatchQueue.global().async { [weak self] in
            _ = callAgentWatch(["task", "clear"], timeoutSec: 5.0)
            DispatchQueue.main.async {
                self?.refreshUI(with: "Task boundary cleared.")
            }
        }
    }

    @objc private func openMonitor() {
        let script = """
        cd '\(kProjectPath)' && source .venv/bin/activate && agentwatch monitor
        """
        runTerminalScript(script)
    }

    @objc private func openLogsFolder() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "\(kProjectPath)/logs"))
    }

    @objc private func openReadme() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "\(kProjectPath)/README.md"))
    }

    @objc private func openConfig() {
        NSWorkspace.shared.open(URL(fileURLWithPath: kConfigPath))
    }

    @objc private func copySetupCommands() {
        let cmds = """
        cd ~/Projects/agentwatch
        python3 -m venv .venv
        source .venv/bin/activate
        pip install -e .
        agentwatch init
        agentwatch config bark
        agentwatch test-push
        agentwatch hooks install
        agentwatch doctor
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(cmds, forType: .string)
        refreshUI(with: "Setup commands copied to clipboard.")
    }

    @objc private func updateBarkKey() {
        let alert = NSAlert()
        alert.messageText = "Configure Bark Key"
        alert.informativeText = "Paste your Bark URL or Bark Key.\n\nExamples:\n  https://api.day.app/YOUR_KEY/\n  YOUR_KEY"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        textField.placeholderString = "https://api.day.app/... or key"
        textField.stringValue = ""
        alert.accessoryView = textField

        alert.window.initialFirstResponder = textField

        let response = alert.runModal()
        if response != .alertFirstButtonReturn { return }
        let input = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if input.isEmpty { return }

        lastActionResult = "Updating Bark key..."
        rebuildMenu()

        DispatchQueue.global().async { [weak self] in
            let result = callAgentWatch(["config", "bark", "--value", input], timeoutSec: 10.0)
            DispatchQueue.main.async {
                let ok = (result?.exitCode == 0)
                if ok {
                    // Extract the redacted key from stdout for the dialog
                    let out = result?.stdout ?? ""
                    let lines = out.components(separatedBy: "\n")
                    let keyLine = lines.first(where: { $0.contains("key updated") }) ?? "Bark key updated."
                    self?.showInfoDialog("Bark Key Updated", message: keyLine.trimmingCharacters(in: .whitespaces))
                } else {
                    let err = result?.stderr ?? result?.stdout ?? "Unknown error"
                    self?.showInfoDialog("Error", message: err.trimmingCharacters(in: .whitespaces))
                }
                self?.refreshUI()
            }
        }
    }

    @objc private func showBarkConfig() {
        let status = readAppStatus()
        let server = (readJSON(kConfigPath)?["notifier"] as? [String: Any])?["bark_server"] as? String ?? "https://api.day.app"
        let message = """
        Bark:  \(status.barkOk ? "OK" : "Missing")
        Server: \(server)
        Key:   \(status.barkDisplay)
        """
        showInfoDialog("Bark Configuration", message: message)
    }

    private func showInfoDialog(_ title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // ── Terminal helper ──────────────────────────────────────────────────

    private func runTerminalScript(_ script: String) {
        // Use osascript to open a new Terminal window and run the script.
        let appleScript = """
        tell application "Terminal"
            activate
            do script "\(script.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))"
        end tell
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScript]
        try? process.run()
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// Entry point
// ──────────────────────────────────────────────────────────────────────────────

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // LSUIElement equivalent
app.run()
