import raylib, std/[times, os, osproc, math, strutils, algorithm, unicode, tables]

# Dynamic FFI bindings for librsvg & libcairo to render Papirus SVGs on the fly
type
  RsvgHandle = pointer
  CairoSurface = pointer
  CairoContext = pointer
  GError = pointer

const CAIRO_FORMAT_ARGB32 = 0

proc rsvg_handle_new_from_file(filename: cstring, error: ptr GError): RsvgHandle {.importc, dynlib: "librsvg-2.so.2".}
proc g_object_unref(`object`: pointer) {.importc, dynlib: "libgobject-2.0.so.0".}
proc cairo_image_surface_create(format: int32, width: int32, height: int32): CairoSurface {.importc, dynlib: "libcairo.so.2".}
proc cairo_create(target: CairoSurface): CairoContext {.importc, dynlib: "libcairo.so.2".}
proc cairo_scale(cr: CairoContext, sx: float64, sy: float64) {.importc, dynlib: "libcairo.so.2".}
proc cairo_surface_flush(surface: CairoSurface) {.importc, dynlib: "libcairo.so.2".}
proc cairo_image_surface_get_data(surface: CairoSurface): ptr uint8 {.importc, dynlib: "libcairo.so.2".}
proc cairo_destroy(cr: CairoContext) {.importc, dynlib: "libcairo.so.2".}
proc cairo_surface_destroy(surface: CairoSurface) {.importc, dynlib: "libcairo.so.2".}
proc rsvg_handle_render_cairo(handle: RsvgHandle, cr: CairoContext): bool {.importc, dynlib: "librsvg-2.so.2".}
proc g_spawn_command_line_async(command_line: cstring, error: ptr GError): bool {.importc, dynlib: "libglib-2.0.so.0".}

{.compile: "wl_region.c".}
proc setCustomInputRegion*(surfPtr: pointer, x, y, w, h: cint) {.importc: "setCustomInputRegion".}

# Render SVG path into a Raylib Texture2D
proc loadSvgTexture(path: string, size: int32): (bool, Texture2D) =
  var err: GError = nil
  let handle = rsvg_handle_new_from_file(path.cstring, addr err)
  if handle == nil:
    return (false, Texture2D())

  let surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, size, size)
  let cr = cairo_create(surface)

  cairo_scale(cr, float64(size) / 48.0, float64(size) / 48.0)
  discard rsvg_handle_render_cairo(handle, cr)
  cairo_surface_flush(surface)

  let data = cairo_image_surface_get_data(surface)
  var img = genImageColor(size, size, Color(r: 0, g: 0, b: 0, a: 0))
  let totalPixels = size * size
  let src = cast[ptr UncheckedArray[uint8]](data)
  let dst = cast[ptr UncheckedArray[uint8]](img.data)
  for i in 0 ..< totalPixels:
    let b = src[i * 4 + 0]
    let g = src[i * 4 + 1]
    let r = src[i * 4 + 2]
    let a = src[i * 4 + 3]
    dst[i * 4 + 0] = r
    dst[i * 4 + 1] = g
    dst[i * 4 + 2] = b
    dst[i * 4 + 3] = a

  let tex = loadTextureFromImage(img)
  cairo_destroy(cr)
  cairo_surface_destroy(surface)
  g_object_unref(handle)
  return (true, tex)

# Formats 24h time without seconds (HH:mm)
proc formatTime(dt: DateTime): string =
  dt.format("HH:mm")

type
  PowerActionKind = enum
    paShutdown,
    paReboot,
    paSuspend,
    paLock,
    paExit

  PowerButton = object
    kind: PowerActionKind
    icon: string
    label: string
    cmd: string

  AppEntry = object
    name: string
    exec: string
    iconName: string
    fallbackIcon: string
    hasTexture: bool
    texture: Texture2D

proc launchApp*(cmd: string) =
  var err: GError = nil
  let fullCmd = "sh -c " & quoteShell(cmd)
  discard g_spawn_command_line_async(fullCmd.cstring, addr err)

proc executePowerAction(btn: PowerButton) =
  case btn.kind
  of paShutdown:
    launchApp("systemctl poweroff")
  of paReboot:
    launchApp("systemctl reboot")
  of paSuspend:
    discard
  of paLock:
    launchApp("swaylock -f -c 121210 || loginctl lock-session")
  of paExit:
    launchApp("niri msg action quit --skip-confirmation")

