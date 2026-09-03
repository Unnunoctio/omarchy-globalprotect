import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "unnunoctio.globalprotect"
  ipcTarget: "unnunoctio.globalprotect"
  manageIpc: false

  property bool cursorActive: false
  property string focusSection: "header"
  property int profileIndex: 0
  property bool addingProfile: false
  property bool errorExpanded: false
  // Source of truth for the delete dialog: empty means closed.
  property string pendingRemovalId: ""
  property string pendingRemovalName: ""
  // Empty means the form creates; with an id it edits that profile.
  property string editingId: ""

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color iconColor: vpn.state === "failed" ? urgent : (vpn.active ? foreground : dim)
  readonly property color barIconColor: vpn.state === "failed" ? (bar ? bar.urgent : Color.urgent)
                                                               : (vpn.active ? barForeground : Qt.darker(barForeground, 1.55))
  readonly property bool headerHasCursor: cursorActive && focusSection === "header" && vpn.installed

  function toggleVpn() {
    if (vpn.installed && vpn.hasProfiles) vpn.toggle()
  }

  function setHeaderCursor() {
    cursorActive = true
    focusSection = "header"
  }

  function setProfileCursor(index) {
    cursorActive = true
    focusSection = "profiles"
    profileIndex = index
  }

  function selectedProfile() {
    if (vpn.profiles.length === 0) return null
    return vpn.profiles[Math.max(0, Math.min(profileIndex, vpn.profiles.length - 1))]
  }

  // Each row turns its own profile on or off: on the one already up it
  // disconnects, on another it switches (the CLI drops and re-raises the
  // tunnel).
  function toggleProfile(p) {
    if (!p) return
    if (p.id === vpn.activeProfileId) vpn.disconnect()
    else vpn.connect(p.id)
  }

  // `gpvpn profile rm` does not disconnect, so deleting the active profile
  // would leave the tunnel up pointing at a config that no longer exists. It has
  // to be taken down first.
  function canRemove(p) {
    return !!p && p.id !== vpn.activeProfileId && !vpn.removing
  }

  function askRemoveProfile(p) {
    if (!canRemove(p)) return
    pendingRemovalName = String(p.name || p.id)
    pendingRemovalId = String(p.id)
    // Starts on Cancel: the action is destructive and has no undo.
    removeConfirm.selectedIndex = 0
  }

  function cancelRemoval() {
    pendingRemovalId = ""
    pendingRemovalName = ""
  }

  function confirmRemoval() {
    var id = pendingRemovalId
    cancelRemoval()
    vpn.removeProfile(id)
  }

  function fillForm(p) {
    nameField.text = p ? String(p.name || p.id || "") : ""
    serverField.text = p ? String(p.server || "") : ""
    modeGroup.value = p ? String(p.mode || "gateway") : "gateway"
    gatewayField.text = p ? String(p.gateway || "") : ""
    clientosDropdown.value = p ? String(p.clientos || "linux-64") : "linux-64"
  }

  function openAddForm() {
    editingId = ""
    addingProfile = true
    vpn.saveError = ""
    fillForm(null)
    setHeaderCursor()
    Qt.callLater(function () { nameField.forceActiveFocus() })
  }

  function openEditForm(p) {
    if (!p) return
    editingId = String(p.id)
    addingProfile = true
    vpn.saveError = ""
    fillForm(p)
    Qt.callLater(function () { nameField.forceActiveFocus() })
  }

  function closeAddForm() {
    addingProfile = false
    editingId = ""
    vpn.saveError = ""
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }

  function toggleAddForm() {
    if (addingProfile) closeAddForm()
    else openAddForm()
  }

  function submitForm() {
    vpn.saveProfile(editingId, nameField.text, serverField.text, modeGroup.value,
                    gatewayField.text, clientosDropdown.value)
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    if (dy === 0) return
    if (focusSection === "header") {
      if (dy > 0 && vpn.profiles.length > 0) setProfileCursor(0)
      return
    }
    if (focusSection === "profiles") {
      if (dy < 0 && profileIndex === 0) {
        setHeaderCursor()
        return
      }
      profileIndex = Math.max(0, Math.min(vpn.profiles.length - 1, profileIndex + dy))
    }
  }

  function activateCursor() {
    // The header control is no longer the switch: it now creates a profile.
    if (focusSection === "header") {
      toggleAddForm()
      return
    }
    toggleProfile(selectedProfile())
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    focusSection = "header"
    profileIndex = 0
    addingProfile = false
    errorExpanded = false
    cancelRemoval()
    vpn.refresh()
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }

  Service {
    id: vpn
    settings: root.settings
  }

  Connections {
    target: vpn
    function onProfileSaved(id) { root.closeAddForm() }
    // After a delete the list shrinks: the cursor can fall out of range.
    function onProfileRemoved(id) {
      root.profileIndex = Math.max(0, Math.min(root.profileIndex, vpn.profiles.length - 2))
    }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function connect(profile: string): string { vpn.connect(profile); return "ok" }
    function disconnect(): string { vpn.disconnect(); return "ok" }
    function refresh(): string { vpn.refresh(); return "ok" }
    function status(): string { return vpn.state }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // What used to require opening the panel just to see it. BarIconButton
    // extends WidgetButton, which already resolves the tooltip against the bar.
    tooltipText: {
      if (!vpn.installed) return "GlobalProtect · backend unavailable"
      if (vpn.state === "connected") {
        var parts = [vpn.profileName !== "" ? vpn.profileName : "Conectada"]
        if (vpn.ip !== "") parts.push(vpn.ip)
        if (uptime.text !== "") parts.push("hace " + uptime.text)
        return parts.join(" · ")
      }
      if (vpn.state === "connecting") return "GlobalProtect · bringing the tunnel up…"
      if (vpn.state === "authenticating") return "GlobalProtect · waiting for the SAML login…"
      if (vpn.state === "failed") return "GlobalProtect · connection failed"
      return vpn.hasProfiles ? "GlobalProtect · disconnected" : "GlobalProtect · no profiles"
    }
    iconComponent: Component {
      Item {
        ShieldIcon {
          anchors.centerIn: parent
          iconSize: Style.space(13)
          color: root.barIconColor
          filled: vpn.connected
          holeColor: root.bar ? root.bar.background : Color.background
          opacity: vpn.busyState ? 0.55 : 1.0

          // A pulse while negotiating: the hollow shield alone is not enough to
          // tell "connecting" from "disconnected".
          SequentialAnimation on opacity {
            running: vpn.busyState
            loops: Animation.Infinite
            NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutQuad }
            NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutQuad }
          }
        }
      }
    }
    onPressed: function (buttonCode) {
      if (buttonCode === Qt.RightButton) root.toggleVpn()
      else if (buttonCode === Qt.MiddleButton) vpn.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // While typing in the form, keys are text rather than shortcuts.
      blocked: nameField.activeFocus || serverField.activeFocus
               || gatewayField.activeFocus || clientosDropdown.popupOpen
      onMoveRequested: function (dx, dy) {
        if (root.pendingRemovalId !== "") {
          if (dx !== 0) removeConfirm.selectedIndex = removeConfirm.selectedIndex === 0 ? 1 : 0
          return
        }
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: {
        if (root.pendingRemovalId !== "") {
          if (removeConfirm.selectedIndex === 0) root.cancelRemoval()
          else root.confirmRemoval()
          return
        }
        if (root.cursorActive) root.activateCursor()
      }
      onCloseRequested: {
        if (root.pendingRemovalId !== "") root.cancelRemoval()
        else if (root.addingProfile) root.closeAddForm()
        else root.close()
      }
      onDeleteRequested: {
        if (root.pendingRemovalId === "" && root.focusSection === "profiles") {
          root.askRemoveProfile(root.selectedProfile())
        }
      }
      onTabRequested: function (direction) { root.switchPanel(direction) }
      onTextKey: function (t) {
        if (root.pendingRemovalId !== "") return
        var key = String(t || "").toLowerCase()
        if (key === "t") root.toggleVpn()
        else if (key === "n") root.toggleAddForm()
        else if (key === "e") { if (root.focusSection === "profiles") root.openEditForm(root.selectedProfile()) }
        else if (key === "d") { if (root.focusSection === "profiles" && root.selectedProfile()) vpn.setDefaultProfile(root.selectedProfile().id) }
        else if (key === "r") vpn.refresh()
        // `l` no llega hasta aca: PanelKeyCatcher lo gasta como flecha derecha.
        else if (key === "g") Quickshell.execDetached(["uwsm-app", "--", "foot", "-T", "GlobalProtect", "bash", "-c", "gpvpn logs -f"])
      }

      ConfirmDialog {
        id: removeConfirm
        anchors.fill: parent
        z: 10
        opened: root.pendingRemovalId !== ""
        message: "Delete the profile \u00AB" + root.pendingRemovalName + "\u00BB?"
        confirmText: "Delete"
        cancelText: "Cancel"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onCanceled: root.cancelRemoval()
        onConfirmed: root.confirmRemoval()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          Item {
            id: header
            width: parent.width
            implicitHeight: hero.implicitHeight
            // Read by the hero's trailingControl, whose `root` resolves to
            // PanelHero rather than to this Panel.
            readonly property bool ringVisible: root.headerHasCursor
            readonly property bool formOpen: root.addingProfile
            function focusHero() { root.setHeaderCursor() }

            PanelHero {
              id: hero
              width: parent.width
              title: "GlobalProtect"
              meta: vpn.stateLabel()
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: vpn.active ? 1.0 : 0.5
              iconComponent: Component {
                ShieldIcon {
                  iconSize: Style.font.display
                  color: root.iconColor
                  filled: vpn.connected
                  holeColor: Color.popups.background
                }
              }

              trailingControl: Component {
                PanelActionButton {
                  visible: vpn.installed
                  bordered: true
                  iconText: header.formOpen ? "󰅖" : "󰐕"
                  tooltipText: header.formOpen ? "Cancel" : "Add profile"
                  foreground: hero.foreground
                  fontFamily: hero.fontFamily
                  hasCursor: header.ringVisible
                  onHovered: function (on) { if (on) header.focusHero() }
                  onClicked: root.toggleAddForm()
                }
              }
            }
          }

          Column {
            visible: vpn.actionStatus !== "" || vpn.lastError !== ""
            width: parent.width
            spacing: Style.space(2)

            Text {
              width: parent.width
              text: vpn.actionStatus !== "" ? vpn.actionStatus
                    : (root.errorExpanded ? vpn.lastErrorFull : vpn.lastError)
              color: vpn.lastError !== "" && vpn.actionStatus === "" ? root.urgent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            // A certificate or HIP error does not fit in 160 characters, and the
            // detail only lived behind `g` -> logs.
            Text {
              visible: vpn.actionStatus === "" && vpn.errorTruncated
              text: root.errorExpanded ? "show less" : "show more"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.underline: expandArea.containsMouse

              MouseArea {
                id: expandArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.errorExpanded = !root.errorExpanded
              }
            }
          }

          PanelSeparator {
            visible: vpn.connected
            foreground: root.foreground
          }

          Column {
            visible: vpn.connected
            width: parent.width
            spacing: Style.spacing.labelGap

            // In portal mode both are shown: the portal being authenticated
            // against, and the gateway picked inside it.
            InfoPair {
              visible: vpn.serverHost !== ""
              label: vpn.profileMode === "portal" ? "Portal" : "Server"
              value: vpn.serverHost
            }
            InfoPair {
              visible: vpn.profileMode === "portal"
              label: "Gateway"
              value: vpn.gatewayName !== "" ? vpn.gatewayName : "automatic"
            }
            InfoPair { label: "Interfaz"; value: vpn.interfaceName }
            InfoPair {
              visible: vpn.ip !== ""
              label: "IP"
              value: vpn.ip
            }
            InfoPair {
              visible: uptime.text !== ""
              label: "Up for"
              value: uptime.text
            }
          }

          PanelSeparator {
            visible: vpn.installed
            foreground: root.foreground
          }

          Column {
            id: addForm
            visible: root.addingProfile
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: root.editingId !== "" ? "EDIT PROFILE" : "NEW PROFILE"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            FormRow {
              label: "Name"
              TextField {
                id: nameField
                Layout.fillWidth: true
                placeholderText: "Work"
                foreground: root.foreground
                font.pixelSize: Style.font.bodySmall
                verticalPadding: Style.space(4)
                onAccepted: serverField.forceActiveFocus()
                Keys.onEscapePressed: root.closeAddForm()
              }
            }

            FormRow {
              label: "Server"
              TextField {
                id: serverField
                Layout.fillWidth: true
                placeholderText: "vpn.company.com"
                foreground: root.foreground
                font.pixelSize: Style.font.bodySmall
                verticalPadding: Style.space(4)
                onAccepted: modeGroup.value === "portal" ? gatewayField.forceActiveFocus()
                                                          : root.submitForm()
                Keys.onEscapePressed: root.closeAddForm()
              }
            }

            FormRow {
              label: "Mode"
              ButtonGroup {
                id: modeGroup
                Layout.fillWidth: true
                focusable: false
                value: "gateway"
                options: ["gateway", "portal"]
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                onChanged: function (v) { modeGroup.value = v }
              }
            }

            // Only applies when authenticating against a portal: it is
            // openconnect's --authgroup, the official client's dropdown.
            FormRow {
              visible: modeGroup.value === "portal"
              label: "Gateway"
              TextField {
                id: gatewayField
                Layout.fillWidth: true
                placeholderText: "whichever the portal picks"
                foreground: root.foreground
                font.pixelSize: Style.font.bodySmall
                verticalPadding: Style.space(4)
                onAccepted: root.submitForm()
                Keys.onEscapePressed: root.closeAddForm()
              }
            }

            FormRow {
              label: "System"
              Dropdown {
                id: clientosDropdown
                Layout.fillWidth: true
                showLabel: false
                value: "linux-64"
                options: ["linux-64", "linux", "win", "mac-intel", "android", "apple-ios"]
                foreground: root.foreground
                fontFamily: root.fontFamily
                onChanged: function (v) { clientosDropdown.value = v }
              }
            }

            Text {
              visible: vpn.saveError !== ""
              width: parent.width
              text: vpn.saveError
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(8)

              Text {
                Layout.fillWidth: true
                text: root.editingId !== "" ? "the id does not change when editing" : "the id comes from the name"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }

              Button {
                text: "Cancel"
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                onClicked: root.closeAddForm()
              }

              Button {
                id: saveButton
                readonly property bool ready: nameField.text.trim() !== ""
                                              && serverField.text.trim() !== ""
                                              && !vpn.saving
                text: vpn.saving ? "Saving…" : "Save"
                bordered: true
                selected: ready
                opacity: ready ? 1.0 : 0.45
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                onClicked: if (ready) root.submitForm()
              }
            }
          }

          PanelSeparator {
            visible: root.addingProfile
            foreground: root.foreground
          }

          Column {
            visible: vpn.installed
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "PROFILES"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              visible: !vpn.hasProfiles
              width: parent.width
              text: "No profiles configured.\nAdd one with the + button above."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Column {
              id: profileColumn
              visible: vpn.hasProfiles
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: vpn.profiles
                ProfileRow {
                  required property var modelData
                  required property int index
                  width: profileColumn.width
                  profile: modelData
                  rowIndex: index
                }
              }
            }
          }

          // The backend is a separate package, so it can be missing or older
          // than what this panel expects.
          Text {
            visible: vpn.cliOutdated
            width: parent.width
            text: "The gpvpn backend is older than " + vpn.minCliVersion
                  + (vpn.cliVersion !== "" ? " (you have " + vpn.cliVersion + ")" : "")
                  + ".\nUpdate it: github.com/Unnunoctio/gpvpn"
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Text {
            visible: !vpn.installed
            width: parent.width
            text: "The `gpvpn` CLI was not found.\nInstall it from: github.com/Unnunoctio/gpvpn"
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Text {
            width: parent.width
            text: "n new · e edit · x delete · d default · t connect · r refresh · g logs · esc"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }

  // Uptime is computed from the unit's timestamp, so it has to be repainted
  // even when the state does not change.
  QtObject {
    id: uptime
    property string text: ""
  }

  // Runs whenever there is a tunnel, not only with the panel open: the bar
  // tooltip shows the uptime too.
  Timer {
    interval: 1000
    running: vpn.connected
    repeat: true
    triggeredOnStart: true
    onTriggered: uptime.text = vpn.uptimeText()
  }

  // Label on the left, control on the right: whatever child is passed in is the
  // control, and it stretches on its own.
  component FormRow: RowLayout {
    id: formRow
    property string label: ""

    width: parent ? parent.width : implicitWidth
    spacing: Style.space(8)

    Text {
      Layout.preferredWidth: Style.space(62)
      Layout.alignment: Qt.AlignVCenter
      text: formRow.label
      color: root.foreground
      opacity: 0.6
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }

  component ProfileRow: CursorSurface {
    id: profileRow
    property var profile: null
    property int rowIndex: 0
    readonly property bool isActive: profile && profile.id === vpn.activeProfileId
    readonly property bool isDefault: profile && profile.id === vpn.defaultProfile

    hasCursor: root.cursorActive && root.focusSection === "profiles" && root.profileIndex === rowIndex
    foreground: root.foreground
    implicitHeight: Math.max(rowContent.implicitHeight, profileSwitch.implicitHeight) + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setProfileCursor(profileRow.rowIndex)
      onClicked: {
        root.setProfileCursor(profileRow.rowIndex)
        root.toggleProfile(profileRow.profile)
      }
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Rectangle {
        width: Style.space(7)
        height: width
        radius: width / 2
        Layout.alignment: Qt.AlignVCenter
        color: profileRow.isActive ? root.foreground : "transparent"
        border.width: profileRow.isActive ? 0 : 1
        border.color: root.dim
      }

      ColumnLayout {
        id: rowContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          text: profileRow.profile ? String(profileRow.profile.name || profileRow.profile.id) : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          text: profileRow.profile ? String(profileRow.profile.server || "") : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideLeft
        }
      }

      Text {
        // Yields its place to the buttons while the cursor is on the row.
        visible: profileRow.isDefault && !profileRow.isActive && !profileRow.hasCursor
        text: "default"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        Layout.alignment: Qt.AlignVCenter
      }

      // All three appear only with the cursor on the row, to keep the list from
      // being crowded with actions that are almost never used.
      PanelActionButton {
        visible: profileRow.hasCursor && !profileRow.isDefault
        iconText: "󰐃"
        tooltipText: "Set as default"
        foreground: root.foreground
        fontFamily: root.fontFamily
        hasCursor: false
        Layout.alignment: Qt.AlignVCenter
        onClicked: vpn.setDefaultProfile(profileRow.profile ? profileRow.profile.id : "")
      }

      PanelActionButton {
        visible: profileRow.hasCursor
        iconText: "󰏫"
        tooltipText: "Edit profile"
        foreground: root.foreground
        fontFamily: root.fontFamily
        hasCursor: false
        Layout.alignment: Qt.AlignVCenter
        onClicked: root.openEditForm(profileRow.profile)
      }

      // The active profile offers no delete: disconnect first.
      PanelActionButton {
        visible: profileRow.hasCursor && !profileRow.isActive
        iconText: "󰩹"
        tooltipText: "Delete profile"
        foreground: root.foreground
        fontFamily: root.fontFamily
        hasCursor: false
        Layout.alignment: Qt.AlignVCenter
        onClicked: root.askRemoveProfile(profileRow.profile)
      }

      // The row's switch governs its own profile; the whole row stays
      // clickable, but the switch eats the click when it lands on it.
      ToggleSwitch {
        id: profileSwitch
        Layout.alignment: Qt.AlignVCenter
        checked: profileRow.isActive
        busy: vpn.busy && profileRow.isActive
        cursorRing: false
        trackHeight: Style.space(18)
        foreground: root.foreground
        onHovered: function (on) { if (on) root.setProfileCursor(profileRow.rowIndex) }
        onToggled: {
          root.setProfileCursor(profileRow.rowIndex)
          root.toggleProfile(profileRow.profile)
        }
      }
    }
  }

  component InfoPair: Item {
    id: pair
    property string label: ""
    property string value: ""

    width: parent.width
    implicitHeight: Math.max(labelText.implicitHeight, valueText.implicitHeight)

    Text {
      id: labelText
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: pair.label
      color: root.foreground
      opacity: 0.6
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Text {
      id: valueText
      anchors.left: labelText.right
      anchors.leftMargin: Style.space(8)
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: pair.value
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      horizontalAlignment: Text.AlignRight
      elide: Text.ElideLeft
    }
  }
}
