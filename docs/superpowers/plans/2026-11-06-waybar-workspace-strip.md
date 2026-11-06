# Waybar Workspace Strip Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a native `niri/workspace-strip` waybar module that renders embossed numbered workspace tiles carrying the real app icons of each workspace's windows, in the bar centre immediately before the clock.

**Architecture:** A new C++ module in the local waybar fork subscribes to the existing niri IPC event stream, computes a compact signature of (visible workspace, active flag, app list), and rebuilds GTK widgets only when that signature changes. Each tile is a `Gtk::Button` with a horizontal box of an index label plus one `Gtk::Image` per distinct app. Embossing is pure CSS.

**Tech Stack:** C++17, GTK3 (gtkmm 3), glibmm, jsoncpp, meson/ninja, waybar module framework (`AModule`, `EventHandler`), niri IPC.

**Spec:** `docs/superpowers/specs/2026-11-06-waybar-workspace-strip-design.md`

## Global Constraints

- Fork path: `/home/kk/dev/tools/waybar` (upstream `1687ec7` + ampere commits). Build with the existing `build/` meson dir.
- Bar height 32 px; icon size default 16.
- Do not modify `niri/workspaces` behaviour or its CSS.
- No polling: update strictly from IPC events (`dp.emit()` pattern used by `Workspaces`).
- Keep the module silent (empty) when niri IPC is unavailable.
- C++ style follows existing `src/modules/niri/*.cpp` (clang-format, 100 col).

---

### Task 1: Scaffold the module and register it

**Files:**
- Create: `include/modules/niri/workspace_strip.hpp`
- Create: `src/modules/niri/workspace_strip.cpp`
- Modify: `meson.build:362-370`
- Modify: `src/factory.cpp:41-44, 237-245`
- Test: run `meson compile -C build` and `waybar --version`

**Interfaces:**
- Consumes: `waybar::modules::niri::IPC` (`gIPC`), `EventHandler::onEvent`.
- Produces: class `waybar::modules::niri::WorkspaceStrip`, module id `niri/workspace-strip`.

- [ ] **Step 1: Write the header**

```cpp
#pragma once

#include <gtkmm/box.h>
#include <gtkmm/button.h>
#include <json/value.h>

#include <string>
#include <unordered_map>
#include <vector>

#include "AModule.hpp"
#include "bar.hpp"
#include "modules/niri/backend.hpp"

namespace waybar::modules::niri {

class WorkspaceStrip : public AModule, public EventHandler {
 public:
  WorkspaceStrip(const std::string& id, const Bar& bar, const Json::Value& config);
  ~WorkspaceStrip() override;

  void update() override;

 private:
  struct TileData {
    unsigned id{};
    unsigned idx{};
    bool active{};
    std::vector<std::string> app_ids;
  };

  void onEvent(const Json::Value& ev) override;
  void rebuild(const std::vector<TileData>& tiles);
  std::vector<TileData> collect() const;
  static std::string signatureOf(const std::vector<TileData>& tiles);
  std::string resolveIconName(const std::string& app_id);

  const Bar& bar_;
  Gtk::Box box_;
  unsigned icon_size_{16};
  std::string last_signature_;
  std::unordered_map<std::string, std::string> icon_cache_;
};

}  // namespace waybar::modules::niri
```

- [ ] **Step 2: Write a minimal implementation that renders an empty strip**

```cpp
#include "modules/niri/workspace_strip.hpp"

#include <spdlog/spdlog.h>

namespace waybar::modules::niri {

WorkspaceStrip::WorkspaceStrip(const std::string& id, const Bar& bar, const Json::Value& config)
    : AModule(config, "workspace-strip", id, false, false), bar_(bar), box_(bar.orientation, 4) {
  if (config["icon-size"].isUInt()) icon_size_ = config["icon-size"].asUInt();

  box_.set_name("niri-workspace-strip");
  if (!id.empty()) box_.get_style_context()->add_class(id);
  box_.get_style_context()->add_class(MODULE_CLASS);
  event_box_.add(box_);

  if (!gIPC) gIPC = std::make_unique<IPC>();

  for (const auto* ev : {"WorkspacesChanged", "WorkspaceActivated", "WorkspaceActiveWindowChanged",
                         "WindowsChanged", "WindowOpenedOrChanged", "WindowClosed"}) {
    gIPC->registerForIPC(ev, this);
  }
}

WorkspaceStrip::~WorkspaceStrip() { gIPC->unregisterForIPC(this); }

void WorkspaceStrip::onEvent(const Json::Value& /*ev*/) { dp.emit(); }

void WorkspaceStrip::update() {
  auto tiles = collect();
  auto sig = signatureOf(tiles);
  if (sig != last_signature_) {
    last_signature_ = sig;
    rebuild(tiles);
  }
  AModule::update();
}

std::vector<WorkspaceStrip::TileData> WorkspaceStrip::collect() const { return {}; }
std::string WorkspaceStrip::signatureOf(const std::vector<TileData>&) { return "empty"; }
void WorkspaceStrip::rebuild(const std::vector<TileData>&) {}
std::string WorkspaceStrip::resolveIconName(const std::string& app_id) { return app_id; }

}  // namespace waybar::modules::niri
```

