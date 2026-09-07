@tool
extends RefCounted
class_name CuratorFieldRegistry

## Typed Appearance / Behavior / Layout matrix for Living*Object (design doc).


func specs_for(target: Node) -> Array[CuratorFieldSpec]:
	var out: Array[CuratorFieldSpec] = []
	if target == null:
		return out

	# --- Appearance: flat media ---
	if target is LivingFlatMediaObject:
		out.append(CuratorFieldSpec.make_float(
			"curvature", "Curvature", CuratorFieldSpec.Section.APPEARANCE,
			-360.0, 360.0, 0.1, "°", true
		))
		out[out.size() - 1].visible_if = func(t):
			return t is LivingFlatMediaObject and (t as LivingFlatMediaObject)._has_2d_in_children()
		out.append(CuratorFieldSpec.make_float(
			"diagonal", "Diagonal", CuratorFieldSpec.Section.APPEARANCE,
			0.01, 50.0, 0.01, "m", false
		))
		out[out.size() - 1].visible_if = func(t):
			return t is LivingFlatMediaObject and (t as LivingFlatMediaObject)._has_2d_in_children()

	# --- Appearance: slideshow extras ---
	if target is LivingSlideShowObject:
		out.append(CuratorFieldSpec.make_float(
			"controls_offset_y", "Controls Offset Y", CuratorFieldSpec.Section.APPEARANCE,
			-5.0, 0.0, 0.01, "m", false
		))
		out.append(CuratorFieldSpec.make_vector2(
			"frame_opening_reference_size", "Frame Opening Ref", CuratorFieldSpec.Section.APPEARANCE,
			0.001, 10.0, 0.001
		))
		out.append(CuratorFieldSpec.make_float(
			"frame_surface_offset", "Frame Surface Offset", CuratorFieldSpec.Section.APPEARANCE,
			0.0, 0.05, 0.0001, "m", false
		))

	# --- Appearance: 3D face ---
	if target is Living3DModelObject:
		var face := CuratorFieldSpec.make_bool(
			"face_visible", "Face Visible", CuratorFieldSpec.Section.APPEARANCE
		)
		face.visible_if = func(t):
			return t is Living3DModelObject and (t as Living3DModelObject)._has_face_in_children()
		out.append(face)

	# --- Appearance: target border ---
	if target is LivingTargetObject:
		out.append(CuratorFieldSpec.make_bool(
			"border_visible", "Border Visible", CuratorFieldSpec.Section.APPEARANCE
		))
		out.append(CuratorFieldSpec.make_color(
			"border_color", "Border Color", CuratorFieldSpec.Section.APPEARANCE
		))
		out.append(CuratorFieldSpec.make_float(
			"border_thickness_h", "Border Thickness H", CuratorFieldSpec.Section.APPEARANCE,
			0.001, 5.0, 0.01, "m", false
		))
		out.append(CuratorFieldSpec.make_float(
			"border_thickness_v", "Border Thickness V", CuratorFieldSpec.Section.APPEARANCE,
			0.001, 5.0, 0.01, "m", false
		))
		out.append(CuratorFieldSpec.make_float(
			"border_corner_radius", "Border Corner Radius", CuratorFieldSpec.Section.APPEARANCE,
			0.0, 10.0, 0.01, "m", true
		))
		out.append(CuratorFieldSpec.make_float(
			"border_y", "Border Y", CuratorFieldSpec.Section.APPEARANCE,
			-50.0, 50.0, 0.01, "m", false
		))
		out.append(CuratorFieldSpec.make_string(
			"border_text", "Border Text", CuratorFieldSpec.Section.APPEARANCE
		))
		out.append(CuratorFieldSpec.make_bool(
			"border_text_visible", "Border Text Visible", CuratorFieldSpec.Section.APPEARANCE
		))
		out.append(CuratorFieldSpec.make_float(
			"border_name_font_size", "Border Font Size", CuratorFieldSpec.Section.APPEARANCE,
			1.0, 256.0, 1.0, "", false
		))
		out.append(CuratorFieldSpec.make_float(
			"chalk_wear", "Chalk Wear", CuratorFieldSpec.Section.APPEARANCE,
			0.0, 1.0, 0.01, "", true
		))

	# --- Appearance: Stargate caption text only ---
	if target is LivingStargateObject:
		out.append(CuratorFieldSpec.make_string(
			"stargate_caption_text", "Stargate Text", CuratorFieldSpec.Section.APPEARANCE
		))

	# --- Behavior: show_caption + visit marker (LivingVisitableObject) ---
	if target is LivingVisitableObject:
		out.append(CuratorFieldSpec.make_bool(
			"show_caption", "Show Text", CuratorFieldSpec.Section.BEHAVIOR
		))
		out.append(CuratorFieldSpec.make_bool(
			"show_visit_point", "Show Visit Point", CuratorFieldSpec.Section.BEHAVIOR
		))

	# --- Behavior: video ---
	if target is LivingVideoObject:
		out.append(CuratorFieldSpec.make_float(
			"auto_pause_camera_distance", "Auto-Pause Camera Distance", CuratorFieldSpec.Section.BEHAVIOR,
			0.0, 1000.0, 0.1, "m", false
		))

	# --- Behavior: slideshow ---
	if target is LivingSlideShowObject:
		out.append(CuratorFieldSpec.make_bool(
			"loop_slides", "Loop Slides", CuratorFieldSpec.Section.BEHAVIOR
		))

	# --- Behavior: audio ---
	if target is LivingAudioObject:
		out.append_array(_audio_behavior_specs())

	# --- Behavior: animated 3D ---
	if target is Living3DModelAnimatedObject:
		out.append(CuratorFieldSpec.make_bool(
			"moving", "Moving", CuratorFieldSpec.Section.BEHAVIOR
		))
		out.append(CuratorFieldSpec.make_bool(
			"random_poses_playing", "Random Poses", CuratorFieldSpec.Section.BEHAVIOR
		))
		out.append(CuratorFieldSpec.make_float(
			"move_speed", "Move Speed", CuratorFieldSpec.Section.BEHAVIOR,
			0.0, 50.0, 0.1, "", false
		))
		out.append(CuratorFieldSpec.make_bool(
			"random_spawn", "Random Spawn", CuratorFieldSpec.Section.BEHAVIOR
		))

	# --- Behavior: crowd ---
	if target is LivingCrowdObject:
		out.append(CuratorFieldSpec.make_int(
			"density", "Density", CuratorFieldSpec.Section.BEHAVIOR, 1, 40, 1
		))

	return out


