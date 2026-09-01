import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Estado de la VPN GlobalProtect. Todo el trabajo real lo hace el CLI `gpvpn`:
// aca solo se poletea `gpvpn status --json`, se disparan connect/disconnect y
// se avisa cuando el tunel cambia de estado.
Item {
  id: root

  property var settings: ({})

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
  property string actionStatus: ""

  readonly property bool connected: state === "connected"
  readonly property bool busyState: state === "connecting" || state === "authenticating"
  // El switch se prende apenas arranca el login: la ventana SAML puede tardar y
  // el usuario tiene que ver que su click hizo algo.
  readonly property bool active: connected || busyState
  readonly property bool busy: busyState || connectProcess.running || disconnectProcess.running
  readonly property bool hasProfiles: profiles.length > 0
  // Cual perfil pinta como "encendido". Conectada es el que reporta el CLI;
  // mientras negocia el CLI todavia no lo sabe, asi que vale el que pedimos.
  readonly property string activeProfileId: connected ? profileId : (busyState ? pendingProfile : "")
  readonly property bool adding: addProcess.running
  // El JSON de gpvpn no trae el gateway suelto: sale del servidor del perfil
  // conectado, o del que se levantaria si se pulsa el switch.
  readonly property string gateway: {
    var p = profileById(targetProfile())
    return p ? String(p.server || "") : ""
  }

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 15, 5, 300)
  readonly property bool notifyOnDisconnect: setting("notifyOnDisconnect", true) === true

  // Distingue una caida del tunel de una desconexion pedida por el usuario:
  // solo la primera merece una notificacion urgente. Un cambio de perfil baja y
  // sube el tunel, y tampoco tiene que avisar de la bajada.
  property string pendingProfile: ""
  property string addError: ""

  signal profileAdded(string id)

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
      case "connected": return profileName !== "" ? profileName : "Conectada"
      case "connecting": return "Levantando el tunel…"
      case "authenticating": return "Esperando el login SAML…"
      case "failed": return "Fallo la conexion"
      case "disconnected": return hasProfiles ? "Desconectada" : "Sin perfiles"
      default: return "Sin datos"
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
      lastError = "No se pudo leer el estado de la VPN"
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
    lastError = incoming === "failed" ? String(parsed.error || "") : ""
    setState(incoming)
  }

  function setState(next) {
    if (next === state) return
    var previous = state
    state = next
    if (previous === "" || previous === "unknown") return   // primer sondeo

    if (next === "connected") {
      _userInitiatedStop = false
      _switchingTo = ""
      pendingProfile = ""
      actionStatus = ""
      notify("VPN conectada", profileName + (ip !== "" ? " · " + ip : ""), "normal")
    } else if (next === "failed") {
      _userInitiatedStop = false
      _switchingTo = ""
      pendingProfile = ""
      notify("Fallo la VPN", lastError !== "" ? lastError : "El tunel no pudo levantarse", "critical")
    } else if (next === "disconnected") {
      pendingProfile = ""
      if (previous !== "connected") return
      if (_userInitiatedStop || _switchingTo !== "") {
        _userInitiatedStop = false
      } else if (notifyOnDisconnect) {
        notify("VPN desconectada", "El tunel se cayo", "critical")
      }
    }
  }

  // Sin argumento usa el perfil por defecto; con uno cambia de perfil, que el
  // CLI resuelve bajando y volviendo a subir el tunel.
  function connect(id) {
    if (connectProcess.running) return
    var target = String(id || targetProfile())
    if (target === "") return
    _userInitiatedStop = false
    _switchingTo = connected && target !== profileId ? target : ""
    pendingProfile = target
    lastError = ""
    var p = profileById(target)
    actionStatus = "Abriendo el login SAML" + (p ? " de " + p.name : "") + "…"
    // El estado optimista evita que el switch vuelva atras en el hueco entre el
    // click y el primer sondeo que ya ve el marker de autenticacion.
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
    actionStatus = "Bajando el tunel…"
    disconnectProcess.command = ["gpvpn", "disconnect"]
    disconnectProcess.running = true
    fastPoll.restart()
  }

  function toggle() {
    if (busy && !connected) return
    if (connected) disconnect()
    else connect("")
  }

  // El id sale del nombre: el formulario del panel pide solo lo imprescindible
  // y las opciones raras de `gpvpn profile add` quedan para el CLI.
  function slug(text) {
    return String(text || "").toLowerCase().trim()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "")
  }

  function addProfile(name, server, mode) {
    if (addProcess.running) return
    var id = slug(name)
    var host = String(server || "").trim()
    if (id === "" || host === "") {
      addError = "Hace falta un nombre y un servidor"
      return
    }
    // `gpvpn profile add` reemplaza sin preguntar; el formulario es de alta, no
    // de edicion, asi que un id repetido se frena aca.
    if (profileById(id)) {
      addError = "Ya hay un perfil con el id \u0027" + id + "\u0027"
      return
    }
    addError = ""
    addProcess.createdId = id
    addProcess.command = ["gpvpn", "profile", "add",
                          "--id", id,
                          "--name", String(name).trim(),
                          "--server", host,
                          "--mode", String(mode || "gateway")]
    addProcess.running = true
  }

  function elide(text) {
    var value = String(text || "").replace(/\s+/g, " ").trim()
    return value.length > 160 ? value.substring(0, 157) + "…" : value
  }

  Component.onCompleted: refresh()

  Timer {
    interval: root.refreshIntervalSec * 1000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  // Mientras algo esta en transicion conviene mirar mas seguido; se apaga sola
  // cuando el estado se asienta.
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
    id: statusProcess
    running: false
    command: []
    stdout: StdioCollector { id: statusStdout; waitForEnd: true; onStreamFinished: root._statusOutput = text }
    onExited: function (exitCode) {
      if (exitCode === 0) {
        root.applyStatus(statusStdout.text || root._statusOutput)
      } else {
        root.installed = false
        root.state = "unknown"
        root.lastError = "Falta el CLI gpvpn en el PATH"
      }
    }
  }

  Process {
    id: connectProcess
    running: false
    command: []
    stderr: StdioCollector { id: connectStderr; waitForEnd: true }
    onExited: function (exitCode) {
      if (exitCode !== 0) {
        root.lastError = root.elide(connectStderr.text || "No se pudo conectar")
        root.actionStatus = ""
        root._switchingTo = ""
        root.notify("No se pudo conectar la VPN", root.lastError, "critical")
      } else {
        root.actionStatus = ""
      }
      root.refresh()
      fastPoll.restart()
    }
  }

  Process {
    id: addProcess
    running: false
    command: []
    property string createdId: ""
    stderr: StdioCollector { id: addStderr; waitForEnd: true }
    onExited: function (exitCode) {
      if (exitCode === 0) {
        root.addError = ""
        root.profileAdded(addProcess.createdId)
      } else {
        root.addError = root.elide(addStderr.text || "No se pudo crear el perfil")
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
        root.lastError = root.elide(disconnectStderr.text || "No se pudo desconectar")
      }
      root.actionStatus = ""
      root.refresh()
      fastPoll.restart()
    }
  }
}
