# Clothesline

[![Built for Omarchy: Plugin](https://raw.githubusercontent.com/tcballard/omarchy-badges/75975e5b5bf75e7ede3764bcd2950046f7abfe2c/badges/v1/omarchy-plugin.svg)](https://github.com/tcballard/omarchy-badges)

Screenshots and recordings hang on a line that drops from the bar. Click to copy, drag to keep or trash.

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
modify those files. The only state it writes is a small
`$XDG_DATA_HOME/clothesline/dismissed.json` listing which paths were unpinned
from the line, so dismissing an item doesn't just bring it right back on the
next scan.

## Security

Omarchy plugins run as unsandboxed code inside `omarchy-shell`. Review this
repository and its dependencies before enabling it.

## License

MIT © 2026 Ayan De