- [ ] **Step 3: Register in meson and factory**

`meson.build` (inside the `if get_option('niri')` source list):

```meson
        'src/modules/niri/workspace_strip.cpp',
```

`src/factory.cpp`:

```cpp
#include "modules/niri/workspace_strip.hpp"
...
    if (ref == "niri/workspace-strip") {
      return new waybar::modules::niri::WorkspaceStrip(id, bar_, config_[name]);
    }
```

- [ ] **Step 4: Build**

Run: `cd /home/kk/dev/tools/waybar && meson compile -C build 2>&1 | tail -20`
Expected: exit 0, `build/waybar` relinked.

- [ ] **Step 5: Verify the module is accepted**

Run: `./build/waybar --version` then start it with a throwaway config containing only
`"modules-center": ["niri/workspace-strip"]` and confirm the log has no
`module not found` for it.

- [ ] **Step 6: Commit**

```bash
git add include/modules/niri/workspace_strip.hpp src/modules/niri/workspace_strip.cpp meson.build src/factory.cpp
git commit -m "feat(niri): scaffold workspace-strip module"
```

---

### Task 2: Collect workspaces and apps

**Files:**
- Modify: `src/modules/niri/workspace_strip.cpp`
- Test: manual run against the live session

**Interfaces:**
- Consumes: `gIPC->workspaces()`, `gIPC->windows()`, `gIPC->lockData()`.
- Produces: `collect()` returning only populated ∪ active tiles, each with de-duplicated `app_ids`.

- [ ] **Step 1: Implement collect()**

```cpp
std::vector<WorkspaceStrip::TileData> WorkspaceStrip::collect() const {
  std::vector<TileData> tiles;
  auto lock = gIPC->lockData();

  for (const auto& ws : gIPC->workspaces()) {
    TileData tile;
    tile.id = ws["id"].asUInt();
    tile.idx = ws["idx"].asUInt();
    tile.active = ws["is_active"].asBool();

    for (const auto& win : gIPC->windows()) {
      if (win["workspace_id"].asUInt() != tile.id) continue;
      const auto app = win["app_id"].asString();
      if (app.empty()) continue;
      if (std::find(tile.app_ids.begin(), tile.app_ids.end(), app) == tile.app_ids.end()) {
        tile.app_ids.push_back(app);
      }
    }

    if (!tile.app_ids.empty() || tile.active) tiles.push_back(std::move(tile));
  }

  std::sort(tiles.begin(), tiles.end(),
            [](const TileData& a, const TileData& b) { return a.idx < b.idx; });
  return tiles;
}
```

- [ ] **Step 2: Implement signatureOf()**

```cpp
std::string WorkspaceStrip::signatureOf(const std::vector<TileData>& tiles) {
  std::string sig;
  for (const auto& t : tiles) {
    sig += std::to_string(t.idx);
    sig += t.active ? "+" : "-";
    for (const auto& a : t.app_ids) {
      sig += ",";
      sig += a;
    }
    sig += "|";
  }
  return sig;
}
```

- [ ] **Step 3: Build and run**

Run: `meson compile -C build && WAYLAND_DISPLAY=wayland-1 ./build/waybar -c /tmp/strip-test.json -l debug`
Expected: no crash; debug log shows module construction.

- [ ] **Step 4: Commit**

```bash
git add src/modules/niri/workspace_strip.cpp
git commit -m "feat(niri): collect workspace tiles and app ids"
```

