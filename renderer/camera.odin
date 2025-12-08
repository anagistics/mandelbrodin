package renderer

import "core:math"
import "core:math/linalg"

// 3D camera for orbital viewing
Camera_3D :: struct {
	// Orbital parameters
	azimuth:   f32, // Rotation around Y axis (horizontal) in degrees
	elevation: f32, // Rotation around X axis (vertical) in degrees
	distance:  f32, // Distance from target

	// Target point (center of view)
	target: [3]f32,

	// Derived (computed from orbital parameters)
	position: [3]f32,

	// Matrices
	view_matrix: matrix[4, 4]f32,
	proj_matrix: matrix[4, 4]f32,

	// Projection parameters
	fov:         f32, // Field of view in degrees
	aspect:      f32, // Aspect ratio (width/height)
	near_plane:  f32, // Near clipping plane
	far_plane:   f32, // Far clipping plane

	// Smooth interpolation
	target_azimuth:   f32,
	target_elevation: f32,
	target_distance:  f32,
}

// Initialize camera with default values
Init_Camera_3D :: proc(camera: ^Camera_3D, aspect: f32, scene_width: f32 = 800, scene_height: f32 = 600) {
	camera.azimuth = 45.0
	camera.elevation = 30.0

	// Calculate distance to fit the scene in view
	// For a 60-degree FOV, distance = (scene_size / 2) / tan(30°)
	// We use the larger dimension and add some margin
	max_dimension := max(scene_width, scene_height)
	camera.distance = max_dimension * 1.2 // 1.2x for comfortable margin

	camera.target = {0, 0, 0}

	camera.fov = 60.0
	camera.aspect = aspect
	camera.near_plane = 0.1
	camera.far_plane = 10000.0  // Increased for larger scenes

	// Initialize interpolation targets to current values
	camera.target_azimuth = camera.azimuth
	camera.target_elevation = camera.elevation
	camera.target_distance = camera.distance

	Update_Camera_3D(camera, 0)
}

// Update camera matrices from orbital parameters
Update_Camera_3D :: proc(camera: ^Camera_3D, dt: f32) {
	// Smooth interpolation (exponential decay)
	lerp_factor := 1.0 - math.exp(-10.0 * dt)

	camera.azimuth = camera.azimuth + (camera.target_azimuth - camera.azimuth) * lerp_factor
	camera.elevation =
		camera.elevation + (camera.target_elevation - camera.elevation) * lerp_factor
	camera.distance = camera.distance + (camera.target_distance - camera.distance) * lerp_factor

	// Clamp elevation to prevent gimbal lock
	camera.elevation = clamp(camera.elevation, -89.0, 89.0)

	// Clamp distance to reasonable range (allow larger distances for big scenes)
	camera.distance = clamp(camera.distance, 10.0, 5000.0)

	// Convert spherical coordinates to Cartesian
	rad_azimuth := math.to_radians(camera.azimuth)
	rad_elevation := math.to_radians(camera.elevation)

	camera.position.x =
		camera.target.x +
		camera.distance * math.cos(rad_elevation) * math.sin(rad_azimuth)
	camera.position.y = camera.target.y + camera.distance * math.sin(rad_elevation)
	camera.position.z =
		camera.target.z +
		camera.distance * math.cos(rad_elevation) * math.cos(rad_azimuth)

	// Create view matrix (look at target from position)
	up := [3]f32{0, 1, 0}
	camera.view_matrix = linalg.matrix4_look_at_f32(
		camera.position,
		camera.target,
		up,
	)

	// Create projection matrix
	camera.proj_matrix = linalg.matrix4_perspective_f32(
		math.to_radians(camera.fov),
		camera.aspect,
		camera.near_plane,
		camera.far_plane,
	)
}

// Reset camera to default view
Reset_Camera_3D :: proc(camera: ^Camera_3D, scene_width: f32 = 800, scene_height: f32 = 600) {
	camera.target_azimuth = 45.0
	camera.target_elevation = 30.0

	// Reset to comfortable viewing distance based on scene size
	max_dimension := max(scene_width, scene_height)
	camera.target_distance = max_dimension * 1.2

	camera.target = {0, 0, 0}
}

// Rotate camera (add to current rotation)
Rotate_Camera_3D :: proc(camera: ^Camera_3D, delta_azimuth, delta_elevation: f32) {
	camera.target_azimuth += delta_azimuth
	camera.target_elevation += delta_elevation

	// Wrap azimuth to [0, 360]
	for camera.target_azimuth < 0 {
		camera.target_azimuth += 360.0
	}
	for camera.target_azimuth >= 360.0 {
		camera.target_azimuth -= 360.0
	}

	// Clamp elevation to prevent gimbal lock
	camera.target_elevation = clamp(camera.target_elevation, -89.0, 89.0)
}

// Zoom camera (change distance)
Zoom_Camera_3D :: proc(camera: ^Camera_3D, delta: f32) {
	camera.target_distance *= 1.0 + delta

	// Clamp to reasonable range (allow larger distances for big scenes)
	camera.target_distance = clamp(camera.target_distance, 10.0, 5000.0)
}

// Pan camera (move target)
Pan_Camera_3D :: proc(camera: ^Camera_3D, delta_x, delta_y: f32) {
	// Convert screen-space delta to world-space delta
	// This requires computing the camera's right and up vectors

	// Forward vector (from camera to target)
	forward := linalg.normalize(camera.target - camera.position)

	// Right vector (perpendicular to forward and world up)
	world_up := [3]f32{0, 1, 0}
	right := linalg.normalize(linalg.cross(forward, world_up))

	// Up vector (perpendicular to forward and right)
	up := linalg.cross(right, forward)

	// Move target in screen-space
	pan_speed := camera.distance * 0.001 // Scale with distance
	camera.target += right * delta_x * pan_speed
	camera.target += up * delta_y * pan_speed
}

// Get VP matrix (View * Projection)
Get_VP_Matrix :: proc(camera: ^Camera_3D) -> matrix[4, 4]f32 {
	return camera.proj_matrix * camera.view_matrix
}
