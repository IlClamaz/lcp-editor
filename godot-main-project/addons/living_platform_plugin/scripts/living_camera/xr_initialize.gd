extends Node

var xr_inteface : XRInterface

func _ready():
	# Attempt to find the OpenXR interface
	var interface = XRServer.find_interface("OpenXR")

	# Check if the interface was found and successfully initialized
	if interface and interface.initialize():
		print("VR headset connected and initialized successfully!")
		# Optional: If using a separate viewport for VR, enable it here
		get_viewport().use_xr = true
	else:
		print("VR headset not found or failed to initialize.")
		# Optional: Fallback to a non-VR setup
		get_viewport().use_xr = false
