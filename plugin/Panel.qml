import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property string dialerBin: Quickshell.env("HOME") + "/.local/bin/omarchy-dialer"

  property bool registered: false
  property string callState: "offline"
  property string activeCall: ""
  property string extension: ""
  property string server: ""
  property string dialNumber: ""
  property int callSeconds: 0
  property var recentList: []

  // Audio settings state
  property bool showAudioSettings: false
  property var audioInputs: []
  property var audioOutputs: []
  property string currentInput: ""
  property string currentOutput: ""

  readonly property bool isInCall: callState === "in_call" || callState === "calling"
  readonly property string tooltipStatus: registered 
    ? ("Phone (Ext " + (extension ? extension : "SIP") + " • Connected)") 
    : "Phone (Offline)"

  function open() {
    root.controller.show()
    refreshStatus()
    loadRecents()
    loadAudioDevices()
  }

  function close() {
    root.controller.hide()
    root.showAudioSettings = false
  }

  function toggle() {
    if (root.opened) close()
    else open()
  }

  function dial(number) {
    var target = (number || dialNumber).trim()
    if (!target) return
    Quickshell.execDetached([root.dialerBin, "dial", target])
    root.callState = "calling"
    root.activeCall = target
    root.callSeconds = 0
    Qt.callLater(refreshStatus)
    loadRecents()
  }

  function hangup() {
    Quickshell.execDetached([root.dialerBin, "hangup"])
    root.callState = "idle"
    root.activeCall = ""
    root.callSeconds = 0
    Qt.callLater(refreshStatus)
  }

  function answer() {
    Quickshell.execDetached([root.dialerBin, "answer"])
    root.callState = "in_call"
    Qt.callLater(refreshStatus)
  }

  function sendDtmf(digit) {
    Quickshell.execDetached([root.dialerBin, "dtmf", String(digit)])
  }

  function appendDigit(digit) {
    dialNumber += digit
    if (isInCall) {
      sendDtmf(digit)
    }
  }

  function backspace() {
    if (dialNumber.length > 0) {
      dialNumber = dialNumber.slice(0, -1)
    }
  }

  function clearNumber() {
    dialNumber = ""
  }

  function formatTime(secs) {
    var m = Math.floor(secs / 60)
    var s = secs % 60
    return (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s
  }

  function refreshStatus() {
    if (!statusProcess.running) {
      statusProcess.running = true
    }
  }

  function loadRecents() {
    if (!recentsProcess.running) {
      recentsProcess.running = true
    }
  }

  function loadAudioDevices() {
    if (!devicesProcess.running) {
      devicesProcess.running = true
    }
  }

  function setAudioInput(name) {
    currentInput = name
    Quickshell.execDetached([root.dialerBin, "set-device", "--input", name])
  }

  function setAudioOutput(name) {
    currentOutput = name
    Quickshell.execDetached([root.dialerBin, "set-device", "--output", name])
  }

  function testAudio() {
    Quickshell.execDetached([root.dialerBin, "test-audio"])
  }

  function boostMic() {
    Quickshell.execDetached([root.dialerBin, "boost-mic", "80%"])
    Qt.callLater(loadAudioDevices)
  }

  // Periodic poll timer
  Timer {
    interval: 2000
    running: root.opened || root.isInCall
    repeat: true
    onTriggered: root.refreshStatus()
  }

  // Call duration timer
  Timer {
    interval: 1000
    running: root.isInCall
    repeat: true
    onTriggered: root.callSeconds += 1
  }

  // Status worker process
  Process {
    id: statusProcess
    running: false
    command: [root.dialerBin, "status"]
    stdout: StdioCollector {
      id: statusOut
      waitForEnd: true
      onStreamFinished: function() {
        try {
          var data = JSON.parse(statusOut.text)
          root.registered = data.registered === true
          root.callState = data.state || "idle"
          root.extension = data.extension || ""
          root.server = data.server || ""
          if (data.active_call) {
            root.activeCall = data.active_call
          }
        } catch (e) {}
      }
    }
  }

  // Recents worker process
  Process {
    id: recentsProcess
    running: false
    command: [root.dialerBin, "recents"]
    stdout: StdioCollector {
      id: recentsOut
      waitForEnd: true
      onStreamFinished: function() {
        try {
          var list = JSON.parse(recentsOut.text)
          if (Array.isArray(list)) {
            root.recentList = list.slice(0, 4)
          }
        } catch (e) {}
      }
    }
  }

  // Audio devices worker process
  Process {
    id: devicesProcess
    running: false
    command: [root.dialerBin, "devices"]
    stdout: StdioCollector {
      id: devicesOut
      waitForEnd: true
      onStreamFinished: function() {
        try {
          var data = JSON.parse(devicesOut.text)
          root.audioInputs = data.inputs || []
          root.audioOutputs = data.outputs || []
          root.currentInput = data.selected_input || ""
          root.currentOutput = data.selected_output || ""
        } catch (e) {}
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: Style.space(320)
    contentHeight: Style.space(520)

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.spacing.popupPadding
      spacing: Style.space(10)

      // Header Bar
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(8)

        Text {
          text: "󰏲"
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          color: root.isInCall ? "#22c55e" : Color.accent
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: 1

          Text {
            text: "SIP Softphone"
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
            color: Color.foreground
          }

          RowLayout {
            spacing: Style.space(4)

            Rectangle {
              width: 7
              height: 7
              radius: 4
              color: root.isInCall ? "#3b82f6" : (root.registered ? "#22c55e" : "#ef4444")
            }

            Text {
              text: root.isInCall 
                ? ("In Call (" + root.formatTime(root.callSeconds) + ")")
                : (root.registered ? ("Ext " + (root.extension ? root.extension : "SIP") + " • Connected") : "Offline")
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              color: Qt.darker(Color.foreground, 1.4)
            }
          }
        }

        // Audio Settings Toggle Button
        Button {
          iconText: ""
          text: ""
          tooltipText: root.showAudioSettings ? "Show Dialpad" : "Audio Device Settings"
          selected: root.showAudioSettings
          fontSize: Style.font.caption
          onClicked: {
            root.showAudioSettings = !root.showAudioSettings
            if (root.showAudioSettings) root.loadAudioDevices()
          }
        }

        // Refresh button
        Button {
          iconText: ""
          text: ""
          tooltipText: "Refresh status"
          fontSize: Style.font.caption
          onClicked: root.refreshStatus()
        }
      }

      // ----------------------------------------------------
      // VIEW A: AUDIO SETTINGS DRAWER (When showAudioSettings is true)
      // ----------------------------------------------------
      ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: root.showAudioSettings
        spacing: Style.space(8)

        Text {
          text: "Audio Devices"
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
          color: Color.foreground
        }

        // Microphone Section
        Text {
          text: "󰍬 Microphone (Input)"
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
          color: Color.accent
        }

        Repeater {
          model: root.audioInputs

          delegate: Rectangle {
            Layout.fillWidth: true
            height: Style.space(34)
            radius: Style.cornerRadius
            color: (root.currentInput === modelData.name) 
              ? Style.selectedFillFor(Color.foreground, Color.accent)
              : (inMouse.containsMouse ? Style.hoverFillFor(Color.foreground, Color.accent) : "transparent")
            border.width: 1
            border.color: (root.currentInput === modelData.name) ? Color.accent : Color.popups.border

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)

              Text {
                text: root.currentInput === modelData.name ? "✓" : " "
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                color: Color.accent
                font.bold: true
              }

              Text {
                text: modelData.description
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                color: Color.foreground
                Layout.fillWidth: true
                elide: Text.ElideRight
              }

              Text {
                text: modelData.volume
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                color: Qt.darker(Color.foreground, 1.5)
              }
            }

            MouseArea {
              id: inMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.setAudioInput(modelData.name)
            }
          }
        }

        // Speaker / Output Section
        Text {
          text: "󰕾 Speaker / Headset (Output)"
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
          color: Color.accent
        }

        Repeater {
          model: root.audioOutputs

          delegate: Rectangle {
            Layout.fillWidth: true
            height: Style.space(34)
            radius: Style.cornerRadius
            color: (root.currentOutput === modelData.name) 
              ? Style.selectedFillFor(Color.foreground, Color.accent)
              : (outMouse.containsMouse ? Style.hoverFillFor(Color.foreground, Color.accent) : "transparent")
            border.width: 1
            border.color: (root.currentOutput === modelData.name) ? Color.accent : Color.popups.border

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)

              Text {
                text: root.currentOutput === modelData.name ? "✓" : " "
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                color: Color.accent
                font.bold: true
              }

              Text {
                text: modelData.description
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                color: Color.foreground
                Layout.fillWidth: true
                elide: Text.ElideRight
              }

              Text {
                text: modelData.volume
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                color: Qt.darker(Color.foreground, 1.5)
              }
            }

            MouseArea {
              id: outMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.setAudioOutput(modelData.name)
            }
          }
        }

        Item { Layout.fillHeight: true }

        // Actions: Test Speaker & Boost Mic
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(6)

          Button {
            Layout.fillWidth: true
            iconText: "󰕾"
            text: "Test Audio"
            fontSize: Style.font.caption
            onClicked: root.testAudio()
          }

          Button {
            Layout.fillWidth: true
            iconText: "󰍬"
            text: "Boost Mic (80%)"
            fontSize: Style.font.caption
            onClicked: root.boostMic()
          }
        }

        Button {
          Layout.fillWidth: true
          iconText: ""
          text: "Back to Dialpad"
          fontSize: Style.font.body
          onClicked: root.showAudioSettings = false
        }
      }

      // ----------------------------------------------------
      // VIEW B: STANDARD DIALPAD (When showAudioSettings is false)
      // ----------------------------------------------------
      ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: !root.showAudioSettings
        spacing: Style.space(10)

        // Active Call Banner (if in call)
        Rectangle {
          Layout.fillWidth: true
          height: Style.space(36)
          visible: root.isInCall
          radius: Style.cornerRadius
          color: Qt.rgba(0.14, 0.77, 0.37, 0.15)
          border.width: 1
          border.color: "#22c55e"

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(10)

            Text {
              text: "󰄬 Connected: " + (root.activeCall || root.dialNumber)
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              color: Color.foreground
              Layout.fillWidth: true
              elide: Text.ElideRight
            }

            Text {
              text: root.formatTime(root.callSeconds)
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
              color: "#22c55e"
            }
          }
        }

        // Number Display & Backspace Field
        Rectangle {
          Layout.fillWidth: true
          height: Style.space(44)
          radius: Style.cornerRadius
          color: Style.controlFill(false, false, Color.foreground, Color.accent)
          border.width: 1
          border.color: Color.popups.border

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(6)
            spacing: Style.space(6)

            TextInput {
              id: numberInput
              Layout.fillWidth: true
              text: root.dialNumber
              font.family: Style.font.family
              font.pixelSize: Style.font.title
              font.bold: true
              color: Color.foreground
              selectByMouse: true
              clip: true
              onTextChanged: root.dialNumber = text
              onAccepted: root.dial(root.dialNumber)

              Text {
                visible: numberInput.text === ""
                text: "Enter number or ext..."
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                color: Qt.darker(Color.foreground, 1.8)
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Button {
              visible: root.dialNumber.length > 0
              text: ""
              iconText: ""
              tooltipText: "Backspace"
              fontSize: Style.font.body
              onClicked: root.backspace()
            }

            Button {
              visible: root.dialNumber.length > 0
              text: ""
              iconText: "󰅖"
              tooltipText: "Clear"
              fontSize: Style.font.body
              onClicked: root.clearNumber()
            }
          }
        }

        // Dialpad Grid (3 columns x 4 rows)
        GridLayout {
          Layout.fillWidth: true
          columns: 3
          rowSpacing: Style.space(6)
          columnSpacing: Style.space(6)

          Repeater {
            model: [
              { digit: "1", sub: "" },
              { digit: "2", sub: "ABC" },
              { digit: "3", sub: "DEF" },
              { digit: "4", sub: "GHI" },
              { digit: "5", sub: "JKL" },
              { digit: "6", sub: "MNO" },
              { digit: "7", sub: "PQRS" },
              { digit: "8", sub: "TUV" },
              { digit: "9", sub: "WXYZ" },
              { digit: "*", sub: "" },
              { digit: "0", sub: "+" },
              { digit: "#", sub: "" }
            ]

            delegate: Rectangle {
              Layout.fillWidth: true
              height: Style.space(48)
              radius: Style.cornerRadius
              color: padMouse.pressed ? Style.pressedFillFor(Color.foreground, Color.accent)
                    : (padMouse.containsMouse ? Style.hoverFillFor(Color.foreground, Color.accent) : "transparent")
              border.width: 1
              border.color: Color.popups.border

              ColumnLayout {
                anchors.centerIn: parent
                spacing: 0

                Text {
                  text: modelData.digit
                  font.family: Style.font.family
                  font.pixelSize: Style.font.title
                  font.bold: true
                  color: Color.foreground
                  Layout.alignment: Qt.AlignHCenter
                }

                Text {
                  visible: modelData.sub !== ""
                  text: modelData.sub
                  font.family: Style.font.family
                  font.pixelSize: Style.space(9)
                  color: Qt.darker(Color.foreground, 1.6)
                  Layout.alignment: Qt.AlignHCenter
                }
              }

              MouseArea {
                id: padMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.appendDigit(modelData.digit)
              }
            }
          }
        }

        // Call / End Action Button
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)

          // Green Call Button
          Rectangle {
            Layout.fillWidth: true
            height: Style.space(42)
            visible: !root.isInCall
            radius: Style.cornerRadius
            color: callMouse.pressed ? "#15803d" : (callMouse.containsMouse ? "#16a34a" : "#22c55e")

            RowLayout {
              anchors.centerIn: parent
              spacing: Style.space(8)

              Text {
                text: "󰏲"
                font.family: Style.font.family
                font.pixelSize: Style.font.title
                color: "white"
              }

              Text {
                text: "Call"
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: true
                color: "white"
              }
            }

            MouseArea {
              id: callMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.dial(root.dialNumber)
            }
          }

          // Red End Call Button
          Rectangle {
            Layout.fillWidth: true
            height: Style.space(42)
            visible: root.isInCall
            radius: Style.cornerRadius
            color: endMouse.pressed ? "#b91c1c" : (endMouse.containsMouse ? "#dc2626" : "#ef4444")

            RowLayout {
              anchors.centerIn: parent
              spacing: Style.space(8)

              Text {
                text: "󰏲"
                font.family: Style.font.family
                font.pixelSize: Style.font.title
                color: "white"
              }

              Text {
                text: "End Call"
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: true
                color: "white"
              }
            }

            MouseArea {
              id: endMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.hangup()
            }
          }
        }

        // Recent Calls strip
        ColumnLayout {
          Layout.fillWidth: true
          visible: root.recentList.length > 0
          spacing: Style.space(4)

          Text {
            text: "Recent Calls"
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
            color: Qt.darker(Color.foreground, 1.5)
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(4)

            Repeater {
              model: root.recentList

              delegate: Rectangle {
                Layout.fillWidth: true
                height: Style.space(26)
                radius: Style.cornerRadius
                color: recMouse.containsMouse ? Style.hoverFillFor(Color.foreground, Color.accent) : "transparent"
                border.width: 1
                border.color: Color.popups.border

                Text {
                  anchors.centerIn: parent
                  text: modelData.number
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  color: Color.foreground
                  elide: Text.ElideRight
                }

                MouseArea {
                  id: recMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    root.dialNumber = modelData.number
                    root.dial(modelData.number)
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