proc sanitizeExec(cmd: string): string =
  var parts = strutils.splitWhitespace(cmd)
  var res: seq[string] = @[]
  for p in parts:
    if p.startsWith("%"): continue
    res.add(p)
  result = res.join(" ")

# Resolves Papirus icon name to a file path
proc resolvePapirusIconPath(iconName: string): string =
  if iconName == "": return ""
  if iconName.startsWith("/"):
    if fileExists(iconName): return iconName
    return ""

  let base = if iconName.endsWith(".png") or iconName.endsWith(".svg"): iconName[0..^5] else: iconName
  let subdirs = @["apps", "categories", "devices", "places", "actions", "status", "mimetypes"]
  let themes = @[
    "/home/ron/.local/share/icons/Papirus-Dark/48x48",
    "/home/ron/.local/share/icons/Papirus/48x48",
    "/home/ron/.local/share/icons/Papirus-Dark/64x64",
    "/home/ron/.local/share/icons/Papirus/64x64",
    "/home/ron/.local/share/icons/hicolor/48x48/apps",
    "/home/ron/.local/share/icons/hicolor/256x256/apps",
    "/home/ron/.local/share/icons/hicolor/scalable/apps",
    "/usr/share/pixmaps"
  ]

  for t in themes:
    if "Papirus" in t:
      for sub in subdirs:
        let p = t / sub / (base & ".svg")
        if fileExists(p): return p
        let p_png = t / sub / (base & ".png")
        if fileExists(p_png): return p_png
    else:
      let p_svg = t / (base & ".svg")
      if fileExists(p_svg): return p_svg
      let p_png = t / (base & ".png")
      if fileExists(p_png): return p_png
  return ""

# Fallback Nerd Font icon
proc getFallbackIcon(name, exec: string): string =
  let s = (name & " " & exec).toLowerAscii()
  if "brave" in s or "zen" in s or "chromium" in s or "vivaldi" in s or "firefox" in s or "browser" in s:
    return "\uF059F" # Browser 󰖟
  elif "foot" in s or "terminal" in s or "btop" in s or "htop" in s or "cmatrix" in s:
    return "\uF120"  # Terminal 
  elif "bitwig" in s or "reaper" in s or "volume" in s or "audio" in s or "sound" in s or "music" in s:
    return "\uF001"  # Music 
  elif "genoffice" in s or "office" in s or "document" in s or "calc" in s or "thunar" in s or "rename" in s:
    return "\uF03E2" # Office / Document 󰏢
  elif "bluetooth" in s:
    return "\uF00AF" # Bluetooth 󰂯
  elif "settings" in s or "look" in s or "seahorse" in s or "passwords" in s or "piper" in s:
    return "\uF013"  # Settings 
  elif "brightness" in s or "temperature" in s or "cheatsheet" in s or "notifications" in s:
    return "\uF0493" # Cog / Tool 󰒓
  else:
    return "\uF003B" # App grid 󰀻

proc parseDesktopFile(path: string): (bool, AppEntry) =
  var app: AppEntry
  var inDesktopEntry = false
  var isApp = false
  var noDisplay = false
  var isTerminal = false
  try:
    for line in lines(path):
      let t = line.strip()
      if t == "[Desktop Entry]":
        inDesktopEntry = true
        continue
      elif t.startsWith("[") and t.endsWith("]"):
        inDesktopEntry = false
        continue
      if inDesktopEntry:
        if t.startsWith("Type="):
          if t[5..^1].strip() == "Application": isApp = true
        elif t.startsWith("NoDisplay="):
          if t[10..^1].strip().toLowerAscii() == "true": noDisplay = true
        elif t.startsWith("Terminal="):
          if t[9..^1].strip().toLowerAscii() == "true": isTerminal = true
        elif t.startsWith("Name=") and app.name == "":
          app.name = t[5..^1].strip()
        elif t.startsWith("Exec=") and app.exec == "":
          app.exec = sanitizeExec(t[5..^1].strip())
        elif t.startsWith("Icon=") and app.iconName == "":
          app.iconName = t[5..^1].strip()
    if isApp and not noDisplay and app.name != "" and app.exec != "":
      if isTerminal:
        app.exec = "foot " & app.exec
      app.fallbackIcon = getFallbackIcon(app.name, app.exec)
      return (true, app)
  except:
    discard
  return (false, app)

