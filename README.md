# Godot Living Platform

This is the main project to develop the Godot add-ons supporting all features required to author, synchronize, curate, and explore 3D scenes for the Living Culture Platform (LCP).

The project includes two primary custom add-ons:
* `living_platform_plugin`: The runtime and data engine responsible for Omeka S synchronization, media instantiation, scene graph layout, spatial audio, captions, dynamic events, and player navigation.
* `curator_dock`: The visual editorial console dock integrated into the Godot editor, enabling curators to download, inspect, arrange (Mise-en-scène), test, and upload curated scenes to Nextcloud/WebDAV without editing GDScript code.


## Top level files and project structure

* `README.md` - Project architecture and class documentation (this file).
* `LICENSE` - GNU General Public License v3.0.
* `godot-main-project/` - The main Godot (4.x) project directory containing:
  * `addons/living_platform_plugin/` - Core runtime platform classes, media visualizers, HTTP services, managers, captions, and player controllers.
  * `addons/curator_dock/` - Editor plugin dock providing the Curator UI, tree inventory, mise-en-scène controls, and remote scene management.
  * `addons/ffmpeg/` - Multiplatform GDExtension (Windows, Linux, macOS, Android) for native video playback (supporting H.264/MP4).
  * `addons/godot-xr-tools/` & `addons/godotopenxrvendors/` - OpenXR integration, vendor loaders, and VR locomotion/interaction tools.
  * `curated_scenes/` - Local storage directory for downloaded and edited `.tscn` scene files.
  * `downloaded_living_media/` - Local cache for downloaded media assets (models, textures, videos, audios) and associated JSON metadata.
  * `project.godot` - Project configuration file with autoload singletons, mobile rendering, and plugin registrations.


## Key assumptions and authoring conventions

The goal of the Living Platform is to quickly and easily create 3D virtual visits that remain synchronized with the Omeka S semantic database. Several assumptions simplify interactions and media authoring:

* **Floor and locomotion**: Locomotion occurs over a walkable horizontal plane with simulated gravity. Slopes and multi-level vertical paths are currently not modeled.
* **Lighting**: Lighting is managed via a dedicated modular setup (`LivingLights`), ensuring consistent ambient and directional illumination across environments. The Curator Dock automatically ensures this node is present.
* **3D models (GLB/GLTF)**: 3D assets are imported in GLB format.
* **Procedural media colliders and curvature**:
  * For flat media (`LivingImage`, `LivingVideo`, `LivingSlideShow`), `"Face"` and `"Trigger"` collision boundaries are generated programmatically to fit the media dimensions.
  * Flat media support cylindrical curvature (both concave and convex) and automatic diagonal scaling.
* **Video formats**: Videos are handled through the FFmpeg GDExtension, supporting standard `.mp4` video streams as well as `.ogv` formats.
* **Visit points**: Visitable objects dynamically generate and maintain a floor-level `LivingVisitPoint` marker in front of their bounding box (+Z direction), serving as the player's teleport target and orientation anchor during guided visits.


## Living platform scenes organization

The plugin provides a prefabricated hierarchy of classes that mirror the participatory data model in Omeka S. 

The platform supports synchronized visualization of items categorized into typed media:
* **Images** (`LivingImageObject` / `LivingImage`)
* **Videos** (`LivingVideoObject` / `LivingVideo`)
* **360° Videos** (`LivingVideo360Object` / `LivingVideo360`)
* **3D Static Models** (`Living3DModelObject` / `Living3DModel`)
* **3D Animated Models** (`Living3DModelAnimatedObject` / `Living3DModelAnimated`)
* **Spatial Audio** (`LivingAudioObject` / `LivingAudio`)
* **Crowds** (`LivingCrowdObject` / `LivingCrowd`)
* **Slideshows** (`LivingSlideShowObject` / `LivingSlideShow`)
* **Container Models** (`LivingContainerModelObject` / `LivingScene`)
* **Stargates** (`LivingStargateObject` / `LivingStargate`)
* **Target / POI Markers** (`LivingTargetObject` / `LivingTarget`)

