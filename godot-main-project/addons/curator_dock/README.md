# Curator Dock (Godot Editor Plugin)

This plugin adds a **Curator Dock** to the Godot editor to help “curators” layout **LivingElements** in a 3D scene driven by **Omeka S** data.

It is designed as a **frontend wrapper**: the dock provides UI actions and placement tools; the actual DB communication is performed by existing `LivingScene` / `LivingElement` logic (and/or a future dedicated DB service).

> Target engine: **Godot 4.5.x**
> This plugin is meant to run in-editor (`@tool`).

---

## What problem it solves

Curators need to:

* open a scene that uses a custom root node: **`LivingScene`**
* pick a **root Omeka item id** (the “scene root” item on Omeka)
* fetch that root’s components and see them in a list (“inventory”)
* place components in the 3D scene multiple times (duplicates allowed)
* auto layout placed items in a grid
* reset / clear placed items
* refresh Omeka-driven data from the dock

This plugin adds a dock to the editor with these capabilities.

---

## Core concepts

### `LivingScene` (scene root node)

A custom `Node3D` with an exported Omeka base URL:

* `OMEKA_BASE_URL` (String)

and a tool button / method:

* `refresh_all_living_elements()`

This method recursively scans the scene and, for each `LivingElement`, calls `fetch_omeka_info()`.

### `LivingElement` (Omeka-backed object)

A custom `Node3D` representing an Omeka item:

* `item_id` (int) → Omeka item identifier
* `fetch_omeka_info()` → populates fields from Omeka (title, descriptions, components, media_uri, etc.)
* `instantiate_components()` → creates child `LivingElement` nodes for each ID in `components`
* `download_media()` → downloads media and later visualizes it (image/video/model/etc.)

The dock does not re-implement DB fetching logic; it triggers these methods and orchestrates a pipeline.

---

## UI overview (what the dock shows)

### Global section

* **Omeka URL (default)**
  Stored in editor settings under:

  * `curator/omeka_url_default`

This is a fallback used when a `LivingScene` has an empty `OMEKA_BASE_URL`.

### Current Scene section (requires `LivingScene` root)

* Status label: shows whether a scene is open and whether it is a `LivingScene`
* **Omeka URL (scene)**: shows/edits `LivingScene.OMEKA_BASE_URL`
* **Apply**: writes the URL into the `LivingScene` node (with Undo/Redo if available)

### Root DB section (per-scene root `LivingElement`)

* **Root item_id**: integer field for the Omeka root item
* **Ensure root LivingElement**: creates a root `LivingElement` under the `LivingScene` if missing, and sets its `item_id`.

The root `LivingElement` is the “DB root” for the scene (name default: `LivingRoot`).

### Actions section

* **Refresh list (DB)**
  Updates the dock inventory list from the Omeka root components (details below).
* **Instantiate scene from DB**
  Runs the Omeka pipeline on the **real** root `LivingElement`, creating/updating children in the scene.
* **Reset / clear layout**
  Removes child `LivingElement` nodes under the real root (current behavior: deletes all direct child `LivingElement` nodes of root).
* **Auto layout**
  Places root’s child `LivingElement` nodes in a grid pattern.

### Inventory + placement

* Left: **ItemList** (inventory snapshot)
* Right: Preview (placeholder icon) + grid placement tools:

  * Cell (e.g. `A1`)
  * Spacing
  * Cols (for auto layout)
  * **Place as child of root** button (duplicates allowed)

Double-click on an inventory item also places it.

---

## Inventory list model (IMPORTANT)

### The list is NOT built from the scene

The inventory list is intended to represent **database-driven components**, not what exists in the scene. You can place duplicates; the list should not change when you place items.

Therefore:

* The inventory list **does not automatically update** when:

  * the scene changes
  * nodes are added / removed
  * you place objects
* The inventory list updates **only** when you press **Refresh list (DB)**.

### How Refresh list (DB) works today

In the current architecture, the “components list” is produced by `LivingElement.instantiate_components()` which creates child nodes.

To avoid affecting the scene, Refresh list uses a **temporary root**:

1. Get the current `LivingScene`
2. Call `LivingScene.refresh_all_living_elements()` (refreshes existing `LivingElement` nodes in the scene)
3. Create a temporary `LivingElement` node:

   * name: `InventoryTempRoot`
   * `item_id` = the root item id from the dock
   * `owner = null` (non-persistent)
4. Run the hydration pipeline on `InventoryTempRoot`:

   * fetch root info (`fetch_omeka_info()`)
   * instantiate components (`instantiate_components()`)
   * for each child: fetch + optional media download
5. Read `InventoryTempRoot` children and build `entries[]`
6. Deduplicate entries by `item_id` (one entry per component ID)
7. Render the list
8. Delete the temporary root node

This produces a “DB snapshot list” without permanently altering the scene—provided `instantiate_components()` does not set owners for temp nodes.

### Required micro-patch (to avoid scene pollution)

Because `LivingElement.instantiate_components()` currently sets `owner = edited_scene_root` in editor mode, it can accidentally make children persistent even for temporary roots.

To avoid that, `instantiate_components()` should only set owners if the parent is persistent:

**Patch in `LivingElement.instantiate_components()`**
Change:

```gdscript
if Engine.is_editor_hint():
	new_element.owner = get_tree().edited_scene_root
```

to:

```gdscript
if Engine.is_editor_hint() and self.owner != null:
	new_element.owner = get_tree().edited_scene_root
```

