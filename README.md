# Godot Living Platform

This is the main project to develop the Godot add-on supporting all the features to implement a 3D scene for the Living Platform project.

## Top level files

* `README.md` - here you are.
* `godot-main-project` is the main project to develop the `living_platform_plugin`.


## Livign platform scenes organization

The plugin provides a set of classes and resources to implement a 3D scene for the Living Platform project. The main idea is to provide a set of prefabricated classes allowing to download and display the information store in a Living Platform OmekaS instance.

The goal is to provide a synchronized visualization of 4 types of media stored in OmekaS as items:
* plain text
* images
* videos
* 3D objects

An example 3D scene containing one instance per type will have the following hierarchy:

LivingScene             # The root node
- LivingItem            # An object pointing to a specific Item in the OmekaS platform
 - LivingMedia          # An object with informatino about media type and a reference to the OmekaS item
   - LivingText         # The 3D object showing the media type in the 3D virtual world
- LivingItem
 - LivingMedia
   - LivingImage        # Same for images
- LivingItem
 - LivingMedia
   - LivingVideo        # Same for videos
- LivingItem
 - LivingMedia
   - Living3DModel      # and for 3D models

### LivingScene (extends Node3D)

This is the node type that needs to be used as root of any LivingPlatform 3D scenes.

It contains the URL to the OmekaS platform. This link will be used by all LivingItem and LivingMedia objects in the scene.

Properties:

* `OMEKA_BASE_URL: String`

### LivingItem (extends Node3D)

Given the item ID, it is able to fetch all the required info from the OmekaS platform and instantiate all the childern LivingMedia objects.

Input properties:

* `item_id: int`

The following properties are automatically fetched htorugh the OmekaS API:

* `title`: String = ""
* `modified`: String = ""
* `resource_class`: int = 0
* `item_sets`: Array[int] = []
* `media`: Array[int] = []

Other properties:

* `experience_visibility` - to control the visibility of the objects. One among "PreExperience", "Experience", "PostExperience"


### LivingMedia (extends Node)

Given the media ID, it is able to fetch all the required info from the OmekaS platform and instantiate the correct submedia type as child object.

Also, it contains the code to download the binary of the referenced media into a local cache folder. Media are never loaded directly from the network. They are first downloaded and stored, and then a local filesystem path will be used to instantiate the 3D nodes.

### LivingText (extends Node3D)

Given the path to a file containing a text, creates a background rectangle and the geometry of the text that is shown over such background.

When instantiated, this object creates on-the-fly two children:

var text_mesh: TextMesh = null
var background: MeshInstance3D = null

The text can be controlled in font size and thickness.

The function `create_visualization()`, called once in `ready()`, initializes the children and the needed geometries.
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

### Living3DModel (TODO)


### Living3DModel (TODO)