A typical curated scene hierarchy conforms to the following structure:

```text
LivingEnvironment                    # Root node of the scene (extends LivingItem)
├── Living_Lights                    # Environment lighting container (LivingLights)
├── Living_Camera                    # Player / camera rig (spawns PlayerFPS or PlayerXR)
├── TARGET - EnvironmentName         # Scene-owned visit target for the whole environment
└── LivingArea-101                   # LivingArea: logical area grouping items (extends LivingItem)
    ├── TARGET - AreaName            # Scene-owned visit target for the area (with chalk border)
    ├── LivingImageObject-102        # LivingImageObject (extends LivingFlatMediaObject)
    │   ├── LivingImage              # MeshInstance3D with texture & curvature
    │   └── LivingVisitPoint         # Interactive floor anchor for visits
    ├── LivingVideoObject-103        # LivingVideoObject (extends LivingFlatMediaObject)
    │   ├── LivingVideo              # MeshInstance3D with SubViewport & VideoStreamPlayer
    │   └── LivingVisitPoint
    ├── Living3DModelObject-104      # Living3DModelObject (extends LivingVisitableObject)
    │   ├── Living3DModel            # Node3D loading imported GLB
    │   └── LivingVisitPoint
    ├── Living3DModelAnimatedObject-105 # Living3DModelAnimatedObject (CharacterBody3D agent)
    │   └── Living3DModelAnimated
    ├── LivingAudioObject-106        # LivingAudioObject (extends LivingObject)
    │   └── LivingAudio              # AudioStreamPlayer3D with attenuation
    ├── LivingCrowdObject-107        # LivingCrowdObject (extends LivingObject)
    │   └── LivingCrowd              # Dynamic crowd avatar spawner and navigator
    ├── LivingSlideShowObject-108    # LivingSlideShowObject (extends LivingFlatMediaObject)
    │   ├── LivingSlideShow          # MeshInstance3D with 3D carousel controls
    │   └── LivingVisitPoint
    ├── LivingStargateObject-109     # LivingStargateObject (teleport portal)
    │   └── LivingStargate           # Node3D with visual cone & trigger
    └── LivingContainerModelObject-110 # LivingContainerModelObject
        └── LivingScene              # Node3D extracting & instantiating template ZIP
```


## Core class reference

### LivingItem (extends Node3D)

The foundational class for all entities connected to the Omeka S platform. Parent class of `LivingEnvironment`, `LivingArea`, and `LivingObject`.

**Key Responsibilities**:
* Holds the unique Omeka S item identifier (`item_id: int`).
* Executes the multi-phase synchronization lifecycle:
  * **Phase 0 (Prefetch)**: Gathers the entire environment metadata tree upfront to identify typed children before spawning.
  * **Phase 1 (Download & Cache)**: Fetches remote media files and thumbnails from Nextcloud/WebDAV. Implements fingerprint validation comparing HTTP headers (`ETag`, `Last-Modified`, `Content-Length`) against local JSON cache to prevent redundant downloads.
  * **Phase 2 (Instantiation)**: Recursively creates appropriate typed child nodes (`components` and `areas`) and instantiates media geometries.
* Tracks asynchronous build states through `BuildState` (`IDLE`, `FETCHING`, `SPAWNING_CHILDREN`, `DOWNLOADING`, `READY`, `ERROR`).
* Emits progress signals: `build_state_changed`, `build_finished`, `download_media_success`, `download_media_error`, `download_thumbnail_success`, `download_thumbnail_error`.

