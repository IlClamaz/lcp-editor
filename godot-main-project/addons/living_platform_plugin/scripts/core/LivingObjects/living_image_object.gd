@tool
extends LivingFlatMediaObject
class_name LivingImageObject

# Typed parent for Omeka "Immagine".


func get_living_image_child() -> LivingImage:
	for child in get_children():
		if child is LivingImage:
			return child as LivingImage
	return null
