import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.leandro-3rne.apple-music"

  readonly property var service: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor("io.github.leandro-3rne.apple-music")
    : null

  readonly property bool hasMedia: service ? service.hasMedia : false
  readonly property bool playing: service ? service.playing : false
  readonly property string title: service ? service.title : ""
  readonly property string artist: service ? service.artist : ""

  property bool popoverOpen: false
  // The bar's panel navigation contract uses `opened` to identify widgets
  // that participate in Tab cycling. Keep it mirrored to the music popover.
  readonly property bool opened: popoverOpen
  // Standard panel controls keep the last hovered target lightly highlighted
  // after the pointer leaves. The popup owns one shared cursor so only one
  // button can retain that state at a time.
  property bool cursorActive: false
  property int cursorIndex: -1
  property bool popoutSwitchClosing: false
  property int popoutSwitchGeneration: 0

  // Flattens track metadata for the bar's tooltip: one line, no angle
  // brackets, trimmed to a sane length for a hover label.
  function tooltipSafe(text) {
    return String(text || "")
      .replace(/[<>]/g, "")
      .replace(/\s+/g, " ")
      .trim()
      .substring(0, 200)
  }

  // Standard bar-widget lifecycle trio, so the bar's single-popup
  // coordinator (below) and any external summon can drive this widget the
  // same way every other one is driven.
  function open() {
    root.popoutSwitchGeneration += 1
    root.popoutSwitchClosing = false
    if (bar && typeof bar.requestPopout === "function") bar.requestPopout(root)
    popoverOpen = true
  }
  function close() {
    root.popoutSwitchGeneration += 1
    root.popoutSwitchClosing = false
    popoverOpen = false
  }
  function toggle() { if (popoverOpen) close(); else open() }
  function closeForPopoutSwitch() {
    // Leave the old popover mounted for one event-loop turn, matching the
    // brief handoff used by KeyboardPanel when two normal shell panels are
    // switched. The generation guard prevents a fast reopen from being closed
    // by this delayed handoff.
    var generation = ++root.popoutSwitchGeneration
    root.popoutSwitchClosing = true
    Qt.callLater(function() {
      if (generation !== root.popoutSwitchGeneration) return
      root.popoverOpen = false
      root.popoutSwitchClosing = false
    })
  }

  // Only one bar popup is meant to be open at a time; this is what tells
  // the bar host to release whichever other widget's popup was open.
  function syncPopout() {
    if (!bar) return
    if (popoverOpen) {
      if (bar.activePopout !== root) bar.requestPopout(root)
    } else if (bar.activePopout === root) {
      bar.releasePopout(root)
    }
  }

  function cursorTargets() {
    return root.hasMedia ? [0, 1, 2, 3] : [3]
  }

  function moveCursor(dx, dy) {
    if (dx === 0 && dy === 0) return
    var targets = root.cursorTargets()
    if (!root.cursorActive) {
      root.cursorActive = true
      root.cursorIndex = root.hasMedia ? 1 : targets[0]
      return
    }

    // Transport controls are one horizontal row; the window button is the
    // row beneath it. Keep the two axes independent so Left/Right never jump
    // to the button and Up/Down never walk through Previous/Play/Next.
    if (dx !== 0) {
      if (!root.hasMedia || root.cursorIndex === 3) return
      root.cursorIndex = Math.max(0, Math.min(root.cursorIndex + (dx > 0 ? 1 : -1), 2))
    } else if (root.hasMedia) {
      if (dy > 0 && root.cursorIndex < 3) root.cursorIndex = 3
      else if (dy < 0 && root.cursorIndex === 3) root.cursorIndex = 1
    }
  }

  function activateCursor() {
    if (!root.cursorActive) return
    if (!root.service) return
    if (root.cursorIndex === 0 && prevButton.enabled) root.service.runAction("previous")
    else if (root.cursorIndex === 1 && playButton.enabled) root.service.runAction("playPause")
    else if (root.cursorIndex === 2 && nextButton.enabled) root.service.runAction("next")
    else if (root.cursorIndex === 3) root.openWindow()
  }

  onPopoverOpenChanged: {
    syncPopout()
    if (popoverOpen) {
      root.cursorActive = false
      root.cursorIndex = -1
      if (service) service.refresh()
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    }
  }
  onBarChanged: syncPopout()
  Component.onDestruction: if (bar && bar.activePopout === root) bar.releasePopout(root)

  // Toggle: bar-icon right-click and the popover's Open/Hide button. Hides
  // an already-open, in-view window instead of doing nothing.
  function openWindow() {
    if (service) service.openWindow()
    close()
  }

  // Always brings the window into view, never hides it. Used by the
  // artwork/title tap — that should reliably take you to the window, not
  // occasionally hide it because it happened to already be in view.
  function focusWindowOnly() {
    if (service) service.focusWindow()
    close()
  }

  // Keep the slot at the same width as the other icon-only bar modules. The
  // host centers the active mark on this slot; extra trailing width would
  // move both the icon and its mark left and leave too much room on the right.
  implicitWidth: iconButton.implicitWidth
  implicitHeight: iconButton.implicitHeight
  // Keep the active mark compact and centered under the optical music glyph
  // instead of using the bar's wider fallback extent.
  readonly property real openPanelIndicatorWidth: Style.space(16)

  // BarIconButton (not a bare Text) is what every other bar icon uses: it
  // renders through OpticalGlyph inside a fixed Style.bar.iconCanvas square
  // using Style.bar.iconFont, so it lines up with its neighbors instead of
  // being centered within the whole widget slot at a mismatched font size.
  // It also registers as a proper bar click target (multi-popup
  // coordination) and swaps in iconComponent in place of the glyph, which
  // is what drives the playing visualization below.
  BarIconButton {
    id: iconButton
    anchors.fill: parent
    bar: root.bar
    // Routed through iconComponent (idleIconComponent below) rather than
    // BarIconButton's built-in `text`, so the swap to the playing
    // visualizer and the idle glyph share one code path.
    useActiveColor: false
    // The bar owns how a tooltip is rendered, so track metadata is flattened
    // to a single line of plain characters on the way out rather than handed
    // over as-is — the popover's own labels, which this plugin does control,
    // still show the title exactly as reported.
    // Details are shown only in the click-opened player panel.
    tooltipText: ""
    iconComponent: root.playing ? visualizerComponent : idleIconComponent

    onPressed: function(button) {
      if (button === Qt.RightButton) root.openWindow()
      else root.toggle()
    }

    // Raw wheel deltas are far noisier than one scroll gesture: trackpads
    // report many small events per swipe rather than a single ±120 "click".
    // Reacting to every nonzero delta skips a track per event instead of
    // per gesture, so this accumulates deltas and acts once the total
    // reaches one notch's worth, then goes quiet briefly so a fast fling
    // can't still fire several skips in a row.
    property real wheelAccum: 0

    onWheelMoved: function(delta) {
      if (!root.hasMedia || !root.service || wheelCooldown.running) return
      wheelAccum += delta
      if (Math.abs(wheelAccum) < 120) return
      root.service.runAction(wheelAccum > 0 ? "previous" : "next")
      wheelAccum = 0
      wheelCooldown.restart()
    }

    Timer {
      id: wheelCooldown
      interval: 350
    }
  }

  Component {
    id: idleIconComponent
    OpticalGlyph {
      width: parent.width
      height: parent.height
      anchors.centerIn: parent
      anchors.verticalCenterOffset: 1
      text: "󰝚"
      fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
      fontSize: Style.bar.iconFont
      color: root.bar ? root.bar.barForeground : Color.foreground
    }
  }

  Component {
    id: visualizerComponent
    PlayingVisualizer {
      // Optical correction for the animated bars only; the idle music note
      // deliberately keeps its existing centered position.
      anchors.horizontalCenterOffset: 1
      foreground: root.bar ? root.bar.barForeground : Color.foreground
    }
  }

  // KeyboardPanel, not PopupCard: PopupCard is built on xdg-popup, which
  // only receives keys after a click or hover routes focus through its
  // parent surface, so it never reliably closes on Escape. KeyboardPanel
  // does the extra work (a brief Wayland Exclusive→OnDemand keyboard-focus
  // prime on a real layer-shell surface) that every first-party widget
  // needing real keyboard interaction (Agents, Audio, Bluetooth, Network,
  // Power, ...) relies on for this.
  KeyboardPanel {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popoverOpen
    focusTarget: keyCatcher
    contentWidth: popup.fittedContentWidth(Style.space(340))
    contentHeight: popup.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) {
        if (root.bar && typeof root.bar.switchPanelFrom === "function")
          root.bar.switchPanelFrom(root, direction)
      }

      Column {
        id: column
        anchors.fill: parent

        Timer {
          // Drives the interpolated progress display while the popover is open.
          interval: 500
          repeat: true
          running: root.popoverOpen && root.hasMedia
          onTriggered: progress.tick++
        }
        spacing: Style.space(12)

        // ---------- Now playing ----------
        // Wrapped in a plain Item (not a positioner) so the tap-to-open
        // MouseArea below can overlay the whole row via anchors.fill —
        // anchoring a sibling directly inside the Row itself would conflict
        // with Row's own child-positioning logic.
        Item {
          visible: root.hasMedia
          width: parent.width
          height: nowPlayingColumn.implicitHeight

          Column {
            id: nowPlayingColumn
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: Style.space(10)

          BorderSurface {
            width: parent.width
            height: width
            radius: Style.spacing.labelGap
            color: Style.normalFillFor(root.bar.foreground, Color.accent)
            borderSpec: Border.controlSpec("normal", root.bar.foreground, Color.accent)

            Image {
              id: localArtImage
              anchors.fill: parent
              // Leave a slightly wider reveal of the framed surface around
              // the artwork, keeping the border crisp without making it
              // visually heavy.
              anchors.margins: Style.space(5)
              fillMode: Image.PreserveAspectCrop
              asynchronous: true
              // Chromium's small local thumbnail gives us the fast first
              // paint while the larger catalog version downloads.
              sourceSize.width: 768
              sourceSize.height: 768
              // Keep the decoded cover while the popup is closed. The source
              // only changes with the track, so Qt can show the same artwork
              // immediately on reopen instead of briefly exposing the dark
              // placeholder while it decodes/downloads the 2000 px image.
              cache: true
              source: root.service ? (root.service.artUrl || "") : ""
              // Shown only once there is a decoded image to show, so a file
              // that turns out not to be one leaves the glyph below in place
              // rather than an empty frame.
              visible: source !== "" && status === Image.Ready
                && root.service && !root.service.trackChanging
            }

            Image {
              id: catalogArtImage
              anchors.fill: parent
              anchors.margins: Style.space(5)
              fillMode: Image.PreserveAspectCrop
              asynchronous: true
              sourceSize.width: 1200
              sourceSize.height: 1200
              cache: true
              source: root.service ? (root.service.highResArtUrl || "") : ""
              // This layer replaces the quick local thumbnail only after it
              // has decoded successfully, so downloading never causes a
              // blank flash.
              visible: source !== "" && status === Image.Ready
                && root.service && !root.service.trackChanging
            }

            Text {
              anchors.centerIn: parent
              width: parent.width - Style.space(28)
              visible: !localArtImage.visible && !catalogArtImage.visible
              text: root.service && root.service.artLoading
                ? "Song loading...✌️🥀"
                : "To broke for a cover image✌️🥀"
              textFormat: Text.PlainText
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignVCenter
              wrapMode: Text.Wrap
            }
          }

          // Track title, artist, and album are page-supplied metadata, so
          // each is pinned to PlainText and rendered verbatim rather than
          // left to Text's default markup auto-detection.
          Column {
            spacing: Style.space(4)
            width: parent.width

            Text {
              text: root.title
              textFormat: Text.PlainText
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
              horizontalAlignment: Text.AlignHCenter
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              text: root.artist
              textFormat: Text.PlainText
              color: Qt.darker(root.bar.foreground, 1.3)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              horizontalAlignment: Text.AlignHCenter
              elide: Text.ElideRight
              width: parent.width
              visible: text !== ""
            }

            Text {
              text: root.service && root.service.album ? root.service.album : ""
              textFormat: Text.PlainText
              color: Qt.darker(root.bar.foreground, 1.6)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              horizontalAlignment: Text.AlignHCenter
              elide: Text.ElideRight
              width: parent.width
              visible: text !== ""
            }
          }
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.focusWindowOnly()
          }
        }

        // ---------- Progress ----------
        // Apple Music doesn't always report a track's total duration over
        // MPRIS, even well into active playback (see the length sanity
        // check in Service.qml). There's a real difference between "no
        // total, so no fill ratio or remaining time" and "no metadata at
        // all": elapsed time is always known, so it's shown regardless,
        // just without a bar or a total when there's nothing to measure it
        // against.
        Column {
          id: progress
          visible: root.hasMedia
          width: parent.width
          spacing: Style.space(4)

          property int tick: 0
          // Reading `tick` inside the binding is what makes the 500ms timer
          // above actually invalidate `position` — livePosition() depends on
          // Date.now(), which QML has no way to know changed on its own.
          readonly property real position: { var _ = tick; return root.service ? root.service.livePosition() : 0 }
          readonly property real length: root.service ? root.service.length : 0
          readonly property bool lengthKnown: length > 0

          function fmt(seconds) {
            var s = Math.max(0, Math.floor(seconds))
            var m = Math.floor(s / 60)
            var r = s % 60
            return m + ":" + (r < 10 ? "0" : "") + r
          }

          ProgressMeter {
            visible: root.hasMedia
            width: parent.width
            value: progress.length > 0 ? progress.position / progress.length : 0
            foreground: root.bar.foreground
            rangeKnown: progress.lengthKnown
            interactive: progress.lengthKnown && root.service && root.service.activePlayer
              && root.service.activePlayer.canSeek
            onMoved: function(ratio) {
              if (root.service) root.service.seekTo(ratio * progress.length)
            }
          }

          Row {
            width: parent.width
            Text {
              id: timeLeft
              text: progress.fmt(progress.position)
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }
            Item { width: parent.width - timeLeft.implicitWidth - timeRight.implicitWidth; height: 1 }
            Text {
              id: timeRight
              text: progress.lengthKnown ? progress.fmt(progress.length) : ""
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        // ---------- Transport ----------
        // The play/pause button is deliberately bigger (iconLarge, more
        // padding) than prev/next, so it's taller — and Row only positions
        // children's x, not y, so without help the shorter buttons sit
        // top-aligned against the taller one instead of centered against
        // it. Each button is wrapped in a plain Item pinned to the row's
        // own height so it can anchor its vertical center normally;
        // anchoring the Button directly as a Row child would conflict with
        // Row's own positioning (Qt warns and ignores it).
        Row {
          id: transportRow
          visible: root.hasMedia
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(12)
          height: playButton.implicitHeight

          Item {
            width: prevButton.implicitWidth
            height: parent.height

            Button {
              id: prevButton
              anchors.verticalCenter: parent.verticalCenter
              iconText: "󰒮"
              foreground: root.bar.foreground
              horizontalPadding: Style.space(12)
              verticalPadding: Style.space(8)
              iconSize: Style.font.iconLarge
              hasCursor: root.cursorActive && root.cursorIndex === 0
              onHovered: function(isHovered) {
                if (!isHovered) return
                root.cursorActive = true
                root.cursorIndex = 0
              }
              enabled: root.service && root.service.activePlayer && root.service.activePlayer.canGoPrevious
              opacity: enabled ? 1.0 : 0.4
              onClicked: if (root.service) root.service.runAction("previous")
            }
          }

          Item {
            width: playButton.implicitWidth
            height: parent.height

            Button {
              id: playButton
              anchors.verticalCenter: parent.verticalCenter
              iconText: root.playing ? "󰏤" : "󰐊"
              foreground: root.bar.foreground
              horizontalPadding: Style.space(16)
              verticalPadding: Style.space(10)
              iconSize: Style.font.heading
              hasCursor: root.cursorActive && root.cursorIndex === 1
              onHovered: function(isHovered) {
                if (!isHovered) return
                root.cursorActive = true
                root.cursorIndex = 1
              }
              enabled: root.service && root.service.activePlayer
                && (root.service.activePlayer.canTogglePlaying || root.service.activePlayer.canPlay || root.service.activePlayer.canPause)
              opacity: enabled ? 1.0 : 0.4
              onClicked: if (root.service) root.service.runAction("playPause")
            }
          }

          Item {
            width: nextButton.implicitWidth
            height: parent.height

            Button {
              id: nextButton
              anchors.verticalCenter: parent.verticalCenter
              iconText: "󰒭"
              foreground: root.bar.foreground
              horizontalPadding: Style.space(12)
              verticalPadding: Style.space(8)
              iconSize: Style.font.iconLarge
              hasCursor: root.cursorActive && root.cursorIndex === 2
              onHovered: function(isHovered) {
                if (!isHovered) return
                root.cursorActive = true
                root.cursorIndex = 2
              }
              enabled: root.service && root.service.activePlayer && root.service.activePlayer.canGoNext
              opacity: enabled ? 1.0 : 0.4
              onClicked: if (root.service) root.service.runAction("next")
            }
          }
        }

        // ---------- Empty state ----------
        Column {
          visible: !root.hasMedia
          width: parent.width
          spacing: Style.space(8)
          topPadding: Style.space(10)
          bottomPadding: Style.space(2)

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "󰝚"
            color: Qt.darker(root.bar.foreground, 1.5)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.displayLarge
          }

          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.service && root.service.launching ? "Opening Apple Music…" : "No song playing"
            color: Qt.darker(root.bar.foreground, 1.3)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
          }
        }

        PanelSeparator {
          foreground: root.bar.foreground
        }

        Button {
          width: parent.width
          // Same toggle as right-click on the bar icon (openWindow, not
          // focusWindowOnly). Uses windowVisible rather than
          // windowKnownOpen: the window still "exists" while hidden, so
          // windowKnownOpen alone can't distinguish hidden from shown.
          // Refreshed whenever the popover opens (see onPopoverOpenChanged),
          // so it's accurate at the moment it's seen.
          text: root.service && root.service.windowVisible ? "Hide Apple Music" : "Open Apple Music"
          bordered: true
          hasCursor: root.cursorActive && root.cursorIndex === 3
          onHovered: function(isHovered) {
            if (!isHovered) return
            root.cursorActive = true
            root.cursorIndex = 3
          }
          foreground: root.bar.foreground
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          onClicked: root.openWindow()
        }
      }
    }
  }

  // Thin rounded meter, in the spirit of a TUI progress bar.
  component ProgressMeter: Item {
    id: meter
    property real value: 0
    property color foreground: Color.foreground
    property bool rangeKnown: false
    property bool interactive: false
    signal moved(real ratio)
    property real thickness: Math.max(Style.space(3), Math.round(Style.spacing.controlHeight * 0.12))

    implicitHeight: thickness

    Rectangle {
      anchors.fill: parent
      radius: height / 2
      // A real duration gets the normal subtle rail. If neither MPRIS nor
      // Apple's catalog knows the duration, keep a slightly stronger empty
      // rail visible instead of making the whole control appear/disappear.
      color: meter.foreground
      opacity: meter.rangeKnown ? 0.22 : 0.34
    }

    Rectangle {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      height: parent.height
      radius: height / 2
      width: parent.width * Math.max(0, Math.min(1, meter.value))
      color: meter.foreground

      Behavior on width {
        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
      }
    }

    Rectangle {
      visible: meter.interactive
      x: Math.max(0, Math.min(parent.width - width, parent.width * meter.value - width / 2))
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(10)
      height: width
      radius: width / 2
      color: meter.foreground
      border.color: Color.popups.background
      border.width: Style.space(2)
    }

    MouseArea {
      anchors.fill: parent
      enabled: meter.interactive
      cursorShape: Qt.PointingHandCursor

      function ratioAt(x) {
        return Math.max(0, Math.min(1, x / Math.max(1, meter.width)))
      }

      onPressed: function(mouse) { meter.moved(ratioAt(mouse.x)) }
      onPositionChanged: function(mouse) {
        if (pressed) meter.moved(ratioAt(mouse.x))
      }
    }
  }

  // A small animated equalizer for the bar icon while something is
  // playing. Not real audio analysis (that would mean capturing this
  // specific Chromium process's PipeWire stream continuously any time
  // anything plays, just to animate a ~16px bar icon) — each bar just
  // drifts to a fresh random height on its own timer, staggered per bar so
  // they don't move in lockstep.
  component PlayingVisualizer: Row {
    id: viz
    // Row only positions children along its own width, so sizing it to
    // parent would leave the bars packed against the left edge instead of
    // centered. Sizing it to its own content (the default) and centering
    // that keeps them centered regardless of bar count or width; height is
    // pinned to the parent explicitly since centering needs a height to
    // center against.
    anchors.centerIn: parent
    height: parent.height
    property color foreground: Color.foreground
    readonly property real barWidth: Math.max(1, Style.space(2))
    // Lifts the bars off the very bottom edge of the icon canvas, and
    // shrinks the range they grow into to match — flush-to-the-edge, nearly
    // full-height bars read as much bigger than the idle note glyph, which
    // has its own natural padding.
    readonly property real bottomInset: Math.max(1, Style.space(3))
    readonly property real availableHeight: Math.max(1, viz.height - bottomInset)
    spacing: Math.max(1, Style.space(2))

    Repeater {
      model: 4

      Item {
        id: slot
        required property int index
        width: viz.barWidth
        height: viz.height

        Rectangle {
          id: bar
          anchors.bottom: parent.bottom
          anchors.bottomMargin: viz.bottomInset
          anchors.horizontalCenter: parent.horizontalCenter
          width: parent.width
          radius: width / 2
          color: viz.foreground
          height: viz.availableHeight * 0.25

          Behavior on height {
            NumberAnimation { duration: 240; easing.type: Easing.InOutSine }
          }
        }

        Timer {
          interval: 260 + slot.index * 35
          repeat: true
          running: true
          triggeredOnStart: true
          onTriggered: bar.height = Math.max(1, viz.availableHeight * (0.15 + Math.random() * 0.55))
        }
      }
    }
  }
}
