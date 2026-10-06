# Living Platform Plugin (`living_platform_plugin`)

The core data and runtime engine for the **Living Culture Platform (LCP)** in Godot Engine.

This plugin is responsible for:
- Synchronizing 3D scenes with an Omeka S semantic database.
- Downloading, caching, and instantiating multimodal participatory assets (3D models, images, videos, 360° videos, spatial audio, animated characters, crowds, carousels, and templates).
- Managing scene graph hierarchies (`LivingEnvironment` → `LivingArea` → `LivingObject` → concrete media).
- Handling spatial navigation, visit points, and dual player locomotion (Desktop FPS vs OpenXR VR).
- Providing 3D in-world captions (floating HUD and extended descriptions).
- Managing Omeka-driven interactive events, session state tokens, and seamless cross-scene caching.

---

## Architectural Assumptions and Authoring Conventions

The Living Platform streamlines the authoring of virtual visits synchronized with Omeka S:

1. **Locomotion and Gravity**:
   - Navigation occurs over a walkable horizontal plane with simulated gravity.
   - Slopes, stairs, and multi-level vertical paths are currently not modeled.
2. **Modular Lighting (`LivingLights`)**:
   - Lighting is packaged in a standard modular rig (`LivingLights`), ensuring uniform illumination across environments.
3. **Static 3D Model Conventions (GLB)**:
   - 3D assets are imported in GLB format.
4. **Procedural Colliders and Curvature for 2D Media**:
   - Flat media (`LivingImage`, `LivingVideo`, `LivingSlideShow`) automatically generate their own `"Face"` and `"Trigger"` collision boundaries matching media dimensions.
   - 2D media support cylindrical curvature (both concave and convex) and automatic diagonal scaling.
5. **Video Playback via FFmpeg**:
   - Video media uses the multiplatform FFmpeg GDExtension, supporting native playback of `.mp4` (H.264) and `.ogv` (Theora/Vorbis).
6. **Automated Visit Points (`LivingVisitPoint`)**:
   - Visitable objects automatically maintain a floor-level `LivingVisitPoint` marker placed just outside their +Z bounding box face, pointing toward the object center.

---

## Scene Organization and Hierarchy

Curated scenes are rooted in a `LivingEnvironment` node. Items and areas downloaded from Omeka S are organized into a clean typed hierarchy:

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

---

## Core Classes Reference

### `LivingItem` (extends `Node3D`)

The base class for all Omeka-connected nodes (`LivingEnvironment`, `LivingArea`, `LivingObject`).

#### Multi-Phase Synchronization Lifecycle
1. **Fase 0 (Prefetch)**:
   - Queries the entire environment metadata tree upfront (`OmekaTreePrefetcher`).
   - Resolves typed participatory item classes before spawning child nodes.
2. **Fase 1 (Download & Cache)**:
   - Downloads media files and thumbnails from Nextcloud/WebDAV.
   - Validates cache fingerprints using HTTP headers (`ETag`, `Last-Modified`, `Content-Length`) against local JSON cache metadata (`downloaded_living_media/`) to avoid unnecessary re-downloads.
3. **Fase 2 (Instantiation)**:
   - Recursively spawns typed children (`components` and `areas`).
   - If an existing node class does not match the participatory type in the database, replaces the node while preserving transform, visibility, and user-edited properties.
   - Cleans up orphaned children deleted on Omeka.
   - Instantiates concrete media nodes (`instantiate_medium()`).

#### Properties
- `item_id: int` - Remote Omeka S item ID.
- **Group OMEKAS**:
  - `title: String` - Item title.
  - `modified: String` - Remote timestamp of last modification.
  - `short_description: String` - Multiline short text (floating HUD).
  - `long_description: String` - Multiline extended description (caption panel).
  - `catalog_description: String` - Catalog / archaeological notes.
  - `resource_class: int` - Omeka resource class ID.
  - `components: Array[int]` - IDs of child items.
  - `areas: Array[int]` - IDs of child areas.
  - `medium_uri: String` - Remote download URI for the primary media file.
  - `thumbnail_uri: String` - Remote download URI for the thumbnail.