**Exported Properties**:
* `item_id: int` - Remote Omeka S item ID.
* Group **OMEKAS**:
  * `title: String` - Item title.
  * `modified: String` - Remote timestamp of last modification.
  * `short_description: String` - Multiline short text (used for the floating HUD).
  * `long_description: String` - Multiline extended description (used for long caption panel).
  * `catalog_description: String` - Additional technical/archaeological catalog notes.
  * `resource_class: int` - Omeka resource class identifier.
  * `components: Array[int]` - List of child item IDs that compose this item.
  * `areas: Array[int]` - List of child area IDs contained within this item.
  * `medium_uri: String` - Remote download URI for the primary media file.
  * `thumbnail_uri: String` - Remote download URI for the square thumbnail.
* Group **REFRESH AND MEDIUM**:
  * `auto_fetch_metadata: bool`, `auto_instantiate_children: bool`, `auto_download_medium: bool`, `auto_instantiate_medium: bool`, `auto_recurse_children: bool`.
  * `media_filename: String`, `media_path: String`, `media_type: String`.
  * `participatory_item_type: String` - Type classification string from Omeka (e.g., `"Immagine"`, `"Oggetto"`, `"Video"`).
  * `thumbnail_path: String` - Local path to the cached thumbnail.
* Inspector actions:
  * `fetch_omeka_info` ("Sincronizza Item da DB")
  * `instantiate_children` ("Instantiate Components and Areas")
  * `instantiate_medium` ("Instantiate Media")


### LivingEnvironment (extends LivingItem)

The root node required for every curated 3D scene in the Living Platform.

**Key Responsibilities**:
* Holds the base endpoint URL for the Omeka S server: `OMEKA_BASE_URL: String` (e.g. `https://omekas.livingculture.it`).
* Manages scene-level synchronization and rebuild via `rebuild_environment()`.
* Handles remote scene I/O: uploading curated scenes (`upload_scene()`), listing remote scenes on Nextcloud (`list_remote_scenes()`), and downloading curated scenes.
* Holds environment-level Omeka event definitions: `omeka_events: Array[LivingEvent]`.
* Stores the ordered sequence of item IDs for guided visits: `visit_path: Array[int]`.
* Automatically ensures an environment-level visit target (`LivingTargetObject`) exists under itself.

**Inspector Actions and Signals**:
* Buttons: `(Re-)build Environment`, `Save/Upload scene to server`, `List scenes in server`.
* Signals: `scene_upload_success`, `scene_upload_error`, `scene_list_success`, `scene_list_error`, `scene_download_success`, `scene_download_error`, `rebuild_completed`, `import_progress`.


### LivingArea (extends LivingItem)

A spatial and logical collection of items within an environment.

**Key Responsibilities**:
* Represents a designated area without enforcing strict rigid boundaries on child movement.
* Optional automated border generation (`automatic_visuals: bool`):
  * Computes the compound 3D bounding box (AABB) of all contained child elements.
  * Dynamically builds a 4-strip rectangular border frame on the floor plane matching the AABB with margin.
  * Generates an `AreaLabel` flat on the floor along the south edge displaying the area name.
  * Configures a `VolumeCollisionBody` on collision layer 3 (`LIVING_3DMODEL_VOLUME_COLLISION_LAYER`) for raycasting.
* Automatically creates a scene-owned `LivingTargetObject` under itself to enable visiting the area as a whole.

**Exported Properties**:
* `automatic_visuals: bool` - Enables automated floor border computation.
* `border_material: Material` - Custom material for border strips and text (defaults to unshaded white).
* `border_tickness_h: float`, `border_thickness_v: float` - Horizontal and vertical border thickness.
* `border_y: float` - Elevation of the border relative to the floor.
* `border_scale: float` - Margin multiplier around child objects (default 1.1).
* `border_name_font_size: float` - Font size of the floor label.


### LivingObject (extends LivingItem)

Base class for all interactive media elements instantiated within an area or environment.

**Key Responsibilities**:
* Sets editor metadata `_edit_group_` to ensure proper selection handling in the 3D viewport.
* Automatically registers with the `RayPickableLivingItems` group (`LivingConstants.RAY_PICKABLE_GROUP_NAME`).
* Implements birth invisibility: when first instantiated from the database, the node receives the metadata `is_born` and sets `visible = false`, preventing newly synced objects from cluttering the viewport until intentionally placed by a curator.