proc loadDesktopApps(): seq[AppEntry] =
  var seen: seq[string] = @[]
  let dirs = @["/home/ron/.local/share/applications", "/usr/share/applications"]
  for d in dirs:
    if not dirExists(d): continue
    for kind, path in walkDir(d):
      if kind == pcFile and path.endsWith(".desktop"):
        let (ok, app) = parseDesktopFile(path)
        if ok and app.name notin seen:
          seen.add(app.name)
          result.add(app)
  result.sort(proc(a, b: AppEntry): int = cmpIgnoreCase(a.name, b.name))

# Calculates normalized roundness parameter for a fixed corner pixel radius
proc getRoundness(rec: Rectangle, radius: float32 = 18.0f32): float32 =
  let minDim = min(rec.width, rec.height)
  if minDim <= 0.001f32:
    return 0.5f32
  min(1.0f32, (radius * 2.0f32) / minDim)

# Draws soft blurred drop shadow
proc drawDropShadow(rec: Rectangle, cornerRadius: float32, layers: int = 4, maxSpread: float32 = 3.5, baseAlpha: uint8 = 22) =
  for i in 1 .. layers:
    let factor = float32(i) / float32(layers)
    let spread = factor * maxSpread
    let alpha = uint8(float32(baseAlpha) * (1.0 - factor * 0.65))
    let shadowRec = Rectangle(
      x: rec.x - spread,
      y: rec.y - spread + (factor * 2.0),
      width: rec.width + (spread * 2.0),
      height: rec.height + (spread * 2.0)
    )
    let r = getRoundness(shadowRec, cornerRadius + spread)
    drawRectangleRounded(shadowRec, r, 16, Color(r: 0, g: 0, b: 0, a: alpha))

proc filterApps(allApps: openArray[AppEntry], query: string): seq[int] =
  let q = query.strip().toLowerAscii()
  for i in 0 ..< allApps.len:
    if q == "" or q in allApps[i].name.toLowerAscii() or q in allApps[i].exec.toLowerAscii():
      result.add(i)

