import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// GlobalProtect VPN state. All the real work is done by the `gpvpn` CLI: this
// only polls `gpvpn status --json`, fires connect/disconnect, and notifies when
// the tunnel changes state.
Item {
  id: root

  property var settings: ({})

  // `gpvpn` exit codes (documented in `gpvpn --help`). Any non-zero code used
  // to be read as "the CLI is missing", so a broken profiles.json showed a
  // message that was plainly false, and a slow negotiation fired a failure
  // notification.
  readonly property int exitProgress: 3
  readonly property int exitNoProfiles: 4
  readonly property int exitNoBackend: 5
  readonly property int exitBadConfig: 6
  readonly property int exitNotFound: 127

  // The CLI lives in its own repo (github.com/Unnunoctio/gpvpn), so the two
  // halves can drift apart. `gpvpn --version` exists from 0.1.0 on: anything
  // older prints its usage and exits 0, which is why "I could not read a
  // version" means "it is old", not "the command failed".
  readonly property string minCliVersion: "0.1.0"
  property string cliVersion: ""
  property bool cliChecked: false
  readonly property bool cliOutdated: cliChecked && installed
                                      && !versionAtLeast(cliVersion, minCliVersion)

  property bool installed: false
  property string state: "unknown"   // connected | connecting | authenticating | disconnected | failed | unknown
  property string profileId: ""
  property string profileName: ""
  property string defaultProfile: ""
  property var profiles: []
  property string interfaceName: ""
  property string ip: ""
  property string since: ""
  property string lastError: ""
  // The whole text, kept beside the elided one: a certificate or HIP error
  // does not fit in 160 characters, and the detail only lived in the logs.
  property string lastErrorFull: ""
  readonly property bool errorTruncated: lastErrorFull.length > lastError.length
  property string actionStatus: ""

  readonly property bool connected: state === "connected"
  readonly property bool busyState: state === "connecting" || state === "authenticating"
  // The switch turns on as soon as the login starts: the SAML window can take a
  // while, and the click has to visibly do something.
  readonly property bool active: connected || busyState
  readonly property bool busy: busyState || connectProcess.running || disconnectProcess.running
  readonly property bool hasProfiles: profiles.length > 0
  // Which profile reads as "on". Once connected it is whatever the CLI
  // reports; while negotiating the CLI does not know yet, so the requested one
  // stands in.
  readonly property string activeProfileId: connected ? profileId : (busyState ? pendingProfile : "")
  readonly property bool saving: saveProcess.running
  // With `mode: gateway` the server IS the gateway. With `mode: portal` the
  // server is the portal and the real gateway is the authgroup, a separate
  // field: labelling the server "Gateway" in that case was simply wrong.
  readonly property var targetProfileObj: profileById(targetProfile())
  readonly property string serverHost: targetProfileObj ? String(targetProfileObj.server || "") : ""
  readonly property string profileMode: targetProfileObj ? String(targetProfileObj.mode || "gateway") : "gateway"
  readonly property string gatewayName: targetProfileObj ? String(targetProfileObj.gateway || "") : ""

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 15, 5, 300)
  readonly property bool notifyOnDisconnect: setting("notifyOnDisconnect", true) === true

  // Tells a dropped tunnel apart from a disconnect the user asked for: only the
  // first deserves an urgent notification. Switching profiles takes the tunnel
  // down and back up, and must not notify about the way down either.
  property string pendingProfile: ""
  property string saveError: ""

  signal profileSaved(string id)
  signal profileRemoved(string id)

  readonly property bool removing: removeProcess.running

  property bool _userInitiatedStop: false
  property string _switchingTo: ""
  property string _statusOutput: ""

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    if (n < min) n = min
    if (n > max) n = max
    return n
  }

  function stateLabel() {
    switch (state) {
      case "connected": return profileName !== "" ? profileName : "Connected"
      case "connecting": return "Bringing the tunnel up…"
      case "authenticating": return "Waiting for the SAML login…"
      case "failed": return "Connection failed"
      case "disconnected": return hasProfiles ? "Disconnected" : "No profiles"
      default: return "No data"
    }
  }

  function profileById(id) {
    for (var i = 0; i < profiles.length; i++) {
      if (profiles[i].id === id) return profiles[i]
    }
    return null
  }

  function targetProfile() {
    if (profileId !== "") return profileId
    if (defaultProfile !== "") return defaultProfile
    return profiles.length > 0 ? profiles[0].id : ""
  }

  function uptimeText() {
    if (!connected || since === "") return ""
    var started = new Date(since)
    if (isNaN(started.getTime())) return ""
    var secs = Math.max(0, Math.floor((Date.now() - started.getTime()) / 1000))
    var h = Math.floor(secs / 3600)
    var m = Math.floor((secs % 3600) / 60)
    if (h > 0) return h + "h " + m + "m"
    if (m > 0) return m + "m"
    return secs + "s"
  }

  function notify(title, body, urgency) {
    Quickshell.execDetached(["notify-send", "-a", "GlobalProtect VPN",
                             "-u", urgency || "normal",
                             "-i", "gpvpn", title, body || ""])
  }

  // Component-wise comparison; anything that does not parse counts as 0, so an
  // empty string falls below any minimum.
  function versionAtLeast(have, want) {
    var a = String(have || "").split(".")
    var b = String(want || "").split(".")
    for (var i = 0; i < 3; i++) {
      var x = parseInt(a[i], 10); if (isNaN(x)) x = 0
      var y = parseInt(b[i], 10); if (isNaN(y)) y = 0
      if (x !== y) return x > y
    }
    return true
  }

  function checkCliVersion() {
    if (versionProcess.running) return
    versionProcess.command = ["gpvpn", "--version"]
    versionProcess.running = true
  }

  function refresh() {
    if (statusProcess.running) return
    _statusOutput = ""
    statusProcess.command = ["gpvpn", "status", "--json"]
    statusProcess.running = true
  }

  function applyStatus(raw) {
    var parsed
    try {
      parsed = JSON.parse(String(raw || ""))
    } catch (e) {
      setError("Could not read the VPN state")
      return
    }
    installed = true
    profileId = String(parsed.profile || "")
    profileName = String(parsed.profileName || "")
    defaultProfile = String(parsed.defaultProfile || "")
    profiles = parsed.profiles || []
    interfaceName = String(parsed.interface || "")
    ip = String(parsed.ip || "")
    since = String(parsed.since || "")
    var incoming = String(parsed.state || "unknown")
    setError(incoming === "failed" ? parsed.error : "")
    setState(incoming)
  }

  function setState(next) {
    if (next === state) return
    var previous = state
    state = next
    if (previous === "" || previous === "unknown") return   // first poll

    if (next === "connected") {
      _userInitiatedStop = false
      _switchingTo = ""
      pendingProfile = ""
      actionStatus = ""
      notify("VPN connected", profileName + (ip !== "" ? " · " + ip : ""), "normal")
    } else if (next === "failed") {
      _userInitiatedStop = false
      _switchingTo = ""
      pendingProfile = ""
      notify("VPN failed", lastError !== "" ? lastError : "The tunnel could not come up", "critical")
    } else if (next === "disconnected") {
      pendingProfile = ""
      if (previous !== "connected") return
      if (_userInitiatedStop || _switchingTo !== "") {
        _userInitiatedStop = false
      } else if (notifyOnDisconnect) {
        notify("VPN disconnected", "The tunnel dropped", "critical")
      }
    }
  }

  // With no argument it uses the default profile; with one it switches
  // profiles, which the CLI resolves by taking the tunnel down and back up.
  function connect(id) {
    if (connectProcess.running) return
    var target = String(id || targetProfile())
    if (target === "") return
    _userInitiatedStop = false
    _switchingTo = connected && target !== profileId ? target : ""
    pendingProfile = target
    setError("")
    var p = profileById(target)
    actionStatus = "Opening the SAML login" + (p ? " for " + p.name : "") + "…"
    // The optimistic state keeps the switch from snapping back in the gap
    // between the click and the first poll that sees the auth marker.
    state = "authenticating"
    connectProcess.command = ["gpvpn", "connect", target]
    connectProcess.running = true
    fastPoll.restart()
  }

  function disconnect() {
    if (disconnectProcess.running) return
    _userInitiatedStop = true
    _switchingTo = ""
    pendingProfile = ""
    actionStatus = "Taking the tunnel down…"
    disconnectProcess.command = ["gpvpn", "disconnect"]
    disconnectProcess.running = true
    fastPoll.restart()
  }

  function toggle() {
    if (busy && !connected) return
    if (connected) disconnect()
    else connect("")
  }

  // The id is derived from the name: the panel form asks only for the
  // essentials, and the rarer `gpvpn profile add` options stay with the CLI.
  function slug(text) {
    return String(text || "").toLowerCase().trim()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "")
  }

  // Create and edit share one path. With an empty editId it creates, deriving
  // the id from the name; with an editId it uses `profile edit`, which merges
  // and therefore allows saving without restating the fields the form omits.
  //
  // The tunnel interface is not editable from the panel: with a single tunnel at
  // a time two of them can never collide, so renaming it only serves firewall
  // rules pinned to the name. It stays in the JSON, and a panel edit leaves it
  // untouched.
  function saveProfile(editId, name, server, mode, gateway, clientos) {
    if (saveProcess.running) return
    var label = String(name || "").trim()
    var host = String(server || "").trim()
    if (label === "" || host === "") {
      saveError = "A name and a server are required"
      return
    }

    var args
    var target = String(editId || "")
    if (target !== "") {
      args = ["gpvpn", "profile", "edit", "--id", target]
      saveProcess.savedId = target
    } else {
      var id = slug(label)
      if (id === "") {
        saveError = "That name yields no valid id"
        return
      }
      // `profile add` replaces without asking: a duplicate id is stopped here.
      if (profileById(id)) {
        saveError = "There is already a profile with the id \u0027" + id + "\u0027"
        return
      }
      args = ["gpvpn", "profile", "add", "--id", id]
      saveProcess.savedId = id
    }

    var wanted = String(mode || "gateway")
    args = args.concat(["--name", label, "--server", host, "--mode", wanted])
    // The gateway only applies to portal mode: leaving portal clears it, so no
    // stale --authgroup is left behind to confuse things later.
    args = args.concat(["--gateway", wanted === "portal" ? String(gateway || "").trim() : ""])
    args = args.concat(["--clientos", String(clientos || "linux-64")])

    saveError = ""
    saveProcess.command = args
    saveProcess.running = true
  }

  function setDefaultProfile(id) {
    if (defaultProcess.running) return
    var target = String(id || "")
    if (target === "" || target === defaultProfile) return
    defaultProcess.command = ["gpvpn", "profile", "default", target]
    defaultProcess.running = true
  }

  // Deleting is destructive and the CLI does not ask: the caller must have
  // confirmed first. It does not disconnect either, which is why the panel does
  // not offer to delete the active profile — doing so would leave the tunnel up
  // pointing at a config that no longer exists.
  function removeProfile(id) {
    if (removeProcess.running) return
    var target = String(id || "")
    if (target === "") return
    removeProcess.targetId = target
    removeProcess.command = ["gpvpn", "profile", "rm", target]
    removeProcess.running = true
  }

  function elide(text) {
    var value = String(text || "").replace(/\s+/g, " ").trim()
    return value.length > 160 ? value.substring(0, 157) + "…" : value
  }

  // The only way to set an error: it stores the whole text and publishes the
  // trimmed one, so the two cannot drift apart.
  function setError(text) {
    lastErrorFull = String(text || "").replace(/\s+/g, " ").trim()
    lastError = elide(lastErrorFull)
  }

  Component.onCompleted: {
    refresh()
    checkCliVersion()
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  // While something is in transition it pays to look more often; it turns
  // itself off once the state settles.
  Timer {
    id: fastPoll
    interval: 1000
    repeat: true
    running: false
    property int ticks: 0
    onTriggered: {
      ticks += 1
      root.refresh()
      if (ticks > 120 || (!root.busy && ticks > 3)) {
        ticks = 0
        running = false
      }
    }
    onRunningChanged: if (running) ticks = 0
  }

  Process {
    id: versionProcess
    running: false
    command: []
    stdout: StdioCollector { id: versionStdout; waitForEnd: true }
    onExited: function (exitCode) {
      var out = String(versionStdout.text || "")
      var m = /gpvpn[ \t]+([0-9]+\.[0-9]+\.[0-9]+)/.exec(out)
      root.cliVersion = (exitCode === 0 && m) ? m[1] : ""
      root.cliChecked = true
    }
  }

  Process {
    id: statusProcess
    running: false
    command: []
    stdout: StdioCollector { id: statusStdout; waitForEnd: true; onStreamFinished: root._statusOutput = text }
    onExited: function (exitCode) {
      if (exitCode === 0) {
        root.applyStatus(statusStdout.text || root._statusOutput)
        return
      }
      root.state = "unknown"
      // 127 comes from the shell when the binary is missing; 5 comes from the
      // CLI itself when the unit or the helper is absent. Only those two mean
      // "not installed": the rest are failures of a CLI that did run.
      if (exitCode === root.exitNotFound) {
        root.installed = false
        root.setError("The gpvpn CLI was not found in PATH")
      } else if (exitCode === root.exitNoBackend) {
        root.installed = false
        root.setError("Backend missing; install it with: gpvpn setup")
      } else if (exitCode === root.exitBadConfig) {
        root.installed = true
        root.setError("The profiles file is not valid JSON")
      } else {
        root.installed = true
        root.setError("gpvpn status failed (exit code " + exitCode + ")")
      }
    }
  }

  Process {
    id: connectProcess
    running: false
    command: []
    stderr: StdioCollector { id: connectStderr; waitForEnd: true }
    onExited: function (exitCode) {
      if (exitCode === 0) {
        root.actionStatus = ""
      } else if (exitCode === root.exitProgress) {
        // The CLI gave up waiting, but the unit is still alive and the tunnel
        // is still negotiating: this is not a failure. pendingProfile and the
        // fast poll are kept, and nothing is notified.
        root.actionStatus = "The tunnel is still negotiating…"
      } else {
        root.setError(exitCode === root.exitNoProfiles
                      ? "No profiles configured"
                      : (connectStderr.text || "Could not connect"))
        root.actionStatus = ""
        root._switchingTo = ""
        root.notify("Could not connect the VPN", root.lastError, "critical")
      }
      root.refresh()
      fastPoll.restart()
    }
  }

  Process {
    id: removeProcess
    running: false
    command: []
    property string targetId: ""
    stderr: StdioCollector { id: removeStderr; waitForEnd: true }
    onExited: function (exitCode) {
      if (exitCode === 0) {
        root.profileRemoved(removeProcess.targetId)
      } else {
        root.setError(removeStderr.text || "Could not delete the profile")
      }
      root.refresh()
    }
  }

  Process {
    id: saveProcess
    running: false
    command: []
    property string savedId: ""
    stderr: StdioCollector { id: saveStderr; waitForEnd: true }
    onExited: function (exitCode) {
      if (exitCode === 0) {
        root.saveError = ""
        root.profileSaved(saveProcess.savedId)
      } else {
        root.saveError = root.elide(saveStderr.text || "Could not save the profile")
      }
      root.refresh()
    }
  }

  Process {
    id: defaultProcess
    running: false
    command: []
    stderr: StdioCollector { id: defaultStderr; waitForEnd: true }
    onExited: function (exitCode) {
      if (exitCode !== 0) {
        root.setError(defaultStderr.text || "Could not set the default profile")
      }
      root.refresh()
    }
  }

  Process {
    id: disconnectProcess
    running: false
    command: []
    stderr: StdioCollector { id: disconnectStderr; waitForEnd: true }
    onExited: function (exitCode) {
      if (exitCode !== 0) {
        root._userInitiatedStop = false
        root.setError(disconnectStderr.text || "Could not disconnect")
      }
      root.actionStatus = ""
      root.refresh()
      fastPoll.restart()
    }
  }
}
