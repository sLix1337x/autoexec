# CS2 Advanced Config

Personal Counter-Strike 2 config by **sLix1337**. Modular autoexec, tuned settings, and a proper null-bind movement system with three switchable modes — no monolithic single-file config, no dead binds.

📖 **[Full documentation](https://slix1337x.github.io/autoexec/)** — install steps, complete key map, movement modes, crosshair/viewmodel presets, troubleshooting.

## Repository structure

```
autoexec/
├── CS2 Advanced Config/     current config — start here
│   ├── autoexec.cfg          settings: mouse, HUD, crosshair, viewmodel, audio, network, performance
│   └── core/
│       ├── load.cfg           load order
│       ├── reg.cfg            verb layer every key binds to
│       ├── keys.cfg           all key binds
│       ├── diag.cfg           exec core/diag — finds a broken layer
│       ├── help.cfg           exec core/help — prints the key map
│       └── modules/           movement, hud, crosshair, viewmodel, weapons
├── old-configs/              earlier configs, kept for reference
└── docs/                     source for the GitHub Pages documentation site
```

## Quick install

1. Copy everything inside `CS2 Advanced Config/` into `...\Counter-Strike Global Offensive\game\csgo\cfg\`.
2. In the CS2 console: `exec autoexec`
3. Confirm the `CONFIGURATION LOADED SUCCESSFULLY` banner prints. If not, run `exec core/diag`.

See the [docs](https://slix1337x.github.io/autoexec/) for the full breakdown.

## Highlights

- **Null-bind movement** — SOCD handled by a proper per-axis state machine, three modes (null / strict / raw) on `KP_4`, master on/off on `KP_5`, one-press-per-input panic reset on `KP_0`.
- **Verb-routed binds** — every key points at a named `+slx_*` verb declared once in `core/reg.cfg`, never at a raw game command directly (mouse buttons excepted).
- **7 crosshair presets** and **8 viewmodel positions**, each on a self-advancing cycle key.
- **Movement-mode HUD feedback** — the HUD accent colour shows which mode is active.
- Prediction disabled for body/head-shot FX, ragdolls, weapon drop and bomb defusal so nothing plays ahead of the server.

## Recommended launch options

```
-threads 9 -noreflex
```
Adjust thread count to your CPU's core count.

## License

MIT — do whatever you want with it.
