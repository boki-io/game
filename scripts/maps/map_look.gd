class_name MapLook
extends RefCounted
## The two look values that live outside the drawn classes (spec 0.6 sections 8.1 and 8.5), for `MapBuilder` to call:
## the vignette's edge darkness and the world's ambient tint. Null theme: today's values (0.62 and white).

const DEFAULT_VIGNETTE := 0.62


## The vignette's edge alpha for `theme`.
static func vignette_alpha(theme: MapTheme) -> float:
	return DEFAULT_VIGNETTE if theme == null else theme.vignette


## Sets the outer stop of a vignette TextureRect's GradientTexture2D to the theme's darkness. Returns false when
## `rect` has no such gradient (nothing is changed). The gradient is copied first, so the scene's shared resource
## (and the hub, which uses its own) keeps its value.
static func apply_vignette(rect: TextureRect, theme: MapTheme) -> bool:
	var tex := rect.texture as GradientTexture2D
	if tex == null or tex.gradient == null or tex.gradient.get_point_count() < 2:
		return false
	var gradient: Gradient = tex.gradient.duplicate()
	var last := gradient.get_point_count() - 1
	var c := gradient.get_color(last)
	c.a = vignette_alpha(theme)
	gradient.set_color(last, c)
	var copy: GradientTexture2D = tex.duplicate()
	copy.gradient = gradient
	rect.texture = copy
	return true


## The ambient tint for `theme`: white with no theme.
static func ambient_color(theme: MapTheme) -> Color:
	return Color.WHITE if theme == null else theme.ambient


## Adds (or updates, when `parent` already has one named "Ambient") a CanvasModulate that tints the world.
## Put it in the world's canvas, not on the UI CanvasLayer's, so the HUD, menus and vignette stay untinted.
static func apply_ambient(parent: Node, theme: MapTheme) -> CanvasModulate:
	var mod := parent.get_node_or_null("Ambient") as CanvasModulate
	if mod == null:
		mod = CanvasModulate.new()
		mod.name = "Ambient"
		parent.add_child(mod)
	mod.color = ambient_color(theme)
	return mod
