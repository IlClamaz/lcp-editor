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

## Livign platform scenes organization

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

This is a class implementing methods to walk on the floor

## Caption Management

In addition, there is a hierarchy of classes to dynamically show informative text.

- LivingCaption             # A Compound 3D object to show text over a background
  - LivingCaptionHUD        # Uses a wide and short object as background. Use to show text floating in front of the camera.
  - LivingCaptionLong       # Uses a big rectangular object as background to show long text. It supports also a dynamic overlay for additional optional text.


### LivingCaption (extends Node3D)

A more stylistic elaborated version of LivingText, where the a predefined GLB geometry is used as background.

It is based on loading the preset scene `living_caption_content.gd`, which contains already a root MeshInstance3D to visualize the text and a child object acting as background (This is the reverse with respect to the LivingText).

The behavior and the functions are very similar to LivingText.