### LivingVisitableObject (extends LivingObject)

Abstract base class for objects that define an interactive viewpoint or visit position. Inherited by flat media (`LivingFlatMediaObject`), 3D models (`Living3DModelObject`), and target markers (`LivingTargetObject`).

**Key Responsibilities**:
* Computes the player's target transform (`get_visit_transform()`) placed just outside the +Z bounding face of the object, oriented to face the object center.
* Maintains a child `LivingVisitPoint` marker pin synced with the object's geometry.
* Provides live in-editor caption preview via `toggle_caption_preview()`.

**Exported Properties**:
* Group **LAYOUT**:
  * `visit_position: Vector3` - Manual position offset from the automatically computed AABB pose.
  * `visit_rotation_degrees: Vector3` - Manual rotation offset applied to the visit orientation.
* Group **BEHAVIOR**:
  * `show_caption: bool` (Inspector alias: `show_text: bool`) - Controls whether `CaptionManager` displays the short HUD and long caption for this object.
  * `show_visit_point: bool` - Controls visibility of the floor marker pin in the 3D viewport.
* Inspector Button: `Preview Text` (`toggle_caption_preview`).


### LivingTargetObject (extends LivingVisitableObject)

A scene-owned visit target representing an Area or Environment during guided navigation.

**Key Responsibilities**:
* Represents a Point of Interest (POI) or area center. Not an item stored in Omeka S directly (`item_id = 0`); links to its parent item via `bound_item_id: int`.
* Automatically synchronizes title and descriptions from its parent `LivingArea` or `LivingEnvironment`.
* Renders a customizable procedural rounded-rectangle or elliptical chalk border on the floor around child geometry.
* Utilizes a dedicated chalk shader (`target_chalk.gdshader`) with hand-drawn stylization.

**Exported Properties**:
* `bound_item_id: int` - Parent area/environment ID.
* `border_visible: bool` - Toggle border rendering.
* `border_color: Color` - Chalk line and text color.
* `border_thickness_h: float`, `border_thickness_v: float` - Horizontal and vertical stroke dimensions.
* `border_corner_radius: float` - Corner rounding radius in meters (higher values form a complete ellipse).
* `border_y: float` - Floor offset.
* `border_text: String`, `border_text_visible: bool`, `border_name_font_size: float` - Floor label settings.
* `chalk_wear: float` (0.0 to 1.0) - Chalk texture wear and stroke dissipation.
* `chalk_alpha: float` (0.0 to 1.0) - Shader opacity multiplier.


---


## Typed LivingObjects and Media classes

### Flat Media: LivingFlatMediaObject

Base class for 2D planar media visualizers (`LivingImageObject`, `LivingVideoObject`, `LivingSlideShowObject`).

**Exported Properties**:
* `diagonal: float` - Authoring scale expressed as the diagonal dimension of the media in meters (replaces direct node scaling).
* `curvature: float` - Cylindrical curvature in degrees (-360° to +360°). Positive values produce a concave screen bending toward the viewer; negative values produce a convex screen.


### 1. Images: LivingImageObject & LivingImage

* **`LivingImageObject`** (extends `LivingFlatMediaObject`):
  * Instantiates a child `LivingImage`.
* **`LivingImage`** (extends `MeshInstance3D`):
  * Loads image textures from cached local files (`res://downloaded_living_media/...`).
  * Generates a segmented plane mesh (32 curve segments) supporting real-time cylindrical curvature.
  * Builds procedural `Face` and `Trigger` collision bodies matching the image aspect ratio and curvature.


### 2. Videos: LivingVideoObject & LivingVideo

* **`LivingVideoObject`** (extends `LivingFlatMediaObject`):
  * `auto_pause_camera_distance: float` - Automatically pauses video playback when the player walks beyond this distance (default 10.0 m).
  * Inspector preview buttons: `Play Video`, `Toggle Pause`, `Stop Video`.