With this patch:

* real root in scene (`owner != null`) behaves normally
* temporary root (`owner == null`) will not create persistent nodes

---

## Placement behavior (duplicates allowed)

When you place an item from the inventory:

* The dock creates a **new `LivingElement` node**
* Sets:

  * `item_id` = selected entry `item_id`
  * `name` = `LivingElement-<item_id>`
  * `position` = grid cell converted to local position (XZ plane)
* Adds it as a **direct child of the real root LivingElement** (`LivingRoot`)
* Sets `owner = edited_scene_root` (so it is visible in the scene tree and saved)
* Then runs the hydration pipeline on the new node:

  * `fetch_omeka_info()`
  * `instantiate_components()`
  * each child: `fetch_omeka_info()` then `download_media()` if needed

Because each placement creates a new node, you can place the same item multiple times.

---

## Hydration pipeline (data + media)

The plugin orchestrates the same pipeline for:

* the root scene instantiation
* placed items
* temporary inventory roots

Pipeline steps:

1. `LivingElement.fetch_omeka_info()`
2. On `fetch_json_success`:

   * `LivingElement.instantiate_components()`
   * for each child `LivingElement`:

	 * `fetch_omeka_info()`
	 * on success: `download_media()` if:

	   * `media_uri` is not empty, and
	   * `media_path` is empty

This ensures:

* metadata is fetched first
* children are spawned from `components`
* media download is done when appropriate

---

## Reset / Clear layout behavior

Current behavior:

* Finds the real root `LivingElement`
* Deletes **all direct child nodes of type `LivingElement`** under that root

This is intentionally “simple” right now.

> If you later want to preserve “canonical DB children” but delete only “placed duplicates”, you’ll need a tagging strategy (e.g., metadata or a separate container). The current design intentionally keeps duplicates directly under root and does not distinguish them.

---

## Auto layout behavior

Auto layout:

* Collects all child nodes of type `LivingElement` under the root
* Sets their local positions in a grid on XZ plane:

```
col = i % cols
row = i / cols
pos = Vector3(col * spacing, 0, row * spacing)
```

* Uses Undo/Redo if available

---

## Module architecture (why the code is split)

The dock was modularized to keep the main UI script manageable.

### `curator_dock.gd`

* Builds UI and connects buttons/signals
* Updates UI enable/disable based on whether a `LivingScene` is open
* Delegates logic to controllers
* Responsible for UI theme usage (icons)

### `controllers/curator_scene_controller.gd`

* Scene detection (`LivingScene`)
* Editor settings (global URL default)
* Ensure root `LivingElement`
* Apply scene URL with Undo/Redo

### `controllers/curator_inventory_controller.gd`

* Owns `entries[]` (inventory snapshot)
* Refresh list logic (temporary root)
* Renders the inventory list in the dock
* Handles selection → preview/help state

### `controllers/curator_layout_controller.gd`

* Grid cell parsing (`A1 → Vector3`)
* Reset root children
* Auto layout

### `controllers/curator_pipeline.gd`

* Hydration pipeline orchestration (fetch → instantiate → child fetch+download)

---

## Undo/Redo support

Whenever possible, operations that change the scene are recorded in Undo/Redo:

* setting `LivingScene.OMEKA_BASE_URL`
* creating the root `LivingElement`
* placing items
* auto layout position changes
* reset operations (when using `queue_free`, it is recorded as “do” operations)

If `undo_redo` is not available, operations are applied directly.

---

## Requirements / assumptions

* The edited scene root should be a `LivingScene` (`class_name LivingScene`)
* `LivingElement` and related classes exist and are available (`class_name LivingElement`)
* `LivingScene.refresh_all_living_elements()` exists
* The “micro-patch” described above is applied to avoid scene pollution from the inventory temp root

---

## Known limitations (current state)

* Inventory thumbnails are placeholders (editor icon).
  Real thumbnails should come from DB/service later.
* Refresh list uses a temporary node and relies on `instantiate_components()` logic.
  A future “DB service” should return inventory data without instantiating nodes.
* Reset deletes all direct `LivingElement` children.
  No distinction between “canonical” and “placed duplicates” is implemented by design.
* No drag-and-drop from list to viewport yet (only click + grid placement).
* Grid supports A–Z columns only (A1..Z999…).

---

## Future improvements (recommended)

* Replace temporary-root inventory with a real data service:

  * `LivingDBService.request_inventory(base_url, root_id)` → returns array of `{item_id, title, thumb, resource_class}`
* Implement drag & drop placement in the 3D viewport
* Add “place at cursor” / “place at raycast hit”
* Add per-type filtering / search in inventory
* Add persistent “scene metadata” storage (root_id + omeka_url) if needed beyond node exports

---

## Troubleshooting

### “Dock not visible”

Make sure the plugin:

* is enabled in **Project Settings → Plugins**
* adds the dock via `add_control_to_dock(...)` (your `curator_plugin.gd`)

### “Refresh list pollutes my scene”

Apply the `instantiate_components()` patch described above (`self.owner != null` check).

### “I can’t place items”

The Place button is disabled if:

* no `LivingScene` is open
* no item is selected in the list

### “Omeka URL is empty”

* Set the global default URL
* Or set scene URL and press **Apply**
* Ensure root uses the updated URL (LivingElements read base URL from LivingScene)

---

If you want, I can also generate a short **developer documentation** section explaining the exact responsibilities of each controller and the expected public methods (like a mini API reference).