- **Group REFRESH AND MEDIUM**:
  - `auto_fetch_metadata`, `auto_instantiate_children`, `auto_download_medium`, `auto_instantiate_medium`, `auto_recurse_children: bool`.
  - `media_filename`, `media_path`, `media_type`, `participatory_item_type`, `thumbnail_path: String`.

#### Signals & State
- `enum BuildState { IDLE, FETCHING, SPAWNING_CHILDREN, DOWNLOADING, READY, ERROR }`
- Signals: `build_state_changed`, `build_finished`, `download_media_success`, `download_media_error`, `download_thumbnail_success`, `download_thumbnail_error`.

---

### `LivingEnvironment` (extends `LivingItem`)

Root node of every curated scene.

#### Responsibilities
- Holds `OMEKA_BASE_URL: String` (e.g. `https://omekas.livingculture.it`).
- Orchestrates full scene rebuilds via `rebuild_environment()`.
- Remote scene I/O: uploading curated scenes (`upload_scene()`), listing remote scenes (`list_remote_scenes()`), and downloading scenes from Nextcloud.
- Holds environment events (`omeka_events: Array[LivingEvent]`) and guided tour item order (`visit_path: Array[int]`).
- Automatically ensures an environment-level visit target (`LivingTargetObject`) exists under itself.

---

### `LivingArea` (extends `LivingItem`)

A spatial and logical collection of items within an environment.

#### Responsibilities
- Groups related items under a common transform.
- Automatically ensures a scene-owned `LivingTargetObject` under itself.

---

### `LivingObject` (extends `LivingItem`)

Base class for all interactive media elements instantiated within an area or environment.

#### Responsibilities
- Assigns editor metadata `_edit_group_` for group selection in the Godot 3D editor.
- Adds the node to the `RayPickableLivingItems` group (`LivingConstants.RAY_PICKABLE_GROUP_NAME`).
- **Birth Invisibility**: On initial instantiation, receives `is_born = true` metadata and sets `visible = false`, preventing uncurated items from cluttering the scene until deliberately placed by a curator.

---

### `LivingVisitableObject` (extends `LivingObject`)

Abstract base class for objects that define an interactive viewpoint or visit position.

#### Responsibilities
- Computes the player's target transform (`get_visit_transform()`) placed just outside the +Z bounding face of the object, facing toward the object.
- Manages an attached floor pin marker (`LivingVisitPoint`).
- Provides in-editor caption preview via `toggle_caption_preview()`.

#### Properties
- **Group LAYOUT**:
  - `visit_position: Vector3` - Manual position offset from auto AABB pose.
  - `visit_rotation_degrees: Vector3` - Manual rotation offset from auto orientation.
- **Group BEHAVIOR**:
  - `show_caption: bool` (Inspector alias: `show_text`) - Controls whether `CaptionManager` displays captions for this item.
  - `show_visit_point: bool` - Controls floor pin marker visibility in the 3D viewport.
- Inspector Button: `Preview Text` (`toggle_caption_preview`).

---

### `LivingTargetObject` (extends `LivingVisitableObject`)

Scene-owned visit target representing an Area or Environment (not an Omeka item; `item_id = 0`, `bound_item_id` links to parent).

#### Responsibilities
- Syncs metadata and descriptions from parent Area/Environment.
- Renders a procedural rounded-rectangle or elliptical chalk border on the floor around child geometry.
- Uses a dedicated custom shader (`target_chalk.gdshader`) with realistic hand-drawn chalk aesthetics.

#### Properties
- `bound_item_id: int` - Target area/environment ID.
- `border_visible: bool`, `border_color: Color`.
- `border_thickness_h: float`, `border_thickness_v: float`, `border_corner_radius: float` (corner rounding in meters).
- `border_y: float`, `border_text: String`, `border_text_visible: bool`, `border_name_font_size: float`.
- `chalk_wear: float` (0.0 to 1.0) - Chalk texture wear and dissipation.
- `chalk_alpha: float` (0.0 to 1.0) - Shader opacity multiplier.