* **`LivingVideo`** (extends `MeshInstance3D`):
  * Built using `living_video.tscn`, comprising a `SubViewport`, a `VideoStreamPlayer`, and 3D playback control widgets.
  * Powered by the FFmpeg GDExtension, providing robust playback of MP4 and OGV video streams.
  * Automatically resizes the viewport texture to match video resolution, applies curvature, and updates raycast colliders.


### 3. 360° Videos: LivingVideo360Object & LivingVideo360

* **`LivingVideo360Object`** (extends `LivingObject`):
  * `sphere_radius: float` - Radius of the surrounding projection sphere (default 500.0 m).
  * Inspector preview buttons: `Play Video`, `Toggle Pause`, `Stop Video`.
* **`LivingVideo360`** (extends `Node3D`):
  * Projects video onto the inside of an inverted `SphereMesh`.
  * Allows immersion inside panoramic 360-degree video recordings.


### 4. 3D Models: Living3DModelObject & Living3DModel

* **`Living3DModelObject`** (extends `LivingVisitableObject`):
  * `face_visible: bool` - Toggles visibility of the internal `"Face"` mesh inside the GLB model.
* **`Living3DModel`** (extends `Node3D`):
  * Loads GLTF/GLB models dynamically from imported resources (`res://`) or directly from disk cache.
  * Searches child nodes for `"Face"` and `"Trigger"` collision shapes to register them with the collision layers used by captions and the player.


### 5. Animated 3D Models: Living3DModelAnimatedObject & Living3DModelAnimated

* **`Living3DModelAnimatedObject`** (extends `LivingObject`):
  * Controls autonomous character behavior in the scene.
  * Properties:
    * `move_speed: float` - Locomotion speed (default 2.0 m/s).
    * `moving: bool` - Enables/disables path movement.
    * `random_poses_playing: bool` - Enables playing random animation clips.
    * `random_spawn: bool` - Randomizes initial spawn position.
    * `extra_pose_chain_chance: float`, `extra_pose_chain_min: int`, `extra_pose_chain_max: int` - Controls chained animation playback.
* **`Living3DModelAnimated`** (extends `CharacterBody3D`):
  * Executes waypoint navigation, animates meshes, and handles idle/locomotion state machines.


### 6. Spatial Audio: LivingAudioObject & LivingAudio

* **`LivingAudioObject`** (extends `LivingObject`):
  * Exposes comprehensive 3D spatial audio parameters:
    * `autoplay: bool`, `loop: bool`.
    * `volume_db: float`, `max_db: float`, `pitch_scale: float`.
    * `unit_size: float`, `max_distance: float`, `attenuation_model`.
    * `attenuation_filter_cutoff_hz: float`, `attenuation_filter_db: float`.
    * `panning_strength: float`, `max_polyphony: int`, `bus: String`.
  * Inspector preview buttons: `Play Audio`, `Stop Audio`.
* **`LivingAudio`** (extends `AudioStreamPlayer3D`):
  * Loads audio files (WAV, OGG, MP3) and applies runtime spatial attenuation.


### 7. Crowds: LivingCrowdObject & LivingCrowd

* **`LivingCrowdObject`** (extends `LivingObject`):
  * `density: int` - Avatar density parameter (range 1 to 40).
* **`LivingCrowd`** (extends `Node3D`):
  * Reads navigation mesh checkpoint positions and spawns animated avatars traversing predefined pathways.


### 8. Slideshows: LivingSlideShowObject & LivingSlideShow

* **`LivingSlideShowObject`** (extends `LivingFlatMediaObject`):
  * Presentation carousel cycling through multiple child image items.
  * Properties:
    * `loop_slides: bool` - Enables continuous looping.
    * `slide_transition_enabled: bool`, `slide_transition_duration: float`, `slide_transition_fade_min_alpha: float` - Cross-fade transition parameters.
    * `auto_hide_source_elements: bool` - Hides original source image items from the scene tree.
    * `controls_offset_y: float` - Vertical offset of 3D next/previous control buttons.
    * `frame_opening_reference_size: Vector2`, `frame_surface_offset: float` - Framing geometry parameters.
