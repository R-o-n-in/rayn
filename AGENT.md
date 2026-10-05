# AGENT.md - AI Agent & Developer Architecture Guide

This document is specifically written for AI coding assistants (agents) and developers who maintain, refactor, or extend the **rayn** codebase.

---

## 🎯 Project Mission & Context

`rayn` was created as a high-performance, standalone desktop shell widget to replace QML/Quickshell/AGS setups in minimal Linux Wayland environments (specifically **Niri**).

Key philosophies:
1. **Low Footprint**: No heavy JavaScript/QML runtimes. Clean compiled Nim + C binary.
2. **Tactile Aesthetics**: Custom physically modeled springs/lerps, procedural micro-grain textures, soft multi-layered drop shadows, and dark matte materials.
3. **Wayland-First**: Complete native integration with Wayland surface input regions and compositor protocols.

---

## 🏗️ Core Architecture & File Structure

```
rayn/
├── src/
│   ├── main.nim       # Main application loop, UI render, event handling, desktop app scanning
│   └── wl_region.c    # C helper interacting with GLFW's Wayland compositor to set surface input regions
├── rayn.nimble        # Nim package specification
├── README.md          # End-user documentation
└── AGENT.md           # Agent context and technical rules (this file)
```

---

## ⚠️ Critical Implementation Rules for Agents

### 1. Process Spawning
- **NEVER** use `osproc.execCmdEx`, `osproc.execCmd`, or standard synchronous system calls inside the main render loop. They create synchronous pipes and block Raylib's event and render loop, freezing the entire Wayland UI.
- **NEVER** use `posix.fork()` inside a multithreaded Raylib / GLFW Wayland process. Forking inside a process holding active Wayland sockets and OpenGL contexts causes deadlocks in child/parent processes.
- **ALWAYS** use `g_spawn_command_line_async` (from `libglib-2.0.so.0`) via `launchApp(cmd)`. This performs asynchronous detached spawning on the C level without touching Nim runtime or threading locks.

### 2. Window Bounds & Wayland Input Region
- `rayn` creates a window with fixed dimensions (`640x540`) so that Niri's floating placement rules center it once at the top of the monitor without shifting sideways.
- To prevent the transparent areas of the `640x540` canvas from blocking mouse clicks when the pill is collapsed, `wl_region.c` is called every frame with `setCustomInputRegion(surfacePtr, curX, curY, curWidth, curHeight)`.
- This tells the Wayland compositor to **only** intercept pointer events within the exact drawn pill boundaries. All clicks outside the pill pass directly through to background applications.

### 3. Raylib Keyboard & Exit Handling
- By default, Raylib exits on `KEY_ESCAPE`.
- `setExitKey(KeyboardKey.Null)` is called immediately after `initWindow` so that pressing <kbd>Escape</kbd> only closes the expanded menu/clears search and never terminates `rayn`.

### 4. Icon Resolution & Rasterization
- Desktop files (`.desktop`) are parsed from `/usr/share/applications` and `~/.local/share/applications`.
- Icons are searched in order: Papirus-Dark, Papirus, hicolor, and pixmaps.
- SVG icons are rendered to GPU textures via `rsvg_handle_render_cairo` and `cairo_image_surface_create` into Raylib `Texture2D`.
- If no matching icon exists, `getFallbackIcon` selects an appropriate Nerd Font symbol.

### 5. Terminal Application Launching
- If a `.desktop` file specifies `Terminal=true`, the execution string is automatically prefixed with `foot ` (e.g. `foot btop`).

---

## 🔧 Build & Test Instructions

```bash
# Compilation
/home/ron/.nimble/bin/nim c -d:release -d:wayland --out:src/rayn src/main.nim

# Installation
cp src/rayn ~/.local/bin/rayn

# Restart process
killall -9 rayn 2>/dev/null || true
WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-1} DISPLAY=${DISPLAY:-:0} nohup ~/.local/bin/rayn >/dev/null 2>&1 &
```
