// =============================================================================
// SHADER FILE: vignette.gdshader
// APPLIED TO: The "VignetteRect" ColorRect node inside the HUD CanvasLayer
// =============================================================================
//
// OVERVIEW
// --------
// This is a SHADER — a small program that runs directly on the GPU (Graphics
// Processing Unit, the graphics card) rather than on the CPU (the main processor).
// Shaders are written in a special language designed for this purpose. Godot uses
// a language called "Godot Shading Language," which is very similar to GLSL
// (OpenGL Shading Language) — the industry-standard shader language.
//
// WHAT DOES THIS SHADER DO?
// It creates a "vignette" — a darkening effect at the edges of the screen that
// gets more intense as the ranger's suspicion rises. At 0 suspicion, the screen
// looks normal. As suspicion climbs toward 100, the screen edges darken to a
// deep red, creating a feeling of danger closing in.
//
// WHERE IS IT USED?
// This shader is attached as a ShaderMaterial to VignetteRect — a ColorRect
// (a flat 2D rectangle) that covers the ENTIRE screen. The rectangle itself is
// invisible by default (its alpha starts at 0), but this shader draws a
// semi-transparent red gradient on it.
//
// HOW IS IT CONTROLLED FROM GDSCRIPT?
// ranger.gd reads the current suspicion value and calls:
//   _vignette_mat.set_shader_parameter("intensity", suspicion / 100.0 * 0.65)
// This changes the "intensity" uniform variable in this shader each frame,
// making the vignette darker when suspicion is high.
//
// COMMENTS IN SHADER FILES:
// Shader files use C-style comments: // for single-line, /* */ for multi-line.
// GDScript uses # for comments. Both mean the same thing — text ignored by the computer.
//
// HOW SHADERS ARE DIFFERENT FROM GDSCRIPT:
// GDScript runs on the CPU, once per frame, sequentially.
// A shader runs on the GPU, once per PIXEL, massively in parallel.
// If the screen is 1920×1080, this fragment shader runs 2,073,600 times every frame —
// once for each individual pixel. But because GPUs have thousands of cores,
// all those pixels are computed simultaneously.
// The shader doesn't "loop over pixels" — it IS the code for ONE pixel,
// and the GPU runs it in parallel for every pixel at once.

// =============================================================================
// LINE 1 — SHADER TYPE DECLARATION
// =============================================================================

// "shader_type" tells Godot what KIND of shader this is.
// There are several types:
//   spatial      — for 3D objects in the world (affected by lighting, depth, etc.)
//   canvas_item  — for 2D objects / UI elements (flat, drawn on screen)
//   particles    — for controlling particle behaviour on the GPU
//   sky          — for drawing the background sky
//
// We use "canvas_item" because this shader is on a 2D UI element (a ColorRect
// that sits on top of the 3D scene as a HUD overlay). It doesn't exist in 3D space
// — it's drawn directly onto the screen in 2D coordinates.
//
// Choosing the wrong shader_type would cause Godot to reject the shader entirely,
// because different types have access to different built-in variables and functions.
shader_type canvas_item;

// =============================================================================
// LINE 3 — UNIFORM VARIABLE: The bridge between GDScript and the shader
// =============================================================================

// A "uniform" is a variable that is set FROM OUTSIDE the shader (from GDScript)
// and stays the same ("uniform") for ALL pixels during one rendering pass.
//
// WHY IS IT CALLED "UNIFORM"?
// Unlike the UV coordinates (which are different for every pixel), a uniform
// has ONE value for the entire draw call. It's "uniformly" the same everywhere.
//
// "float" means this is a floating-point number (can have decimal places).
//
// "intensity" is the name. We refer to this name in two places:
//   1. Inside this shader (line 8): used to scale the vignette darkness.
//   2. In GDScript (ranger.gd): _vignette_mat.set_shader_parameter("intensity", value)
//      The string "intensity" must exactly match this name.
//
// ": hint_range(0.0, 1.0)" is a HINT — optional metadata for the Godot Editor.
// hint_range tells the Inspector to show a SLIDER for this uniform, constrained
// between 0.0 and 1.0. It doesn't enforce limits in code — just an editor aid.
// 0.0 = no vignette (fully transparent), 1.0 = maximum vignette.
//
// "= 0.0" is the DEFAULT value. When the scene first loads (before ranger.gd
// sets anything), intensity starts at 0 — the screen looks completely normal.
uniform float intensity : hint_range(0.0, 1.0) = 0.0;

// =============================================================================
// LINES 5–10 — THE FRAGMENT FUNCTION: Runs once per pixel
// =============================================================================

// "void fragment()" is the FRAGMENT SHADER function.
// In GPU programming, a "fragment" is essentially one pixel being drawn.
// This function is called by the GPU for every single pixel covered by the
// VignetteRect. The function's job is to decide: what color should THIS pixel be?
//
// "void" means the function doesn't return a value the traditional way.
// Instead, it writes to a special built-in output variable called "COLOR"
// (line 9) to set the pixel's final color.
//
// BUILT-IN VARIABLES AVAILABLE IN A canvas_item FRAGMENT SHADER:
//   UV     — The current pixel's texture coordinate (explained below).
//   COLOR  — OUTPUT: write the desired RGBA color here to set the pixel color.
//   (Many others exist but aren't used in this simple shader.)