---

## Typed Media Classes Reference

### Flat Media: `LivingFlatMediaObject` (extends `LivingVisitableObject`)

Common base class for 2D planar media visualizers (`LivingImageObject`, `LivingVideoObject`, `LivingSlideShowObject`).

- `diagonal: float` - Real-world diagonal size of the plane in meters (replaces direct node scaling).
- `curvature: float` - Cylindrical curvature in degrees (-360° to +360°). Positive values create a concave curved display; negative values create a convex display.

---

### 1. Images: `LivingImageObject` & `LivingImage`
- **`LivingImageObject`**: Spawns `LivingImage`.
- **`LivingImage`** (`MeshInstance3D`):
  - Builds a segmented curved plane mesh (32 segments).
  - Automatically generates `Face` and `Trigger` collision bodies matching the image size and curvature.

### 2. Videos: `LivingVideoObject` & `LivingVideo`
- **`LivingVideoObject`**:
  - `auto_pause_camera_distance: float` (default 10.0 m) - Pauses video when the player moves away.
  - Inspector preview buttons: `Play Video`, `Toggle Pause`, `Stop Video`.
- **`LivingVideo`** (`MeshInstance3D`):
  - Uses `SubViewport`, `VideoStreamPlayer`, and 3D playback controls (`living_video.tscn`).
  - Powered by FFmpeg GDExtension for MP4/OGV decoding.

### 3. 360° Videos: `LivingVideo360Object` & `LivingVideo360`
- **`LivingVideo360Object`**: `sphere_radius: float` (default 500.0 m).
- **`LivingVideo360`** (`Node3D`): Inverted `SphereMesh` surround video player.

### 4. 3D Models: `Living3DModelObject` & `Living3DModel`
- **`Living3DModelObject`**: `face_visible: bool` - Toggles visibility of the `"Face"` mesh.
- **`Living3DModel`** (`Node3D`): Dynamically loads GLB models from resources or disk;

### 5. Animated 3D Characters: `Living3DModelAnimatedObject` & `Living3DModelAnimated`
- **`Living3DModelAnimatedObject`**: `move_speed: float`, `moving: bool`, `random_poses_playing: bool`, `random_spawn: bool`, pose chain parameters.
- **`Living3DModelAnimated`** (`CharacterBody3D`): Navigates scene waypoints, plays animations, and manages character state machines.

### 6. Spatial Audio: `LivingAudioObject` & `LivingAudio`
- **`LivingAudioObject`**: `autoplay`, `loop`, `volume_db`, `max_db`, `pitch_scale`, `unit_size`, `max_distance`, `attenuation_model`, `max_polyphony`, `panning_strength`, `bus`, `attenuation_filter_cutoff_hz`, `attenuation_filter_db`. Preview buttons: Play / Stop.
- **`LivingAudio`** (`AudioStreamPlayer3D`): Loads WAV, OGG, or MP3 audio and applies 3D spatial attenuation.

### 7. Crowds: `LivingCrowdObject` & `LivingCrowd`
- **`LivingCrowdObject`**: `density: int` (1 to 40).
- **`LivingCrowd`** (`Node3D`): Reads navigation checkpoints and instantiates animated crowd agents traversing the scene.

### 8. Slideshows: `LivingSlideShowObject` & `LivingSlideShow`
- **`LivingSlideShowObject`**: `loop_slides`, `slide_transition_enabled`, `slide_transition_duration`, `slide_transition_fade_min_alpha`, `auto_hide_source_elements`, `controls_offset_y`, `frame_opening_reference_size`, `frame_surface_offset`.
- **`LivingSlideShow`** (`MeshInstance3D`): 3D carousel presenting images with interactive 3D navigation buttons, cross-fade transitions, and optional 3D frame models.

### 9. Container Models: `LivingContainerModelObject` & `LivingScene`
- **`LivingContainerModelObject`**: Handles environment template archives (.zip).
- **`LivingScene`** (`Node3D`): Extracts `.zip` packages to local disk and instantiates the unpacked entry scene (`LivingEnvironmentTemplate.tscn`) safely.