---

### Task 3: Render tiles with real icons

**Files:**
- Modify: `src/modules/niri/workspace_strip.cpp`

**Interfaces:**
- Consumes: `Gtk::IconTheme`, `Gtk::Image`, `Gtk::Label`.
- Produces: `rebuild()` populating `box_`.

- [ ] **Step 1: Implement resolveIconName()**

```cpp
std::string WorkspaceStrip::resolveIconName(const std::string& app_id) {
  auto cached = icon_cache_.find(app_id);
  if (cached != icon_cache_.end()) return cached->second;

  std::string name = app_id;
  if (auto info = Gio::DesktopAppInfo::create(app_id + ".desktop")) {
    if (auto icon = info->get_icon()) {
      if (auto themed = std::dynamic_pointer_cast<Gio::ThemedIcon>(icon)) {
        for (const auto& candidate : themed->get_names()) {
          if (Gtk::IconTheme::get_default()->has_icon(candidate)) {
            name = candidate;
            break;
          }
        }
      }
    }
  }
  if (!Gtk::IconTheme::get_default()->has_icon(name)) name.clear();
  icon_cache_[app_id] = name;
  return name;
}
```

- [ ] **Step 2: Implement rebuild()**

```cpp
void WorkspaceStrip::rebuild(const std::vector<TileData>& tiles) {
  for (auto* child : box_.get_children()) box_.remove(*child);

  for (const auto& tile : tiles) {
    auto* button = Gtk::manage(new Gtk::Button());
    button->set_relief(Gtk::RELIEF_NONE);
    button->get_style_context()->add_class("ws-tile");
    if (tile.active) button->get_style_context()->add_class("active");

    auto* content = Gtk::manage(new Gtk::Box(Gtk::ORIENTATION_HORIZONTAL, 4));
    auto* label = Gtk::manage(new Gtk::Label(std::to_string(tile.idx)));
    label->get_style_context()->add_class("ws-index");
    content->pack_start(*label, false, false, 0);

    for (const auto& app : tile.app_ids) {
      auto name = resolveIconName(app);
      if (name.empty()) continue;
      auto* image = Gtk::manage(new Gtk::Image());
      image->set_from_icon_name(name, Gtk::ICON_SIZE_INVALID);
      image->set_pixel_size(static_cast<int>(icon_size_));
      content->pack_start(*image, false, false, 0);
    }

    button->add(*content);
    const auto idx = tile.idx;
    button->signal_clicked().connect([idx] {
      Glib::spawn_command_line_async("niri msg action focus-workspace " + std::to_string(idx));
    });
    box_.pack_start(*button, false, false, 0);
  }
  box_.show_all();
}
```

- [ ] **Step 3: Build and inspect**

Run: `meson compile -C build && WAYLAND_DISPLAY=wayland-1 ./build/waybar -c /tmp/strip-test.json &` then `grim /tmp/strip.png`
Expected: tiles appear with numbers and app icons for the current windows.

- [ ] **Step 4: Commit**

```bash
git add src/modules/niri/workspace_strip.cpp
git commit -m "feat(niri): render tiles with app icons"
```

---

### Task 4: Wire into the real bar and style it

**Files:**
- Modify: `~/.config/waybar/config` (modules-center)
- Modify: `~/.config/waybar/style.css`
- Modify: `~/.config/niri/config.kdl` (spawn explicit fork path)
- Modify: `~/dev/tools/waybar/build` install path (`~/.local/bin/waybar`)

- [ ] **Step 1: Add the module before the clock**

```json
  "modules-center": [
    "niri/workspace-strip",
    "clock"
  ],
  ...
  "niri/workspace-strip": {
    "icon-size": 16
  },
```

- [ ] **Step 2: Add the emboss CSS**

