@tool
extends MeshInstance3D


@export_tool_button("Set Icon") var set_icon_btn = set_icon

func set_icon():
	
	print("Setting text for ", name)
	
	var text_mesh = self.mesh as TextMesh
	if name == "play":
		text_mesh.text = "\u23F5"
	elif name == "pause":
		text_mesh.text = "\u23F8"
	elif name == "skipback":
		text_mesh.text = "\u23EE"