void fragment() {

	// ── LINE 6: RECENTRE THE UV COORDINATES ────────────────────────────────

	// WHAT IS UV?
	// "UV" (sometimes called "texture coordinates") is a 2D coordinate that
	// represents WHERE on the shape this pixel is located — but as a fraction,
	// not in pixels.
	//
	// For a 2D rectangle (like our VignetteRect):
	//   UV = (0.0, 0.0) at the TOP-LEFT corner
	//   UV = (1.0, 0.0) at the TOP-RIGHT corner
	//   UV = (0.0, 1.0) at the BOTTOM-LEFT corner
	//   UV = (1.0, 1.0) at the BOTTOM-RIGHT corner
	//   UV = (0.5, 0.5) at the dead CENTRE
	//
	// REAL-WORLD ANALOGY: Imagine a map of a room. The coordinates go from
	// (0,0) at the corner to (1,1) at the opposite corner. Any point in the room
	// can be described as a fraction of the room's total size.
	//
	// WHY SUBTRACT vec2(0.5)?
	// The built-in UV has its ORIGIN (0, 0) at the top-left. But for a circular
	// vignette, we want the ORIGIN at the CENTRE of the screen.
	// Subtracting (0.5, 0.5) shifts the coordinate system:
	//   Old UV (0.5, 0.5) = centre → New uv (0.0, 0.0) = centre ✓
	//   Old UV (0.0, 0.0) = top-left → New uv (-0.5, -0.5) = top-left ✓
	//   Old UV (1.0, 1.0) = bottom-right → New uv (0.5, 0.5) = bottom-right ✓
	// Now (0, 0) is the centre, and all edges are at distance 0.5 from centre.
	// This makes it easy to create a circular effect — we just measure distance
	// from (0, 0) and that IS the distance from the screen centre.
	//
	// "vec2" is the shader type for a 2D vector (two floats: x and y).
	// "vec2(0.5)" creates the vector (0.5, 0.5) — a shorthand where one value
	// fills both components.
	vec2 uv = UV - vec2(0.5);

	// ── LINE 7: CALCULATE DISTANCE FROM CENTRE (WITH ASPECT RATIO FIX) ─────

	// "length()" computes the length of a 2D vector — the distance from (0,0).
	// For a vector (x, y): length = sqrt(x² + y²)
	// This is the 2D Pythagorean theorem. The result is the distance from the
	// pixel to the screen centre in "UV space" (0.0 = centre, ~0.7 = corner).
	//
	// BUT WAIT — WHY MULTIPLY BY vec2(1.0, 1.778)?
	// Screens are not square. A typical 16:9 screen is 1.778 times wider than tall.
	// (16 ÷ 9 ≈ 1.778)
	//
	// Without this correction, the "circle" of the vignette would actually be
	// an ELLIPSE — squashed vertically — because UV coordinates treat the
	// rectangle as if it were square (0 to 1 in both directions regardless of
	// the screen's actual pixel dimensions).
	//
	// EXAMPLE WITHOUT CORRECTION:
	//   Screen pixel (960, 540) = centre → UV (0.5, 0.5) → recentred (0, 0)
	//   Screen pixel (960, 0) = top-centre → UV (0.5, 0) → recentred (0, -0.5)
	//   Screen pixel (1920, 540) = right-centre → UV (1, 0.5) → recentred (0.5, 0)
	//   distance from top-centre = 0.5. Distance from right-centre = 0.5.
	//   They appear the SAME distance away in UV space, even though the top-centre
	//   pixel is only 540 pixels from centre and the right-centre is 960 pixels away.
	//   The vignette would be stronger at the sides than at the top/bottom —
	//   which is visually wrong.
	//
	// EXAMPLE WITH CORRECTION (multiply Y by 1.778):
	//   Recentred (0, -0.5) → after multiply: (0 * 1.0, -0.5 * 1.778) = (0, -0.889)
	//   Recentred (0.5, 0) → after multiply: (0.5 * 1.0, 0 * 1.778) = (0.5, 0)
	//   distance from top: 0.889. Distance from right: 0.5.
	//   Now the top/bottom distance is proportionally larger, compensating for the
	//   fact that those edges are PHYSICALLY farther in pixel terms.
	//   The vignette circle now appears truly circular on screen. ✓
	//
	// "vec2(1.0, 1.778)" is the aspect ratio correction vector.
	// Component-wise multiplication: (uv.x * 1.0, uv.y * 1.778)
	float d = length(uv * vec2(1.0, 1.778));

	// ── LINE 8: CALCULATE VIGNETTE OPACITY AT THIS PIXEL ───────────────────

	// "smoothstep(edge0, edge1, x)" is a built-in shader function that performs
	// smooth interpolation between two values.
	//
	// HOW smoothstep WORKS:
	//   If x <= edge0: returns 0.0 (completely below the range → no effect)
	//   If x >= edge1: returns 1.0 (completely above the range → full effect)
	//   Between edge0 and edge1: returns a smooth S-curve value between 0 and 1.
	//
	// THE "S-CURVE" (also called Hermite interpolation):
	// Regular linear interpolation goes from 0 to 1 in a straight line — it looks
	// mechanical. smoothstep uses the formula: 3t² - 2t³, which creates a curve
	// that starts slow, accelerates in the middle, then slows again at the end.
	// This creates gradients that look natural rather than abrupt.
	//
	// WHAT DOES IT MEAN HERE?
	// smoothstep(0.25, 0.65, d):
	//   When d < 0.25 (within the central 25% radius): returns 0.0 → no vignette.
	//   When d > 0.65 (beyond 65% from centre): returns 1.0 → full vignette color.
	//   Between 0.25 and 0.65: smooth S-curve transition.
	//
	// In visual terms:
	//   The centre of the screen is completely clear (d is small → smoothstep = 0).
	//   The extreme corners are fully darkened (d is large → smoothstep ≈ 1).
	//   The area between looks like a smooth, natural gradient.
	//
	// THEN MULTIPLY BY intensity:
	//   If intensity = 0.0 (ranger is calm): v = 0 → pixel is fully transparent.
	//   If intensity = 0.65 (near-max from ranger.gd's 0.65 cap):
	//     v = smoothstep result * 0.65 → corners darken noticeably.
	//   This scales the ENTIRE vignette up or down based on danger level.
	//
	// "float v" stores the final alpha (opacity) for this pixel's vignette layer.
	float v = smoothstep(0.25, 0.65, d) * intensity;

	// ── LINE 9: SET THE PIXEL'S FINAL COLOR ────────────────────────────────

	// "COLOR" is the built-in output variable of a fragment shader.
	// Assigning to it sets the final color of this pixel.
	//
	// "vec4(r, g, b, a)" creates a 4-component color vector:
	//   r = Red   component (0.0 to 1.0)
	//   g = Green component (0.0 to 1.0)
	//   b = Blue  component (0.0 to 1.0)
	//   a = Alpha component (0.0 = fully transparent, 1.0 = fully opaque)
	//
	// vec4(0.8, 0.0, 0.0, v):
	//   R = 0.8 — strong red (slightly less than full 1.0 to avoid harsh brightness)
	//   G = 0.0 — no green
	//   B = 0.0 — no blue
	//   A = v   — opacity controlled by the smoothstep result above
	//
	// RESULT: A dark reddish tint at the screen edges. Near the centre, v ≈ 0
	// so the pixel is nearly transparent (you see the game through it). At the
	// corners, v approaches "intensity" (up to 0.65) so the corner pixels are
	// 65% opaque dark red — a sinister red border framing the screen.
	//
	// WHY DARK RED SPECIFICALLY?
	// Red is universally associated with danger. A darkening red border signals
	// to the player: "the ranger is suspicious, you are in danger." It creates
	// psychological urgency without text or UI interruption — pure visual language.
	COLOR = vec4(0.8, 0.0, 0.0, v);
}

