# Godot Living Platform

This is the main project to develop the Godot add-on supporting all the features to implement a 3D scene for the Living Platform project.

## Top level files

* `README.md` - here you are.
* `godot-main-project` is the main project to develop the `living_platform_plugin`.


## Some assumptions

The goal of the Living Platform is to quickyl and easily create 3D virtual visits that stay synchronized with the database. As such, assumptions are done to simplify the interaction.

* Flat floor only: the interaction happens on a flat horizontal floor. We don't support at the monet walking on slopes or stairs.
* No complex lighting: we manage at the moment everything with a single ambient light. No spot, point or directional light are used.

Some assumptions are also made on the authoring procedure of 3D models.

* Objects for the Living Platform are expected in GLB format
* Two (invisible) objects inside a 3D model will be used to instantiate collision geomtries for various tasks:
  * An object "Face" will be used to intercept camera ray casting. If the camera view center intercept the Face, a floating HUD displaying the Item shor text descriptino will be shown in front of the camera.
  * An object "Trigger" will be used to check for collisions with the "feet" of the walking camera. Whenever the camera touches the Trigger, the Long Caption object will be displayed.
* For elements of type LivingVideo and LivingImage: Face and Trigger bounds are programmatically generated.

## Living platform scenes organization

The plugin provides a set of classes and resources to implement a 3D scene for the Living Platform project. The main idea is to provide a set of prefabricated classes allowing to download and display the information store in a Living Platform OmekaS instance.

The goal is to provide a synchronized visualization of 4 types of media stored in OmekaS as items:
* plain text
* images
* videos
* 3D objects

A typical 3D scene containing one instance per type will have the following hierarchy:

- LivingEnvironment         # The root node
  - Living Area             # An area is a collection of Items, on which the visibility can be controlled
    - LivingElement         # An object representing an "Element of the digital platform"
      - LivingText          # The 3D object showing the text media type in the 3D virtual world
    - LivingElement
      - LivingImage         # Same for images
    - LivingElement
      - LivingVideo         # Same for videos
    - LivingElement
      - Living3DModel       # and for 3D models


### LivingItem (extends Node3D)

This is the top-level class, mother of the LivingEnvironment, LivingArea and LivingElement classes.
It contains:
- the ID of a specific item on the the OmekaS platform
- the code to fetch the item JSON information
- the code to download the medium
- the code to instantiate the specific class to visualize an item as child of this node
- the code to download the thumbnail of the item
- the code to control gthe visibility of the Item (and child media)
- the visibility status flags (pre-experience and post-experience)

Input properties:

* `item_id: int`

The following properties are automatically fetched htorugh the OmekaS API:

* `title`: String = ""
* `modified`: String = ""
* `resource_class`: int = 0
* `item_sets`: Array[int] = []
* `media`: Array[int] = []

Other properties:

* `experience_visibility` - to control when the object must be visible according the the state of the cotaining area. One or both of: "Pre-Experience", "Post-Experience".


### LivingEnvironment (extends LivingItem)

This is the node type that needs to be used as root of any LivingPlatform 3D scenes.

It contains the URL to the OmekaS platform. This link will be used by all LivingItem and LivingMedia objects in the scene.

Properties:

