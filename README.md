# rayn 🌧️

**rayn** is a lightweight, tactile dynamic desktop pill widget, power menu, and application launcher designed for Linux Wayland compositors (such as **Niri**, Hyprland, and Sway).

Built with **Nim**, **Raylib**, and **C**, `rayn` serves as a high-performance alternative to heavy desktop shells (like Quickshell, AGS, or Omarchy default shells) with custom physical spring/lerp animations, procedural matte textures, and full Wayland integration.

---

## ✨ Features

- **Dynamic Island Morphing**:
  - **Collapsed State**: Sleek 24-hour clock pill (`HH:mm`) with subtle border, soft drop shadows, and procedural tactile micro-grain noise texture.
  - **Left-Click (LKM)**: Smoothly morphs into a full-featured, searchable Application Launcher.
  - **Right-Click (PKM)**: Smoothly morphs into a tactile 4-button Power Menu (Shutdown, Reboot, Lock, Exit).
  - **Dismissal**: Clicking outside the widget or pressing <kbd>Escape</kbd> smoothly collapses it back.
- **On-the-Fly Papirus SVG/PNG Icon Rendering**:
  - Automatically discovers desktop `.desktop` entries in `/usr/share/applications` and `~/.local/share/applications`.
  - Dynamically rasterizes Papirus SVGs and PNGs to crisp GPU textures using `librsvg` and `libcairo` via dynamic C FFI.
  - Includes smart Nerd Font glyph fallback for un-themed applications.
- **Fast, Non-Blocking Execution**:
  - Processes are spawned asynchronously via `libglib-2.0` (`g_spawn_command_line_async`), completely isolating child process lifecycle from the render loop.
  - Terminal applications (`Terminal=true`) are automatically launched inside the `foot` terminal emulator.
- **Wayland Input Region Masking**:
  - Uses native Wayland protocols (`wl_compositor_create_region`, `wl_surface_set_input_region`) so that transparent areas surrounding the pill never block mouse clicks to background windows.
- **Zero-CPU Idle Sleep**:
  - Automatically drops into low-frequency idle sleeps when no animations or interactions are occurring.

---

## 🛠️ Architecture & Tech Stack

- **Core Language**: [Nim](https://nim-lang.org/) (2.2+)
- **Graphics & Windowing**: [Raylib](https://www.raylib.com/) via [naylib](https://github.com/planetis-m/naylib) (GLFW with Wayland backend)
- **Vector Graphics**: `librsvg-2.so.2` & `libcairo.so.2` for dynamic vector icon rasterization
- **Process Spawning**: `libglib-2.0.so.0` (`g_spawn_command_line_async`)
- **Compositor Protocols**: `libwayland-client` for surface input region clipping

---

## 📦 Building and Running

### Prerequisites

Ensure the following packages are installed on your system (e.g. Debian/Ubuntu/Arch):
- `nim` (2.0+)
- `libraylib-dev` / `raylib`
- `librsvg2-dev`
- `libcairo2-dev`
- `libglib2.0-dev`
- `libwayland-dev`
- `fonts-jetbrains-mono` or `JetBrainsMono Nerd Font`

### Compiling

```bash
nim c -d:release -d:wayland --out:src/rayn src/main.nim
```

### Running

```bash
WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-1} DISPLAY=${DISPLAY:-:0} ./src/rayn &
```

---

## ⚙️ Niri Configuration (`config.kdl`)

To place `rayn` floating at the top-center without window borders or focus rings in Niri, add:

```kdl
window-rule {
    match title="^(rayn|pill-clock)$"
    open-floating true
    default-floating-position x=0 y=4 relative-to="top"
    focus-ring { off; }
    border { off; }
    draw-border-with-background false
    geometry-corner-radius 0
    clip-to-geometry false
    opacity 1.0
    shadow { off; }
}
```

---

## 📄 License

MIT License. See [LICENSE](LICENSE) for details.