// =============================================================================
// EXECUTION FLOW SUMMARY (Per-Pixel, Every Frame)
// =============================================================================
//
// EVERY FRAME, FOR EVERY PIXEL ON THE SCREEN:
//
//   1. The GPU calls this fragment() function for this pixel.
//   2. UV gives the pixel's position as a 0–1 fraction across the rectangle.
//   3. Subtract (0.5, 0.5) to recentre the coordinate system at the screen centre.
//   4. Multiply by the aspect ratio correction (1.0, 1.778) to compensate for
//      the screen being wider than tall — keeps the vignette circular.
//   5. Compute the distance from centre using the Pythagorean theorem (length()).
//   6. smoothstep maps that distance to a 0–1 vignette strength:
//        - Centre pixels: 0 (clear)
//        - Edge/corner pixels: approaches 1 (full vignette)
//        - In-between: smooth S-curve gradient
//   7. Multiply by "intensity" (set from GDScript) to scale the effect with danger.
//   8. Write a dark red color with that alpha value to COLOR.
//
// HOW THE DANGER ESCALATION LOOKS TO THE PLAYER:
//   Suspicion 0%:   intensity = 0.00 → screen looks completely normal
//   Suspicion 40%:  intensity = 0.26 → faint red shadow at far corners
//   Suspicion 70%:  intensity = 0.46 → visible dark red border on all sides
//   Suspicion 100%: intensity = 0.65 → strong dark red vignette, alarming
//   (Caught at 100% suspicion — the caught sound and screen shake happen simultaneously)
//
// GLOSSARY OF SHADER TERMS USED:
//   uniform   — A variable passed IN from GDScript, same value for all pixels.
//   vec2      — A 2D vector: two floats (x, y). Used for UV coordinates here.
//   vec4      — A 4D vector: four floats (r, g, b, a). Used for color.
//   float     — A single floating-point number.
//   UV        — Built-in: this pixel's position on the shape (0,0 to 1,1).
//   COLOR     — Built-in OUTPUT: write the pixel's final color here.
//   length()  — Built-in: returns the magnitude of a vector (Pythagorean distance).
//   smoothstep() — Built-in: S-curve interpolation between two edges.