* **`LivingSlideShow`** (extends `MeshInstance3D`):
  * Renders active slides with transition animations, handles 3D button interactions, and aligns optional decorative frame models.


### 9. Container Models: LivingContainerModelObject & LivingScene

* **`LivingContainerModelObject`** (extends `LivingObject`):
  * Manages environment-level scene templates distributed as packaged ZIP archives.
* **`LivingScene`** (extends `Node3D`):
  * Unpacks downloaded `.zip` packages on disk to extract full sub-scenes (e.g. `LivingEnvironmentTemplate.tscn`) and instantiates them safely into the scene graph.


### 10. Stargates: LivingStargateObject & LivingStargate

* **`LivingStargateObject`** (extends `LivingObject`):
  * Portals facilitating transitions between different environments or scenes.
  * Properties:
    * `target_environment_id: int` - ID of the destination Omeka environment.
    * `use_scene_path: bool`, `target_scene_path: String` - Direct file path destination override.
    * `stargate_caption_text: String`, `stargate_caption_scale: float`, `stargate_caption_position_y: float` - Floating destination label.
    * `color_active: Color`, `color_inactive: Color`, `color_used: Color` - State-driven illumination colors.
* **`LivingStargate`** (extends `Node3D`):
  * Features a glowing truncated conical visual effect and an `Area3D` trigger on collision layer 3 (`LIVING_3DMODEL_TRIGGER_COLLISION_LAYER`). When entered by the player, it invokes `LivingSceneManager` to switch scenes while offsetting player coordinates.


---


## Player and camera system

The player camera system accommodates both standard desktop displays and OpenXR-compliant VR headsets seamlessly.

### LivingCamera (extends Node3D)

Root camera controller spawned into every environment scene.

* Detects runtime OpenXR availability:
  * **Desktop**: Instantiates `PlayerFPS.tscn` (`PlayerFPS`).
  * **VR / XR**: Instantiates `PlayerXR.tscn` (Godot XR Tools rig with stereo `XRCamera3D` and motion controller nodes).
* Exposes runtime motion flags: `set_player_movement_enabled()`, `set_player_gravity_enabled()`.
* Implements screen fade transitions via `fade_out()` and `fade_in()` using an internal camera-attached quad mesh for scene transitions and teleports.
* Houses camera raycasting for interactive HUD intercept and text vision (`LivingCameraTextVision`).

### PlayerFPS (extends CharacterBody3D)

First-person walking controller for desktop execution:
* Input controls: WASD / Arrow keys for planar movement (`move_speed = 5.0`, `acceleration = 10.0`, `friction = 10.0`).
* Mouse look: Mouse capture mode with customizable sensitivity and vertical pitch clamping (-85° to +85°).
* Orientation alignment: `set_view_to_direction(world_direction: Vector3)` aligns body yaw and camera pitch toward targeted visit points.

### VisitNavigator (extends Node)

Unified tour navigation component providing guided walkthroughs along the environment's `visit_path`:
* Iterates sequentially through ordered item IDs stored in `LivingEnvironment.visit_path`.
* **Controls**:
  * Desktop: Keyboard `N` (Next visit point) / `P` (Previous visit point).
  * VR: Right XR Controller `by_button` (Next) / `ax_button` (Previous).
* Teleports the player rig to the object's `LivingVisitPoint`, aligns viewing direction toward the item, and notifies `LivingEventManager` of visit completion (`notify_item_visited`).


---


## Caption and Visit Point system

Informational texts are presented directly inside the 3D world as contextual overlays rather than static 2D screen UI.

### LivingVisitPoint (extends Node3D)

Attached automatically to visitable media nodes:
* Renders a circular floor ring with a directional orientation arrow pointing directly at the object.
* Acts as the exact spatial destination for player teleportation and orientation during guided visits.

