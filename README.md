# Apple Music for Omarchy

Apple Music in the Omarchy bar, backed by a dedicated Chromium window and a
native, theme-aware now-playing panel.

![Apple Music now-playing panel](preview.png)

## About this version

This project is a modification and continuation of Nick Pestov's excellent
[`nickpestov/omarchy-am`](https://github.com/nickpestov/omarchy-am). The
original project established the Chromium window lifecycle, MPRIS integration,
bar widget, and clean profile removal used here.

This version keeps that foundation and expands it with:

- A larger, keyboard-navigable native player panel.
- More robust track-change handling and progress reporting.
- A two-stage cover pipeline: Chromium's local MPRIS image appears quickly,
  then a higher-resolution match is queried from Apple's public iTunes Search
  and Lookup APIs.
- Album, artist, title, duration, and collection-aware matching with guarded
  fallbacks and small in-memory caches.
- Better coordination with Omarchy's bar popout navigation.

Thanks to Nick Pestov for the original implementation and its clear MIT
licensing. See [Credits](#credits) and [LICENSE](LICENSE).

## Features

- Left-click opens a native now-playing panel with artwork, metadata, progress,
  and previous/play-pause/next controls.
- Right-click opens or hides the real `music.apple.com` Chromium window.
- Clicking the artwork or title always brings the player window into view.
- Scrolling the bar icon changes track.
- The music-note icon becomes a small equalizer during playback.
- The browser profile is separate from your normal Chromium profile.

## Requirements

- Omarchy 4 (Quattro) or newer
- `omarchy-shell` running on Hyprland
- `chromium`, `python3`, `curl`, and `jq` on `PATH`
- Chromium's Widevine CDM for protected playback

## Install

```sh
omarchy plugin add https://github.com/leandro-3rne/omarchy-apple-music.git --enable
```

The widget is placed on the right side of the bar by default. Move it with:

```sh
omarchy bar move io.github.leandro-3rne.apple-music --section right
```

Open the Apple Music window and sign in there. Credentials and cookies remain
inside the plugin's dedicated local Chromium profile; they are never part of
this repository.

## Usage

- Left-click: open or close the now-playing panel.
- Right-click: open the Apple Music window, or hide it when it is visible.
- Scroll: previous or next track.
- Arrow keys: move through panel controls.
- Enter/Space: activate the selected control.
- Escape: close the panel.

## IPC

```sh
omarchy-shell io.github.leandro-3rne.apple-music status
omarchy-shell io.github.leandro-3rne.apple-music open
omarchy-shell io.github.leandro-3rne.apple-music show
omarchy-shell io.github.leandro-3rne.apple-music playPause
omarchy-shell io.github.leandro-3rne.apple-music next
omarchy-shell io.github.leandro-3rne.apple-music previous
omarchy-shell io.github.leandro-3rne.apple-music refresh
```

## Privacy and network access

Playback metadata is read through Chromium's MPRIS interface. For improved
artwork and duration metadata, the plugin sends the current artist, title, and
album as search terms to Apple's public iTunes Search/Lookup endpoints. Cover
images are then fetched from Apple's artwork CDN. No Apple account credential,
cookie, browser profile, or local file is sent by the plugin.

The current MPRIS thumbnail is copied into a user-only runtime directory before
QML loads it. The copy is replaced on track changes and disappears with the
user session.

## Remove

```sh
omarchy plugin remove io.github.leandro-3rne.apple-music
```

Removal closes the dedicated Chromium window and deletes its isolated profile,
including its cache, cookies, and Apple Music sign-in. Disabling the plugin only
closes the window and preserves the profile for later use.

The profile is stored under:

```text
${XDG_DATA_HOME:-$HOME/.local/share}/leandro-3rne-apple-music
```

## Credits

- Original project: [Nick Pestov — omarchy-am](https://github.com/nickpestov/omarchy-am)
- Modification and extended artwork lookup: [leandro-3rne](https://github.com/leandro-3rne)
- Apple Music is a trademark of Apple Inc. This community project is not
  affiliated with or endorsed by Apple.

## License

MIT — see [LICENSE](LICENSE). The original copyright notice is retained.