* `OMEKA_BASE_URL: String` - The URL to the OmeksS instance (e.g., https://omekas.livingculture.it)

It contains also the functions to:
- check the structure of the scene and invoke the recursive methods on the root
- recursively instantiate the media of all items in the scene
- OK save the scene back on the server

### LivignArea (extends LivingItem)

This is a collection of items. It is conceptually a defined area in the scene. However, no real constraints about the items position will be enforced.

Properties:

* `visibility_state` - The current area state: "Pre-experience" or "Post-experience"


### LivingText (extends MeshInstance3D)

Given the path to a file containing a text, creates a background rectangle and the geometry of the text that is shown over such background.

When instantiated, this object creates on-the-fly a child MeshInstance (showing the text) and its related TextMesh, realizing the text geometry:

```
var mesh_instance: MeshInstance3D = null
var text_mesh: TextMesh = null
```

The `self` will act as background.

The text can be controlled in font size and thickness.

The function `create_visualization()`, called once in `ready()`, initializes the child and the needed geometries.
The function `_update_geometries()` is called whenever the text is updated in order to update the background size and position, and the text geometry position.


### LivingCaption (extends Node3D)

A more stylistic elaborated version of LivingText, where the a predefined GLB geometry is used as background.

It is based on loading the preset scene `living_caption_content.gd`, which contains already a root MeshInstance3D to visualize the text and a child object acting as background (This is the reverse with respect to the LivingText).

The behavior and the functions are very similar to LivingText.


### LivingImage (extends MeshInstance3D)

Given the path to an image, creates a 3D rectangle showing the image pixels in the virtual space.


### LivingVideo (extends Sprite 3D, Loaded from a subscene with children)

Given the path to a Ogg/Vorbis video (.ogv), creates a rectangle in space that can visualize such video.

It is based on the instantiation of the PackedScene `living_video.tscn`, which containg a pre-configured hierarchy of nodes needed to show a video:

LivingVideo (Sprite3D)
- VideoPlayer-SubViewport (SubViewport)
  - VideoStreamPlayer (VideoStreamPlayer)

After setting the video_path, the LivingVideo support control methods to play/stop/pause a video.

The size of the video area can be controlled by the `pixel_size` attribute.

Godot can natively visualize only Ogg/Vorbis videos (.ogv). You can use `ffmpeg` to quickly convert any format to OGV from the command line. E.g.:

    ffmpeg -i 1514-maciste_sulla_scogliera.mp4 -c:v libtheora -q:v 6 -c:a libvorbis -q:a 5 1514-maciste_sulla_scogliera.ogv

### Living3DModel (extends Node3D)

Given the path to a GLTF/GLB 3D model (.glb), loads the objects and adds it as child.

The model can be loaded from:
* A local pre-imported resource (res://path/tp/file.glb): faster, can control import options
* A whatever file in the filesystem: slower, no control of import options.


## LivingCamera

This is a class implementing methods to walk on the floor.
The class relies on loading a specific scene `living_camera.tscn`, containing the nodes needed to implement a walking control (via keys), looking around control (via mouse), and also supports interaction through VR headsets.

It simulates gravity. So, it supposes the presence in the scene of a collider acting as floor (or you will fall down, forever).


## Caption Visualization

Here is described the system to manage the visualization of text visualization (short text, long text, catalog text).

### Caption Objects

The text is visualized as 3D text in front of a background.
Here is the hierarchy of classes to dynamically show informative text.

- LivingCaption             - A compound 3D object to dynamically show text over a background object. The background object has to be specified as parameter in the constructor.
  - LivingCaptionHUD        - Uses a wide and short object as background. Use to show text floating in front of the camera.
  - LivingCaptionLong       - Uses a big rectangular object as background to show long text. It supports also a dynamic overlay for additional optional text (catalog).

Requirements:

* The background objects are supposed to lay on the vertical X/Y plane.
* The text is visualized on the +Z side of the plane. So, the background front face must lay exactly over the X/Y plane.
* The text is normally shown over the whole surface of the background, computed from teh AABB of the background node.
* The `background_[x|y]_proportion` fields allow to shrink the area occupied by the text and leave amrgine for a border in the background.

### Caption Management

Requirements. The subscene appended to a LivingElement must contain the two following nodes:

* A "Face" `CollisionObject3D` node with `collision_layer` set to `LivingConstants.LIVING_3DMODEL_FRONT_FACE_COLLISION_LAYER`.
  * This will be used to intercept the camer view.
  * For Living3DModel objects, this is automatically set up by searching for a node called "Face".
  * For LivingImage and LivingVideo, this face is automatically generated according to the size of the background.
* A floor "Trigger" `CollisionObject3D` node with `collision_layer` set to `LivingConstants.LIVING_3DMODEL_TRIGGER_COLLISION_LAYER`.
  * This will be used to intercept when the camera "walks over" an are in front of the object.
  * This happens because the camera has a "feet" collision node set on the same layer.
  * For Living3DModel objects, this is automatically set up by searching for a node called "Trigger".
  * For LivingImage and LivingVideo, this trigger surface is automatically generated according to the size of the background.

Assuming the above-described node are present in scene LivingElements, the visulization of the captions is managed by two components added to the camera.

* `hud_manager.gd` - Manages the visualization fo the small HUD floating in front of the face of the camera
  * At each `_process()`, the HUD invokes the camera method to cast a ray in front and tries to intercept the closest `LivingElement` by colliding with its "Face".
  * If the closest element, is null, the HUD is hidden, Otherwise the short text of the LivingElement is taken and the `LivingCaptionHud` is shown by appending it to the camera.
  * If the closest LivingElement changes, or goes to null. The HUD object is instructed to _fade-out_ and is removed as child of the camera.
* `caption_managed.gd` - Manages the long text and the catalog information.
  * When the camera triggers the collision with a "Trigger" node, the long text and the catalog text are taken from the correspoinding LivingElement and used to instantiate `LivingCaptionLong`.
  * The caption object is place at the root level of the scene, in a position with a parameterizable offset with respect to the camera local space. The idea is to visualize the object on the right side of the camera field-of-view.
  * At this point, the object itself continuously monitor (in its `_process()`) the distance with the camera. If the camera move further than a given threshold, the caption object is instructed to _fade-out_.

The "fade-out" of LivingCaptions is managed by invoking the `fade_out()` method.
When invoked, the LivingCaption enters a `FADING_OUT` state in which it animates (in the `_process()` method) a visibly property that is reducing the visibility of the object.
The idea is that several `_fade_out_mode_` can be implemented, like shrinking (size animation), disappearing (transparency animation), fly-away (global_position animation). At the moment, only shrinking is implemented.
When the fade-pout animation has terminated, the node self-detaches from the scene.

## Real-time navigation

TODO