## Which Layout subsections to show for this target.
## Keys: "position", "rotation", "scale" -> bool
func layout_visibility(target: Node) -> Dictionary:
	var show_position: bool = true
	var show_rotation: bool = true
	var show_scale: bool = true

	if target is LivingFlatMediaObject:
		# Size is controlled via Appearance.diagonal
		show_scale = false
	elif target is LivingCrowdObject:
		show_rotation = false
		show_scale = false
	elif target is LivingAudioObject:
		show_rotation = false
		show_scale = false
	elif target is LivingVideo360Object:
		show_rotation = false
		show_scale = false
	elif target is LivingArea:
		show_scale = false

	return {
		"position": show_position,
		"rotation": show_rotation,
		"scale": show_scale,
		"visit_position": target is LivingVisitableObject,
		"visit_rotation": target is LivingVisitableObject,
	}


func _audio_behavior_specs() -> Array[CuratorFieldSpec]:
	var atten_keys := PackedStringArray([
		"ATTENUATION_INVERSE_DISTANCE",
		"ATTENUATION_INVERSE_SQUARE_DISTANCE",
		"ATTENUATION_LOGARITHMIC",
		"ATTENUATION_DISABLED",
	])
	var specs: Array[CuratorFieldSpec] = []
	specs.append(CuratorFieldSpec.make_bool("autoplay", "Autoplay", CuratorFieldSpec.Section.BEHAVIOR))
	specs.append(CuratorFieldSpec.make_bool("loop", "Loop", CuratorFieldSpec.Section.BEHAVIOR))
	specs.append(CuratorFieldSpec.make_float("volume_db", "Volume", CuratorFieldSpec.Section.BEHAVIOR, -80.0, 24.0, 0.1, "dB"))
	specs.append(CuratorFieldSpec.make_float("max_db", "Max dB", CuratorFieldSpec.Section.BEHAVIOR, -24.0, 6.0, 0.1, "dB"))
	specs.append(CuratorFieldSpec.make_float("pitch_scale", "Pitch", CuratorFieldSpec.Section.BEHAVIOR, 0.01, 4.0, 0.01))
	specs.append(CuratorFieldSpec.make_float("unit_size", "Unit Size", CuratorFieldSpec.Section.BEHAVIOR, 0.1, 100.0, 0.1, "m"))
	specs.append(CuratorFieldSpec.make_float("max_distance", "Max Distance", CuratorFieldSpec.Section.BEHAVIOR, 0.0, 4096.0, 0.1, "m"))
	specs.append(CuratorFieldSpec.make_enum("attenuation_model", "Attenuation Model", CuratorFieldSpec.Section.BEHAVIOR, atten_keys))
	specs.append(CuratorFieldSpec.make_int("max_polyphony", "Max Polyphony", CuratorFieldSpec.Section.BEHAVIOR, 1, 32, 1))
	specs.append(CuratorFieldSpec.make_float("panning_strength", "Panning Strength", CuratorFieldSpec.Section.BEHAVIOR, 0.0, 1.0, 0.01))
	specs.append(CuratorFieldSpec.make_string("bus", "Bus", CuratorFieldSpec.Section.BEHAVIOR))
	specs.append(CuratorFieldSpec.make_float(
		"attenuation_filter_cutoff_hz", "Atten. Filter Cutoff", CuratorFieldSpec.Section.BEHAVIOR,
		10.0, 20000.0, 1.0, "Hz"
	))
	specs.append(CuratorFieldSpec.make_float(
		"attenuation_filter_db", "Atten. Filter dB", CuratorFieldSpec.Section.BEHAVIOR,
		-80.0, 0.0, 0.1, "dB"
	))
	return specs
