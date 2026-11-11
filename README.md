# Clothesline

[![Built for Omarchy: Plugin](https://raw.githubusercontent.com/tcballard/omarchy-badges/75975e5b5bf75e7ede3764bcd2950046f7abfe2c/badges/v1/omarchy-plugin.svg)](https://github.com/tcballard/omarchy-badges)

Screenshots, recordings and what you copy hang on a line that drops from the bar. Click to copy.

The line is strung across the top of the screen, right under the bar. Rest the
pointer just under the middle of the bar and it drops down; move away and it
tucks back up. Clicking the bar widget holds it down until you click elsewhere.
On the line: click an item to copy it, double-click to open it, right-click for
Annotate / Reveal in files / Delete, and the × takes it off the line.

What you copy hangs there too, read from Omarchy's own clipboard history: text
as a note (its first line the title), a lone web address as a link, and copied
images like any screenshot. Click one to copy it back; double-click opens a
link in the browser or a note in the editor; right-click → Delete from history
removes it from the clipboard history as well. Copies a password manager marks
as secret never reach the history, so they never hang.

### Replace the clipboard manager hotkey

Plugins can't bind keys, so to have <kbd>Super</kbd> + <kbd>Ctrl</kbd> + <kbd>V</kbd>
drop the line instead of opening Omarchy's clipboard panel, add this to
`~/.config/hypr/bindings.lua`:

```lua
o.rebind("SUPER + CTRL + V", "Clothesline",
  "omarchy-shell shell toggle io.github.ayandexyz.clothesline '{}'")
```

Omarchy's clipboard plugin keeps recording history in the background either
way; only its panel loses the key.

Kinds: service, bar-widget

## GitHub topics

Pair this badge with `omarchy` and `omarchy-plugin` in your GitHub repository's
About topics. The badge does not set topics automatically. Keep other relevant
topics too. This is a community discovery convention, not marketplace approval.

## Requirements

- Omarchy 4 with Quattro shell-plugin support.
- `wl-clipboard` (for copying an item to the clipboard) and `gio` (for
  trashing an item) — both ship with Omarchy by default.
- `omasnap` for the "Annotate" action on screenshots (also ships by default).

## Installation

```bash
omarchy plugin add https://github.com/ayandexyz/clothesline.git --enable
```

For a local checkout:

```bash
omarchy plugin add "$(pwd)" --enable
```

## Validation and tests

```bash
./tests/run
omarchy plugin validate .
```

## Update

```bash
omarchy plugin update io.github.ayandexyz.clothesline
```

## Removal

```bash
omarchy plugin remove io.github.ayandexyz.clothesline
```

The plugin watches `$XDG_PICTURES_DIR/Screenshots` (or `$OMASNAP_SCREENSHOT_DIR`
/ `$OMARCHY_SCREENSHOT_DIR`) and `$XDG_VIDEOS_DIR` (or
`$OMARCHY_SCREENRECORD_DIR`) — the same directories Omarchy's own capture
commands write to — and lists their contents. It does not move, copy, or
modify those files. It also reads `$XDG_STATE_HOME/omarchy/clipboard-history.json`,
and only writes to it when you choose Delete from history. The only state of
its own is in `$XDG_DATA_HOME/clothesline/`: `dismissed.json` lists what was
taken off the line, so dismissing an item doesn't just bring it right back on
the next scan, and `clipboard-seen.json` records when each copy was first seen,
so copies sit among the captures in the order they came.

## Security

Omarchy plugins run as unsandboxed code inside `omarchy-shell`. Review this
repository and its dependencies before enabling it.

## License

MIT © 2026 Ayan De