```css
/* Workspace strip: embossed numbered tiles with real app icons */
#niri-workspace-strip {
  margin: 0 10px;
}

#niri-workspace-strip button.ws-tile {
  all: initial;
  min-height: 24px;
  padding: 0 8px;
  margin: 4px 3px;
  border-radius: 6px;
  background-image: linear-gradient(to bottom, #6d7f96 0%, #47576b 48%, #35424f 52%, #2b3641 100%);
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.55),
              inset 0 -1px 0 rgba(0, 0, 0, 0.55),
              0 1px 2px rgba(0, 0, 0, 0.45);
}

#niri-workspace-strip button.ws-tile.active {
  background-image: linear-gradient(to bottom, #a9c6e8 0%, #6f9cc8 48%, #4f7ba6 52%, #3f6688 100%);
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.75),
              inset 0 -1px 0 rgba(0, 0, 0, 0.45),
              0 0 6px rgba(150, 200, 255, 0.55);
}

#niri-workspace-strip label.ws-index {
  all: initial;
  color: #ffffff;
  font-family: "CaskaydiaMono Nerd Font", monospace;
  font-size: 13px;
  font-weight: bold;
  margin-right: 2px;
}
```

- [ ] **Step 3: Install the fork binary and point niri at it**

```bash
install -Dm755 ~/dev/tools/waybar/build/waybar ~/.local/bin/waybar
```

In `~/.config/niri/config.kdl` replace `spawn-at-startup "waybar"` with the absolute fork path so the stock `/usr/bin/waybar` is never picked up:

```kdl
spawn-at-startup "/home/kk/.local/bin/waybar"
```

- [ ] **Step 4: Restart the bar and verify visually**

```bash
pkill -x waybar; sleep 2
WAYLAND_DISPLAY=wayland-1 setsid /home/kk/.local/bin/waybar >/tmp/waybar_err.log 2>&1 &
sleep 3
grim /tmp/bar.png
```

Expected: strip sits immediately left of the clock; tiles show numbers + icons; active tile brighter.

- [ ] **Step 5: Commit (fork repo)**

```bash
git add -A && git commit -m "feat: workspace strip wiring + styling" 
```

---

### Task 5: Repo pipeline (dotfiles)

**Files:**
- Create: `patches/waybar-workspace-strip.patch`
- Modify: `install.sh`
- Modify: `README.md`
- Create: `config/waybar/*` copies of the live files

- [ ] **Step 1: Generate the patch**

```bash
cd ~/dev/tools/waybar
git diff 1687ec7..HEAD > /home/kk/dotfiles-repo/patches/waybar-workspace-strip.patch
```

- [ ] **Step 2: install.sh builds waybar from upstream + patch**

```bash
log "2/6 Building waybar (upstream + workspace-strip patch)"
BUILD_ROOT="$(mktemp -d)"; trap 'rm -rf "$BUILD_ROOT"' EXIT
git clone --quiet https://github.com/Alexays/Waybar "$BUILD_ROOT/src"
git -C "$BUILD_ROOT/src" checkout --quiet 1687ec7
git -C "$BUILD_ROOT/src" apply "$REPO_DIR/patches/waybar-workspace-strip.patch"
meson setup "$BUILD_ROOT/src" "$BUILD_ROOT/build" -Dtests=disabled -Dman-pages=disabled \
  -Dcava=disabled -Dgps=disabled -Dwwan=disabled -Dlogin-proxy=disabled \
  -Dsndio=disabled -Drfkill=disabled
meson compile -C "$BUILD_ROOT/build"
install -Dm755 "$BUILD_ROOT/build/waybar" "$TARGET_HOME/.local/bin/waybar"
```

- [ ] **Step 3: Document in README**

State that waybar is built locally from a pinned upstream commit plus
`patches/waybar-workspace-strip.patch`, and that the distro package is not used.

- [ ] **Step 4: Commit and push**

```bash
cd /home/kk/dotfiles-repo
git add -A
git commit -m "waybar: build from upstream + workspace-strip patch"
GIT_SSH_COMMAND="ssh -i /home/kk/.ssh/id_ed25519 -o IdentitiesOnly=yes" git push origin main
```

---

### Task 6: Verification pass

- [ ] **Step 1:** Open windows on workspaces 1–4; confirm tiles appear/disappear and icons match apps.
- [ ] **Step 2:** Click each tile; confirm `niri msg --json workspaces` shows the switch.
- [ ] **Step 3:** Switch workspaces; active tile moves, no flicker.
- [ ] **Step 4:** Kill the IPC socket (`pkill -f niri-ipc` is unsafe — instead restart waybar mid-session) and confirm reconnect.
- [ ] **Step 5:** Pixel-scan `/tmp/bar.png` to confirm the strip's right edge is left of the clock with a gap.
- [ ] **Step 6:** Commit any fixes; report results.
