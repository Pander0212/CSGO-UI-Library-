# Nova UI – Implementation Plan

> The library name lives in exactly one place: `src/Meta.lua` (`Name`, `Folder`, export prefixes).

## 1. File structure

```
src/
  Meta.lua                  -- name / folder / versions (the ONE place to rename the library)
  init.lua                  -- Library singleton: CreateWindow, SetSkin, Loader, Notify, Dialog, ...
  Core/
    Maid.lua  Signal.lua  Util.lua  Tween.lua
    Theme.lua               -- theme registry: Bind / BindGradient / Set (live tween) / presets / export
    Flags.lua               -- flag store + Changed signal
    Registry.lua            -- skin registry
    FS.lua                  -- pcall-wrapped file API with session (memory) fallback
    Config.lua              -- configs, settings.json, autoload, autosave, migration, export/import
    Icons.lua               -- vector icons built from Frames (+ asset-id passthrough)
    Input.lua               -- unified mouse/touch drag, long-press, global keybind dispatch
    Renderer.lua            -- walks the logic tree and asks the active skin to render it
  Components/
    Types.lua               -- per-kind value logic (normalize / serialize / equality)
    Element.lua             -- shared element logic (Flag, Callback, Set/Get, Visible, Disabled, Tooltip, addons)
    Group.lua  Tab.lua  Window.lua
  Skins/
    Base/                   -- complete reference skin + shared primitives, every other skin extends it
      init.lua Prim.lua Theme.lua Window.lua Components.lua Overlays.lua
    Classic/  Modern/  Onetap/  Fatal/  Dashboard/
      init.lua  Theme.lua  Window.lua  Components.lua  Loader.lua
  Mobile/   init.lua FloatingButton.lua QuickToggles.lua
  ESPPreview/ init.lua Rig.lua
  Tabs/     Appearance.lua ConfigTab.lua
build/build.py              -- bundles src -> dist/NovaUI.lua (single loadstring-able file)
example.lua  README.md
tools/preview/              -- Roblox API mock + HTML renderer used to produce screenshots/tests
```

## 2. Skin interface

```lua
Skin = {
  Name = "Classic", Description = "...",
  Theme   = { Defaults = {...}, Presets = { Default = {...}, ... } },
  Style   = { ... structural switches used by shared renderers ... },
  Window  = function(ctx, window) -> WindowView,       -- layout, tab system, pages
  Group   = function(ctx, group, column) -> GroupView,
  Components = { Toggle, Slider, Dropdown, Textbox, Keybind, ColorPicker, Button, Label,
                 Paragraph, Divider, ESPPreview, InlineColorPicker, InlineKeybind },
  DropdownList, ColorPanel, Popout, ContextMenu,       -- floating panels
  Notification, Dialog, Tooltip, Watermark, KeybindList,
  FloatingButton, QuickToggle,
  Loader  = function(ctx, opts, handle) -> LoaderView,
}
```
Skins are created with `Base.Extend{...}` – anything not overridden falls back to Base,
so a new skin can start with just a `Theme` and grow from there.

## 3. Public API (short)

```lua
local UI  = loadstring(game:HttpGet(".../dist/NovaUI.lua"))()
UI:Loader{ Skin = "Classic", Products = {...} }          -- yields until "Load" finished
local Win = UI:CreateWindow{ Skin = "Classic", Title = "Nova", ToggleKey = Enum.KeyCode.RightShift }
local Tab = Win:AddTab{ Name = "Aimbot", Icon = "crosshair", Category = "Combat" }
local G   = Tab:AddGroup{ Name = "General", Side = "Left" }
G:AddToggle{ Name, Flag, Default, Callback, Tooltip, Pinnable }:AddColorPicker{...}:AddKeybind{...}
G:AddSlider / AddDropdown / AddTextbox / AddKeybind / AddColorPicker / AddButton / AddLabel / AddParagraph / AddDivider / AddESPPreview
Win:AddThemeTab()  Win:AddConfigTab()
UI:SetSkin("Modern")  UI:Notify{...}  UI:Dialog{...}  UI:GetESPSettings()  UI:Destroy()
UI.Config:Save/Load/Delete/Rename/Duplicate/List/SetAutoload/Export/Import
UI.Theme:Set(key, value)  UI.Theme:Bind(inst, prop, key)
```

## 4. Theme keys
Grouped in sections (Colors, Gradients, Background, Fonts, Layout, Animation, Branding,
Notifications, Sounds, Mobile). Every color key `X` also has an `Alpha.X` transparency key.
Full list in README.md.

## 5. Config format (version 2)

```json
{
  "version": 2, "library": "Nova UI", "name": "legit", "saved": 1731500000,
  "skin": "Classic",
  "theme": { "skin": "Classic", "overrides": { "*": {...}, "Classic": { "Accent": "#9acd32" } } },
  "flags": { "aim_enabled": true, "aim_color": { "Color": "#ff0000", "Transparency": 0, "Rainbow": false } },
  "window": { "x": 200, "y": 120, "w": 660, "h": 560, "tab": "Aimbot", "sub": "Main" },
  "mobile": { "mode": "Auto", "button": { "x": 20, "y": 200 }, "pins": { "aim_enabled": { "x": 40, "y": 300, "size": "M", "alpha": 0 } } }
}
```
Folders: `NovaUI/<PlaceId>/configs/*.json`, `NovaUI/themes/*.json`, `NovaUI/settings.json`.