### 10. Stargates: `LivingStargateObject` & `LivingStargate`
- **`LivingStargateObject`**: `target_environment_id: int`, `use_scene_path: bool`, `target_scene_path: String`, `stargate_caption_text: String`, `stargate_caption_scale: float`, `stargate_caption_position_y: float`, `color_active`, `color_inactive`, `color_used`.
- **`LivingStargate`** (`Node3D`): Glowing conical portal with an `Area3D` trigger on collision layer 3. When entered, teleports the player via `LivingSceneManager`.

---

## Player and Camera System

### `LivingCamera` (`Node3D`)
Root camera rig spawned into every scene:
- Detects OpenXR runtime availability automatically:
  - **Desktop**: Instantiates `PlayerFPS.tscn` (`PlayerFPS`).
  - **VR / XR**: Instantiates `PlayerXR.tscn` (Godot XR Tools stereo rig with motion controllers).
- Camera fade transitions (`fade_out()`, `fade_in()`) using an attached camera quad mesh.
- Houses camera raycasting for interactive text vision (`LivingCameraTextVision`).

### `PlayerFPS` (`CharacterBody3D`)
Desktop first-person walking controller:
- Movement: WASD / Arrow keys (`move_speed = 5.0`, `acceleration = 10.0`, `friction = 10.0`).
- Mouse look: Captured mouse mode with vertical pitch clamping (-85° to +85°).
- Orientation alignment: `set_view_to_direction()` aligns body yaw and camera pitch toward targeted visit points.

### `VisitNavigator` (`Node`)
Unified tour navigation component providing guided walkthroughs along `LivingEnvironment.visit_path`:
- Desktop: `N` (Next item) / `P` (Previous item).
- VR: Right controller `by_button` (Next) / `ax_button` (Previous).
- Teleports the player rig to each item's `LivingVisitPoint`, aligns viewing direction, and records visits in `LivingSessionManager`.

---

## Caption and Visit Point System

### `LivingVisitPoint` (`Node3D`)
Floor marker composed of a circular ring and a directional orientation arrow pointing at the object. Serves as the player teleport target and viewing orientation.

### `CaptionManager` (`Resource`)
Mounted on `LivingCameraTextVision`:
- Evaluates player proximity (`text_activation_distance = 1.0m`, `text_deactivation_distance = 1.5m`) and view angle (`text_activation_angle = 20°`) relative to the nearest `LivingVisitableObject`.
- **Floating HUD (`LivingCaptionHUD`)**: Short description floating in front of the camera, smoothly adjusting position and scale with player distance.
- **Long Caption (`LivingCaptionLong`)**: Extended description and catalog panel positioned to the side of the field of view.
- Sound effects on show and hide (`short_in.ogg`, `short_out.ogg`, `long_text_in.ogg`, `long_text_out.ogg`).
- `LivingCaptionPreview`: Allows curators to preview captions directly in the Godot 3D editor.

---

## Dynamic Events, Session State and Singletons

### `LivingSceneManager` (Autoload Singleton)
- Manages scene switching (`go_to_scene()`) by scene path or environment ID.
- Off-tree caching: Preserves outgoing scenes in `_scene_cache` rather than freeing them, retaining dynamic state, video playback positions, and crowd locations when returning to previously visited environments.

### `LivingEventManager` (Autoload Singleton)
- Evaluates `LivingEvent` definitions configured on `LivingEnvironment.omeka_events`.
- Triggers: `CONDITION_CHECK`, `STARGATE_COLLIDED`, `BUTTON_HELD_10S`, `ITEM_VISITED`.
- Evaluates preconditions against `LivingSessionManager` and executes actions (e.g. state variable updates, audio cues, stargate activation).

### `LivingSessionManager` (Autoload Singleton)
- Centralized store for session state using `ENTITY:VARIABLE:VALUE` tokens.
- Loads property schemas from `omeka_dynamic_properties_table.json`.
- Tracks item visitation status (`Item123:VISIT:VISITED`).
