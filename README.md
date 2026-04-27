# ChuckDAW

Native macOS generative DAW built around [ChucK](https://github.com/ccrma/chuck).

## Current shape

- Native SwiftUI desktop app, not a browser app
- Multi-track generative scene builder with seeds, density, scale, swing, and step grids
- Per-track ChucK voice editing
- Global ChucK prelude and arrangement template editing
- Compiles the project into a single ChucK program
- Starts and stops a real local `chuck` process for playback
- Autosaves state into Application Support

## Build and run

From this folder:

```bash
swift run ChuckDAWApp
```

This opens the macOS app window.

## ChucK engine setup

This machine does not currently have `chuck` installed on the path. The app lets you point at any local `chuck` binary.

To clone and build the official source locally:

```bash
./Scripts/build-chuck.sh
```

After that, use this path in the app:

```text
Vendor/chuck/src/chuck
```

## Reprogramming model

The arrangement template exposes these placeholders:

- `{{GLOBALS}}`
- `{{PRELUDE}}`
- `{{TRACK_FUNCTIONS}}`
- `{{TRACK_SPAWN}}`

That means you can replace the scheduler, routing, helper functions, and per-track synthesis code without leaving the app.

## Notes

- This is a strong native first version: generator, code compiler, and desktop playback bridge are in place.
- It is not yet a full audio recorder, plugin host, or timeline-based editor.