### CaptionManager (extends Resource)

Component operating on `LivingCameraTextVision`:
* Proximity and angle activation:
  * Evaluates player distance to the nearest `LivingVisitableObject`'s visit point (`text_activation_distance`, default 1.0 m; `text_deactivation_distance`, default 1.5 m).
  * Evaluates angle between the camera view direction and the visit point forward vector (`text_activation_angle`, default 20°).
* Caption hierarchy:
  * **Short Caption (`LivingCaptionHUD`)**: Floating 3D banner in front of the camera displaying the item's short description. Adapts position and scale smoothly as the player moves.
  * **Long Caption (`LivingCaptionLong`)**: Large 3D panel positioned on the side of the field of view displaying full descriptions and optional catalog information.
* Audio cues: Triggers dedicated sound effects on caption display and dismissal (`short_in.ogg`, `short_out.ogg`, `long_text_in.ogg`, `long_text_out.ogg`).
* `LivingCaptionPreview`: Allows curators to toggle text display in the editor viewport to verify legibility and positioning before exporting.


---


## Dynamic Events, Session State and Singletons

Three autoload singletons handle cross-scene persistence, events, and dynamic state:

### LivingSceneManager (Autoload)

* Manages scene transitions (`go_to_scene()`) by scene path or environment ID.
* Preserves state: caches scenes off-tree in `_scene_cache` rather than freeing them, preserving runtime modifications, video states, and avatar positions when returning to previously visited environments.

### LivingEventManager (Autoload)

* Loads and evaluates `LivingEvent` definitions stored in `LivingEnvironment.omeka_events`.
* Event triggers:
  * `CONDITION_CHECK`: Periodically evaluates logic conditions.
  * `STARGATE_COLLIDED`: Fired when crossing a stargate trigger.
  * `BUTTON_HELD_10S`: Fired on sustained button interaction.
  * `ITEM_VISITED`: Fired when a visit point is reached.
* Preconditions & Actions: Evaluates state expressions against `LivingSessionManager` and triggers actions (e.g. activating stargates, playing sound effects).

### LivingSessionManager (Autoload)

* Centralized global state storage using `ENTITY:VARIABLE:VALUE` tokens.
* Loads dynamic properties vocabulary from `omeka_dynamic_properties_table.json`.
* Tracks item visitation status (e.g. `Item123:VISIT:VISITED`).


---


## Curator Dock editor plugin

Located in `addons/curator_dock/`, this editor add-on provides a full visual workstation for scene curators:

* **DATABASE panel**:
  * Connects to Omeka S via REST API.
  * Lists available environments and remote scenes.
  * **Download**: Downloads curated `.tscn` scenes and associated assets from Nextcloud/WebDAV.
  * **Create**: Instantiates new curated scenes from templates (`living_environment_root.tscn`) into `res://curated_scenes/`.
  * **Save / Upload**: Strips runtime-only nodes, saves clean scene files, and uploads them to Nextcloud.
  * **Restore Saved Components**: Rebuilds missing media nodes and refreshes metadata from Omeka.
* **INVENTORY panel**:
  * Displays a full visual tree of the environment, containing areas and typed `Living*Object` nodes.
  * Features item thumbnails, row selection, and visibility / lock toggles.
* **MISE-EN-SCÈNE panel**:
  * Context-sensitive property editor for the selected tree node:
    * **State**: Visibility and editor lock toggles (with undo/redo support).
    * **Layout**: Position, Rotation, and Uniform Scale spinboxes synchronized bidirectionally with 3D editor gizmos.
    * **Appearance & Behavior**: Exposes typed controls matching the selected object type (curvature, diagonal, density, speed, audio parameters).
* **EVENTS panel**:
  * Read-only inspector displaying Omeka-driven triggers, preconditions, and actions associated with the environment.
* **Editor Profiles**:
  * Supports custom `EditorFeatureProfile` files (`Developer` vs `Curator`) to streamline the Godot interface for non-programmer domain experts.
