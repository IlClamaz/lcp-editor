@tool
extends RefCounted
class_name CuratorFieldSpec

## Declarative field for Mise-en-scène Appearance / Behavior.

enum Section { APPEARANCE, BEHAVIOR }
enum UiKind { BOOL, FLOAT, INT, STRING, ENUM, VECTOR2 }


var property: String = ""
var label: String = ""
var section: Section = Section.BEHAVIOR
var ui: UiKind = UiKind.FLOAT
var min_value: float = 0.0
var max_value: float = 100.0
var step: float = 0.1
var suffix: String = ""
## When true, FLOAT is shown as slider + spin (e.g. curvature).
var use_slider: bool = false
## Enum names for UiKind.ENUM (e.g. AudioStreamPlayer3D.AttenuationModel keys).
var enum_keys: PackedStringArray = PackedStringArray()
## Optional: Callable(target) -> bool. If set and returns false, field is skipped.
var visible_if: Callable = Callable()


static func make_bool(property: String, label: String, section: Section) -> CuratorFieldSpec:
	var s := CuratorFieldSpec.new()
	s.property = property
	s.label = label
	s.section = section
	s.ui = UiKind.BOOL
	return s


static func make_float(
	property: String,
	label: String,
	section: Section,
	min_v: float,
	max_v: float,
	step_v: float = 0.1,
	suffix_v: String = "",
	slider: bool = false
) -> CuratorFieldSpec:
	var s := CuratorFieldSpec.new()
	s.property = property
	s.label = label
	s.section = section
	s.ui = UiKind.FLOAT
	s.min_value = min_v
	s.max_value = max_v
	s.step = step_v
	s.suffix = suffix_v
	s.use_slider = slider
	return s


static func make_int(
	property: String,
	label: String,
	section: Section,
	min_v: int,
	max_v: int,
	step_v: int = 1
) -> CuratorFieldSpec:
	var s := CuratorFieldSpec.new()
	s.property = property
	s.label = label
	s.section = section
	s.ui = UiKind.INT
	s.min_value = float(min_v)
	s.max_value = float(max_v)
	s.step = float(step_v)
	return s


static func make_string(property: String, label: String, section: Section) -> CuratorFieldSpec:
	var s := CuratorFieldSpec.new()
	s.property = property
	s.label = label
	s.section = section
	s.ui = UiKind.STRING
	return s


static func make_enum(
	property: String,
	label: String,
	section: Section,
	keys: PackedStringArray
) -> CuratorFieldSpec:
	var s := CuratorFieldSpec.new()
	s.property = property
	s.label = label
	s.section = section
	s.ui = UiKind.ENUM
	s.enum_keys = keys
	return s


static func make_vector2(
	property: String,
	label: String,
	section: Section,
	min_v: float = 0.001,
	max_v: float = 100.0,
	step_v: float = 0.001
) -> CuratorFieldSpec:
	var s := CuratorFieldSpec.new()
	s.property = property
	s.label = label
	s.section = section
	s.ui = UiKind.VECTOR2
	s.min_value = min_v
	s.max_value = max_v
	s.step = step_v
	return s