proc main() =
  # Window bounds accommodating both Power Menu (wide) and Apps Menu (tall)
  const
    winWidth: int32 = 640
    winHeight: int32 = 540

  # Pill geometry
  const
    pillCollapsedW: float32 = 118.0
    pillTopH: float32 = 36.0
    powerExpandedW: float32 = 500.0
    powerExpandedH: float32 = 152.0
    appsExpandedW: float32 = 470.0
    appsExpandedH: float32 = 530.0

  setConfigFlags(flags(
    ConfigFlags.WindowUndecorated,
    ConfigFlags.WindowTransparent,
    ConfigFlags.WindowTopmost,
    ConfigFlags.WindowUnfocused
  ))

  initWindow(winWidth, winHeight, "rayn")
  setExitKey(KeyboardKey.Null)
  setTargetFPS(60)

  # Generate procedural micro-grain noise texture for tactile matte roughness
  var noiseImg = genImageWhiteNoise(128, 128, 0.45f32)
  let noiseTexture = loadTextureFromImage(noiseImg)
  setTextureFilter(noiseTexture, TextureFilter.Bilinear)

  # Load desktop applications and their Papirus icons
  var apps = loadDesktopApps()
  const iconPixelSize: int32 = 36
  for i in 0 ..< apps.len:
    let p = resolvePapirusIconPath(apps[i].iconName)
    if p != "":
      if p.endsWith(".svg"):
        let (ok, tex) = loadSvgTexture(p, iconPixelSize)
        if ok:
          apps[i].hasTexture = true
          apps[i].texture = tex
      elif p.endsWith(".png") or p.endsWith(".xpm"):
        try:
          var img = loadImage(p)
          if img.width > 0:
            imageResize(img, iconPixelSize, iconPixelSize)
            apps[i].texture = loadTextureFromImage(img)
            apps[i].hasTexture = true
        except:
          discard

  # Load JetBrainsMono Nerd Font Bold natively at 1:1 pixel sizes
  let fontPath = "/home/ron/.local/share/fonts/JetBrainsMonoNerdFont-Bold.ttf"
  var
    fontClock: Font
    fontPowerIcons: Font
    fontPowerLabels: Font
    fontAppIcons: Font
    fontAppText: Font
    fontSearch: Font
    fontsLoaded = false

  if fileExists(fontPath):
    var clockCps: seq[int32] = @[]
    for c in "0123456789: ": clockCps.add(int32(ord(c)))
    fontClock = loadFont(fontPath, 22, clockCps)
    setTextureFilter(fontClock.texture, TextureFilter.Point)

    var powerIconCps: seq[int32] = @[
      0xF011'i32, 0xF021'i32, 0xF186'i32, 0xF023'i32, 0xF08B'i32,
      0x23FB'i32, 0x21BB'i32, 0x263E'i32, 0x1F512'i32
    ]
    fontPowerIcons = loadFont(fontPath, 44, powerIconCps)
    setTextureFilter(fontPowerIcons.texture, TextureFilter.Bilinear)

    var textCps: seq[int32] = @[]
    for c in 32..126: textCps.add(int32(c))
    for c in 0x0400..0x045F: textCps.add(int32(c))
    textCps.add(@[0xF002'i32, 0xF0349'i32]) # Search icon  / 󰍉

    # Power labels at 19px
    fontPowerLabels = loadFont(fontPath, 19, textCps)
    setTextureFilter(fontPowerLabels.texture, TextureFilter.Point)

    var appIconCps: seq[int32] = @[
      0xF059F'i32, 0xF120'i32, 0xF001'i32, 0xF03E2'i32,
      0xF00AF'i32, 0xF013'i32, 0xF0493'i32, 0xF003B'i32,
      0xF011'i32, 0xF021'i32, 0xF186'i32, 0xF023'i32, 0xF08B'i32
    ]
    fontAppIcons = loadFont(fontPath, 26, appIconCps)
    setTextureFilter(fontAppIcons.texture, TextureFilter.Bilinear)

    # Large 21px font for app names
    fontAppText = loadFont(fontPath, 21, textCps)
    setTextureFilter(fontAppText.texture, TextureFilter.Point)

    # Search bar font at 18px
    fontSearch = loadFont(fontPath, 18, textCps)
    setTextureFilter(fontSearch.texture, TextureFilter.Point)

    fontsLoaded = true

  # Tactile Matte Dark Composite Palette
  let
    matteBg = Color(r: 20, g: 19, b: 18, a: 236)
    matteBgHover = Color(r: 25, g: 24, b: 22, a: 245)
    matteBorder = Color(r: 247, g: 209, b: 171, a: 35)
    timeColor = Color(r: 255, g: 252, b: 248, a: 255)

  let powerButtons = [
    PowerButton(kind: paShutdown, icon: "\uF011", label: "Выкл",    cmd: "poweroff"),
    PowerButton(kind: paReboot,   icon: "\uF021", label: "Рестарт", cmd: "reboot"),
    PowerButton(kind: paLock,     icon: "\uF023", label: "Блок",    cmd: "lock"),
    PowerButton(kind: paExit,     icon: "\uF08B", label: "Выход",   cmd: "exit")
  ]

  var
    isPowerOpen = false
    isAppsOpen = false
    powerProgress: float32 = 0.0
    appsProgress: float32 = 0.0
    hoverClockAnim: float32 = 0.0
    powerBtnHover: array[4, float32] = [0.0f32, 0.0f32, 0.0f32, 0.0f32]
    appScrollY: float32 = 0.0
    targetScrollY: float32 = 0.0
    searchQuery: string = ""
    selectedAppIndex: int = 0
  let surfacePtr = getWindowHandle()

  while not windowShouldClose():
    let rawDt = getFrameTime()
    let dt = min(0.0166f32, rawDt)
    let mousePos = getMousePosition()

    # Dynamic target state & dimensions
    let targetPower = if isPowerOpen: 1.0f32 else: 0.0f32
    let targetApps = if isAppsOpen: 1.0f32 else: 0.0f32

    let powerSpeed = if isPowerOpen: 12.0f32 else: 16.0f32
    let appsSpeed = if isAppsOpen: 12.0f32 else: 16.0f32

    powerProgress += (targetPower - powerProgress) * min(1.0, dt * powerSpeed)
    appsProgress += (targetApps - appsProgress) * min(1.0, dt * appsSpeed)

    let curWidth = pillCollapsedW +
      (powerExpandedW - pillCollapsedW) * powerProgress +
      (appsExpandedW - pillCollapsedW) * appsProgress
    let curHeight = pillTopH +
      (powerExpandedH - pillTopH) * powerProgress +
      (appsExpandedH - pillTopH) * appsProgress
    let curX = floor((float32(winWidth) - curWidth) / 2.0)
    let curY = 4.0f32

    # Dynamic Wayland input mask: clicks outside the pill pass directly to background windows
    setCustomInputRegion(surfacePtr, cint(curX - 4.0), cint(curY - 2.0), cint(curWidth + 8.0), cint(curHeight + 8.0))

    let mainPillRect = Rectangle(x: curX, y: curY, width: curWidth, height: curHeight)
    let clockTopRect = Rectangle(x: curX, y: curY, width: curWidth, height: pillTopH)

    let isClockHovered = checkCollisionPointRec(mousePos, clockTopRect)
    let isInsideMain = checkCollisionPointRec(mousePos, mainPillRect)

    if isClockHovered:
      hoverClockAnim = min(1.0, hoverClockAnim + dt * 10.0)
    else:
      hoverClockAnim = max(0.0, hoverClockAnim - dt * 8.0)

    # Mouse actions on Clock Pill:
    if isClockHovered and isMouseButtonPressed(MouseButton.Left):
      isAppsOpen = not isAppsOpen
      isPowerOpen = false
      if not isAppsOpen: searchQuery = ""

    if isClockHovered and isMouseButtonPressed(MouseButton.Right):
      isPowerOpen = not isPowerOpen
      isAppsOpen = false
      searchQuery = ""

    # Click outside dismisses menu
    if (isPowerOpen or isAppsOpen) and (isMouseButtonPressed(MouseButton.Left) or isMouseButtonPressed(MouseButton.Right)) and not isInsideMain:
      isPowerOpen = false
      isAppsOpen = false
      searchQuery = ""

    # Filter apps by search query
    let filteredIndices = filterApps(apps, searchQuery)
    if selectedAppIndex >= filteredIndices.len:
      selectedAppIndex = max(0, filteredIndices.len - 1)

    # Keyboard input in Apps Menu (Real-time Search & Navigation)
    if appsProgress > 0.4:
      var ch = getCharPressed()
      while ch > 0:
        if ch >= 32:
          searchQuery.add(Rune(ch).toUTF8())
          targetScrollY = 0.0
          selectedAppIndex = 0
        ch = getCharPressed()

      if isKeyPressed(KeyboardKey.Backspace):
        if searchQuery.len > 0:
          var runes = searchQuery.toRunes()
          runes.setLen(runes.len - 1)
          searchQuery = $runes
          targetScrollY = 0.0
          selectedAppIndex = 0

      if isKeyPressed(KeyboardKey.Down):
        if filteredIndices.len > 0:
          selectedAppIndex = min(filteredIndices.len - 1, selectedAppIndex + 1)
          let itemTop = float32(selectedAppIndex) * 58.0f32
          if itemTop + 58.0f32 > targetScrollY + (curHeight - pillTopH - 74.0f32):
            targetScrollY = itemTop + 58.0f32 - (curHeight - pillTopH - 74.0f32)

      if isKeyPressed(KeyboardKey.Up):
        if filteredIndices.len > 0:
          selectedAppIndex = max(0, selectedAppIndex - 1)
          let itemTop = float32(selectedAppIndex) * 58.0f32
          if itemTop < targetScrollY:
            targetScrollY = itemTop

      if isKeyPressed(KeyboardKey.Enter):
        if filteredIndices.len > 0 and selectedAppIndex < filteredIndices.len:
          let appIdx = filteredIndices[selectedAppIndex]
          launchApp(apps[appIdx].exec)
          isAppsOpen = false
          searchQuery = ""

      if isKeyPressed(KeyboardKey.Escape):
        if searchQuery.len > 0:
          searchQuery = ""
          targetScrollY = 0.0
          selectedAppIndex = 0
        else:
          isAppsOpen = false

    # Power buttons hover & click
    var anyPowerHovered = false
    if powerProgress > 0.05:
      let btnRowY = curY + pillTopH + 8.0
      let btnH: float32 = 98.0
      let totalBtns = powerButtons.len
      let btnSpacing: float32 = 8.0
      let totalSpacing = btnSpacing * float32(totalBtns - 1)
      let availableW = curWidth - 24.0
      let btnW = (availableW - totalSpacing) / float32(totalBtns)

      for i in 0 ..< totalBtns:
        let btn = powerButtons[i]
        let hAnim = powerBtnHover[i]
        let btnX = curX + 12.0 + float32(i) * (btnW + btnSpacing)
        let btnRect = Rectangle(x: btnX, y: btnRowY, width: btnW, height: btnH)
        let isBtnHov = checkCollisionPointRec(mousePos, btnRect) and powerProgress > 0.5
        if isBtnHov:
          anyPowerHovered = true
          powerBtnHover[i] = min(1.0, powerBtnHover[i] + dt * 14.0)
          if isMouseButtonPressed(MouseButton.Left):
            executePowerAction(powerButtons[i])
            isPowerOpen = false
        else:
          powerBtnHover[i] = max(0.0, powerBtnHover[i] - dt * 12.0)
    else:
      for i in 0 ..< 4:
        powerBtnHover[i] = 0.0

    # Apps list scrolling
    var anyAppHovered = false
    let appItemH: float32 = 58.0
    let appListTopY = curY + pillTopH + 58.0
    let appListH = curHeight - pillTopH - 66.0
    let maxScroll = max(0.0f32, float32(filteredIndices.len) * appItemH - appListH + 8.0f32)

    if appsProgress > 0.05 and isInsideMain:
      let wheel = getMouseWheelMove()
      if wheel != 0.0f32:
        targetScrollY = clamp(targetScrollY - wheel * 60.0f32, 0.0f32, maxScroll)

    targetScrollY = clamp(targetScrollY, 0.0f32, maxScroll)
    appScrollY += (targetScrollY - appScrollY) * min(1.0, dt * 18.0f32)

    let nowDt = now()
    let timeStr = formatTime(nowDt)

    beginDrawing()
    clearBackground(Color(r: 0, g: 0, b: 0, a: 0))

    # 1. Soft Drop Shadow
    drawDropShadow(mainPillRect, cornerRadius = 18.0f32, layers = 4, maxSpread = 3.5, baseAlpha = 24)

    # 2. Tactile Matte Rough Surface
    let blend = max(hoverClockAnim, max(powerProgress * 0.4, appsProgress * 0.4))
    let curBg = Color(
      r: uint8(float32(matteBg.r) + float32(matteBgHover.r - matteBg.r) * blend),
      g: uint8(float32(matteBg.g) + float32(matteBgHover.g - matteBg.g) * blend),
      b: uint8(float32(matteBg.b) + float32(matteBgHover.b - matteBg.b) * blend),
      a: uint8(float32(matteBg.a) + float32(matteBgHover.a - matteBg.a) * blend)
    )

    let mainRoundness = getRoundness(mainPillRect, 18.0f32)
    drawRectangleRounded(mainPillRect, mainRoundness, 20, curBg)

    # Micro-grain noise texture
    beginScissorMode(int32(curX), int32(curY), int32(curWidth), int32(curHeight))
    let grainColor = Color(r: 255, g: 255, b: 255, a: 8)
    var ty = curY
    while ty < curY + curHeight:
      var tx = curX
      while tx < curX + curWidth:
        drawTexture(noiseTexture, int32(tx), int32(ty), grainColor)
        tx += 128.0
      ty += 128.0
    endScissorMode()

    # Matte delicate border
    drawRectangleRoundedLines(mainPillRect, mainRoundness, 20, 1.0, matteBorder)

    # 3. Clock Text (22px)
    if fontsLoaded:
      let fontSize: float32 = 22.0
      let spacing: float32 = 1.0
      let textSize = measureText(fontClock, timeStr, fontSize, spacing)
      let textX = floor(curX + (curWidth - textSize.x) / 2.0)
      let textY = floor(curY + (pillTopH - textSize.y) / 2.0)
      drawText(fontClock, timeStr, Vector2(x: textX, y: textY), fontSize, spacing, timeColor)
    else:
      let textW = measureText(timeStr, 22)
      drawText(timeStr, int32(floor(curX + (curWidth - float32(textW)) / 2.0)), int32(floor(curY + (pillTopH - 22.0) / 2.0)), 22, RayWhite)

    # 4. Power Menu
    if powerProgress > 0.05:
      let sepY = curY + pillTopH + 1.0
      let sepAlpha = uint8(35.0f32 * powerProgress)
      drawLine(
        int32(curX + 20.0), int32(sepY),
        int32(curX + curWidth - 20.0), int32(sepY),
        Color(r: 247, g: 209, b: 171, a: sepAlpha)
      )

      let btnRowY = curY + pillTopH + 8.0
      let btnH: float32 = 98.0
      let totalBtns = powerButtons.len
      let btnSpacing: float32 = 8.0
      let totalSpacing = btnSpacing * float32(totalBtns - 1)
      let availableW = curWidth - 24.0
      let btnW = (availableW - totalSpacing) / float32(totalBtns)

      for i in 0 ..< totalBtns:
        let btn = powerButtons[i]
        let hAnim = powerBtnHover[i]
        let btnX = curX + 12.0 + float32(i) * (btnW + btnSpacing)
        let btnRect = Rectangle(x: btnX, y: btnRowY, width: btnW, height: btnH)

        let cardBgAlpha = uint8((10.0f32 + 35.0f32 * hAnim) * powerProgress)
        let cardBg = Color(r: 255, g: 255, b: 255, a: cardBgAlpha)
        let cardBorderAlpha = uint8((18.0f32 + 60.0f32 * hAnim) * powerProgress)
        let cardBorder = Color(r: 247, g: 209, b: 171, a: cardBorderAlpha)

        let cardRoundness = getRoundness(btnRect, 14.0f32)
        drawRectangleRounded(btnRect, cardRoundness, 16, cardBg)
        drawRectangleRoundedLines(btnRect, cardRoundness, 16, 0.8, cardBorder)

        if fontsLoaded:
          let iconDim = measureText(fontPowerIcons, btn.icon, 44.0, 0.5)
          let iconX = floor(btnX + (btnW - iconDim.x) / 2.0)
          let iconY = floor(btnRowY + 12.0)
          let iconAlpha = uint8((210.0f32 + 45.0f32 * hAnim) * powerProgress)
          drawText(fontPowerIcons, btn.icon, Vector2(x: iconX, y: iconY), 44.0, 0.5, Color(r: 250, g: 245, b: 240, a: iconAlpha))

          let labelDim = measureText(fontPowerLabels, btn.label, 19.0, 0.5)
          let labelX = floor(btnX + (btnW - labelDim.x) / 2.0)
          let labelY = floor(btnRowY + 66.0)
          let textAlpha = uint8((180.0f32 + 75.0f32 * hAnim) * powerProgress)
          drawText(fontPowerLabels, btn.label, Vector2(x: labelX, y: labelY), 19.0, 0.5, Color(r: 230, g: 225, b: 220, a: textAlpha))

    # 5. Apps Menu with Search Bar and Papirus Icons
    if appsProgress > 0.05:
      let sepY = curY + pillTopH + 1.0
      let sepAlpha = uint8(35.0f32 * appsProgress)
      drawLine(
        int32(curX + 16.0), int32(sepY),
        int32(curX + curWidth - 16.0), int32(sepY),
        Color(r: 247, g: 209, b: 171, a: sepAlpha)
      )

      # Search Bar Pill Input
      let searchBarY = curY + pillTopH + 8.0
      let searchBarH: float32 = 40.0
      let searchBarRect = Rectangle(x: curX + 14.0, y: searchBarY, width: curWidth - 28.0, height: searchBarH)
      let searchBg = Color(r: 255, g: 255, b: 255, a: uint8(14.0f32 * appsProgress))
      let searchBorder = Color(r: 247, g: 209, b: 171, a: uint8(45.0f32 * appsProgress))
      drawRectangleRounded(searchBarRect, 0.5, 16, searchBg)
      drawRectangleRoundedLines(searchBarRect, 0.5, 16, 0.8, searchBorder)

      if fontsLoaded:
        # Search icon 
        let searchIcon = "\uF002"
        drawText(fontSearch, searchIcon, Vector2(x: searchBarRect.x + 14.0, y: searchBarRect.y + 11.0), 18.0, 0.5, Color(r: 247, g: 209, b: 171, a: uint8(180.0f32 * appsProgress)))

        # Search Query or Placeholder
        if searchQuery == "":
          let placeholder = "Поиск приложений..."
          drawText(fontSearch, placeholder, Vector2(x: searchBarRect.x + 40.0, y: searchBarRect.y + 11.0), 18.0, 0.5, Color(r: 160, g: 155, b: 150, a: uint8(140.0f32 * appsProgress)))
        else:
          drawText(fontSearch, searchQuery, Vector2(x: searchBarRect.x + 40.0, y: searchBarRect.y + 11.0), 18.0, 0.5, Color(r: 255, g: 252, b: 248, a: uint8(240.0f32 * appsProgress)))

      # Scissor list of applications
      let listClipX = int32(curX + 8.0)
      let listClipY = int32(appListTopY)
      let listClipW = int32(curWidth - 16.0)
      let listClipH = int32(appListH)

      if listClipH > 2:
        beginScissorMode(listClipX, listClipY, listClipW, listClipH)

        if filteredIndices.len == 0:
          if fontsLoaded:
            let emptyMsg = "Ничего не найдено"
            let msgDim = measureText(fontAppText, emptyMsg, 18.0, 0.5)
            let msgX = curX + (curWidth - msgDim.x) / 2.0
            let msgY = appListTopY + 40.0
            drawText(fontAppText, emptyMsg, Vector2(x: msgX, y: msgY), 18.0, 0.5, Color(r: 180, g: 175, b: 170, a: uint8(160.0f32 * appsProgress)))
        else:
          for k in 0 ..< filteredIndices.len:
            let i = filteredIndices[k]
            let itemY = appListTopY + float32(k) * appItemH - appScrollY
            if itemY + appItemH < appListTopY - 10.0 or itemY > appListTopY + appListH + 10.0:
              continue

            let itemRect = Rectangle(x: curX + 12.0, y: itemY, width: curWidth - 28.0, height: appItemH - 4.0)
            let isHov = (checkCollisionPointRec(mousePos, itemRect) and appsProgress > 0.5 and mousePos.y >= float32(listClipY) and mousePos.y <= float32(listClipY + listClipH)) or (k == selectedAppIndex and searchQuery != "")

            if isHov:
              anyAppHovered = true
              let hovBg = Color(r: 255, g: 255, b: 255, a: uint8(32.0f32 * appsProgress))
              let hovBorder = Color(r: 247, g: 209, b: 171, a: uint8(60.0f32 * appsProgress))
              drawRectangleRounded(itemRect, 0.28, 12, hovBg)
              drawRectangleRoundedLines(itemRect, 0.28, 12, 0.8, hovBorder)
              if isMouseButtonPressed(MouseButton.Left):
                launchApp(apps[i].exec)
                isAppsOpen = false
                searchQuery = ""
            else:
              let idleBg = Color(r: 255, g: 255, b: 255, a: uint8(8.0f32 * appsProgress))
              drawRectangleRounded(itemRect, 0.28, 12, idleBg)

            # Draw Papirus Icon or Fallback
            let iconX = itemRect.x + 10.0
            let iconY = floor(itemRect.y + (itemRect.height - 36.0) / 2.0)
            if apps[i].hasTexture:
              let iconAlpha = uint8((if isHov: 255.0f32 else: 230.0f32) * appsProgress)
              drawTexture(apps[i].texture, int32(iconX), int32(iconY), Color(r: 255, g: 255, b: 255, a: iconAlpha))
            elif fontsLoaded:
              let iconDim = measureText(fontAppIcons, apps[i].fallbackIcon, 26.0, 0.5)
              let fIconY = floor(itemRect.y + (itemRect.height - iconDim.y) / 2.0)
              let iconAlpha = uint8((if isHov: 255.0f32 else: 210.0f32) * appsProgress)
              drawText(fontAppIcons, apps[i].fallbackIcon, Vector2(x: iconX + 4.0, y: fIconY), 26.0, 0.5, Color(r: 247, g: 209, b: 171, a: iconAlpha))

            # Larger 21px App Name
            if fontsLoaded:
              let nameX = itemRect.x + 54.0
              let nameDim = measureText(fontAppText, apps[i].name, 21.0, 0.5)
              let nameY = floor(itemRect.y + (itemRect.height - nameDim.y) / 2.0)
              let nameAlpha = uint8((if isHov: 255.0f32 else: 220.0f32) * appsProgress)
              drawText(fontAppText, apps[i].name, Vector2(x: nameX, y: nameY), 21.0, 0.5, Color(r: 252, g: 248, b: 244, a: nameAlpha))

        endScissorMode()

        # Slim scrollbar
        if maxScroll > 0.0f32:
          let barX = curX + curWidth - 8.0
          let barTrackH = appListH - 12.0
          let thumbH = max(24.0f32, barTrackH * (appListH / (float32(filteredIndices.len) * appItemH)))
          let thumbY = appListTopY + 6.0 + (appScrollY / maxScroll) * (barTrackH - thumbH)
          let thumbRect = Rectangle(x: barX, y: thumbY, width: 3.0, height: thumbH)
          drawRectangleRounded(thumbRect, 0.5, 8, Color(r: 247, g: 209, b: 171, a: uint8(90.0f32 * appsProgress)))

    endDrawing()

    # Zero-CPU Idle Sleep:
    let isAnimating = (powerProgress > 0.001 and powerProgress < 0.999) or
                      (appsProgress > 0.001 and appsProgress < 0.999) or
                      (hoverClockAnim > 0.001 and hoverClockAnim < 0.999) or
                      (abs(targetScrollY - appScrollY) > 0.5f32)
    let isInteractive = isPowerOpen or isAppsOpen or isClockHovered or anyPowerHovered or anyAppHovered or isAnimating

    if not isInteractive:
      sleep(25)

  closeWindow()

when isMainModule:
  main()
