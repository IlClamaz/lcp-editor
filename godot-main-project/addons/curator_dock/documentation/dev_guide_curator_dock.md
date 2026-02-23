# Curator Dock 1.0 — Developer Guide (Godot 4.x) - 23.02.2026

This document describes the **Curator Dock** plugin architecture, responsibilities, data flow, and common pitfalls.  
It is intended for developers maintaining the plugin and/or integrating it with `living_platform_plugin`.

> Assumption: Godot 4.x (tested 4.5.1), plugin loaded under `res://addons/curator_dock/`.

---

## 1) Goals & Scope

The Curator Dock provides editor-side tooling for curators to:

- Instantiate a `LivingEnvironment` scene from an Omeka-backed ID
- Ensure baseline scene setup (player/camera, lights, floor)
- Provide a scene-driven inventory list (snapshot of current scene tree)
- Select nodes from the list to focus gizmos in the 3D viewport
- Toggle node visibility and apply simple positioning / auto-layout operations
- Preserve usability with Undo/Redo where possible

**Important design choice (current)**:
- The inventory is **scene-based** (it reflects the current `LivingEnvironment` tree), not a pure DB inventory.
- Database fetching / instantiation is done by `LivingEnvironment.rebuild_environment()` (and internal LivingItem logic), not by the curator dock.

---

## 2) High-level architecture

### Entry point: `curator_plugin.gd`
- Extends `EditorPlugin`
- Instantiates the dock script and injects:
  - `editor_interface = get_editor_interface()`
  - `undo_redo = get_undo_redo()`
- Adds dock via `add_control_to_dock()`

### Dock orchestrator: `curator_dock.gd`
- Extends `VBoxContainer`
- Owns controllers and wires them to UI and editor hooks.
- Minimal business logic; delegates to controllers.

### UI builder: `curator_dock_ui_builder.gd`
- RefCounted helper that builds UI nodes in code
- Returns a struct-like object `ui` containing all widget references
- Dock interacts via `ui.*` only (encapsulation)

### Controllers
- `CuratorSceneController`:
  - Detects `LivingEnvironment` as the edited scene root
  - Applies global URL to environment
  - Provides helper functions to find/ensure nodes under environment (area/element)
- `CuratorSetupController`:
  - Ensures player/camera, floor, lights (usually instancing scenes)
  - Provides presence checks for sanity display
- `CuratorInventoryController`:
  - Converts a `scan_environment()` snapshot into an `ItemList`
  - Provides metadata per row (instance_id, node_path, visibility, nesting level)
  - Handles UI selection logic (enable/disable buttons etc.)
- `CuratorLayoutController`:
  - Auto-layout helpers (grid)
  - Reset helpers
- `CuratorEditorHooks`:
  - Connects to editor/runtime signals:
	- `node_added/node_removed` (filtered)
	- `undo_redo` version changes
	- `Node.renamed` watchers (for async title updates)
  - Emits `refresh_requested()` which the dock handles

---

## 3) Data model (snapshot → list)

### Snapshot format
Produced by `CuratorDock.scan_environment(env_root)`:

Each row is a `Dictionary`:

- `name: String`
- `visible: bool` (from `is_visible_in_tree()` or Node3D.visible)
- `nesting_level: int` (depth)
- `node_path: String` (relative to env root, optional but useful fallback)
- `instance_id: int` (preferred resolver; stable for selection/toggle)

### ItemList metadata
For each list item, store robust metadata (always dictionary):

```gdscript
{
  "instance_id": int,
  "node_path": String,
  "visible": bool,
  "nesting_level": int
}
```

Resolution strategy:
1. Use `instance_from_id(instance_id)` if possible
2. Fallback to `env.get_node_or_null(node_path)` if still valid

---

## 4) Refresh strategy & avoiding selection loss

### The core problem
- Rebuilding the ItemList (`clear()` + `add_item()`) can invalidate selection and cause UX issues.
- Scene modifications can happen frequently:
  - `node_added/node_removed` (instantiation and deletion)
  - `renamed` (titles arriving async after fetch)
  - `undo/redo` on properties (visibility toggles) with no node add/remove

### Current strategy
- `CuratorEditorHooks` emits `refresh_requested`
- `curator_dock.gd` runs `_do_env_refresh()`, which:
  - scans environment once
  - pushes snapshot into inventory controller
  - renders list
  - binds rename watchers from the same snapshot

---

## 5) Undo/Redo considerations

### Visibility toggle
Visibility toggles are undoable if you register a property change:

```gdscript
undo_redo.create_action("Toggle visibility")
undo_redo.add_do_property(node, "visible", new_vis)
undo_redo.add_undo_property(node, "visible", old_vis)
undo_redo.commit_action()
```

### Reset / “Destroy all”
**Do not use `queue_free()`** if you need Ctrl+Z to restore nodes.  
`queue_free()` is not undoable unless you serialize and recreate nodes.

Preferred Undoable approach:
- `remove_child()` in DO
- `add_child()` + `move_child()` in UNDO
- Optionally restore `owner` if needed

This keeps nodes alive but detached, allowing undo to restore them.

---

## 6) Instantiation flow (template copy)

When pressing **Instantiate environment**:

1. Validate `Environment ID > 0` before doing anything
2. If no `LivingEnvironment` root is open:
   - Load template scene: `res://addons/living_platform_plugin/scenes/living_environment_root.tscn`
   - Instantiate it, pack, save into `res://curated_scenes/` with unique name
   - Open new scene via `editor_interface.open_scene_from_path(new_path)`
   - Continue next frame (`call_deferred`) to ensure the edited scene root is ready
3. Apply global Omeka URL to environment
4. Ensure baseline setup (camera/floor/lights)
5. Set `env.item_id` to desired ID (UndoRedo if available)
6. Call `env.rebuild_environment()`
7. Refresh UI after fetch success:
   - hook `env.fetch_json_success` (ONE_SHOT) and request refresh
   - also rely on rename watchers to update names as titles arrive

---

## 7) Sanity Check

Sanity labels should reflect:
- `setup_ctrl.has_player(env)`
- `setup_ctrl.has_lights(env)`
- `setup_ctrl.has_floor(env)`
- Environment validity (e.g. `env.item_id > 0`)

Buttons:
- Ensure buttons are disabled when the corresponding setup item already exists.


## 8) Folder organization

```
res://addons/curator_dock/
  plugin.cfg
  curator_plugin.gd

  docks/
	curator_dock.gd
	curator_dock_ui_builder.gd

  controllers/
	curator_editor_hooks.gd
	curator_scene_controller.gd
	curator_inventory_controller.gd
	curator_layout_controller.gd
	curator_setup_controller.gd
```

---

## 9) Extensibility notes

### Future: UI in .tscn
When moving UI to `.tscn`:
- Keep `CuratorDockUIBuilder` as a thin loader/binder, or remove it.
- Preserve `ui` reference object pattern (encapsulation stays useful).
