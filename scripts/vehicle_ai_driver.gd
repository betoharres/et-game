class_name VehicleAIDriver
extends Node

## Wanders a road graph: at every junction it takes a random street that is not
## the one it came from, so a patrol keeps turning into different blocks. See
## driveable_truck.gd, which calls get_control_input() from _update_driving()
## whenever the vehicle isn't player-controlled, so throttle and steering go
## through the same physics path the player's input uses.
##
## `road_nodes` are the centres of the drivable road tiles. They sit on a
## regular grid, so the links between them are derived from their spacing
## instead of being authored by hand.

@export var road_nodes: Array[Vector3] = []

## How many nodes of the chosen way ahead are kept as the path to follow. The
## car steers along this rolling polyline and refills it as it advances.
@export var path_nodes: int = 4
## A branch shorter than this many tiles is treated as a nub and skipped while
## another street is available, so the car doesn't dive into every little stub.
@export var min_branch_cells: int = 3

## Cruise speed on a straight, in m/s. The AI brakes with reverse engine force
## when it runs faster than this, so it never accelerates itself into a slide.
@export var cruise_speed: float = 9.0
## Speed asked for in a tight corner and while turning around. Kept low: the
## turnaround has little room before the curb, and a slow approach means the
## car isn't still carrying much forward speed at the instant it flips into
## reverse (a hard reversal against real forward speed, at this car's high
## tyre grip, is what was pitching it into the curb hard enough to tunnel
## through the sidewalk collision).
@export var corner_speed: float = 3.0
## Speed error (m/s) that saturates the throttle.
@export var speed_control_band: float = 3.0

## Pure pursuit aims this far down the path, plus a slice of the current speed:
## a fixed short look-ahead oscillates (and clips curbs) as the car speeds up,
## while looking further than a tile cuts the corners at junctions.
@export var min_look_ahead: float = 5.0
@export var look_ahead_per_speed: float = 0.6
@export var max_look_ahead: float = 10.0

@export var max_steering_angle_deg: float = 35.0
## Above this speed the steering output is scaled down, so the same heading
## error doesn't throw the car sideways at speed.
@export var steering_calm_speed: float = 8.0
@export var min_steering_scale: float = 0.35
## Steering is normally commanded in [-1, 1], the scale Input.get_axis gives.
## Below `maneuver_speed` the AI may ask for more, which the vehicle turns into
## extra lock: a car uses its parking lock to turn around, and a U-turn at
## cruise lock is wider than the street.
@export var maneuver_steering_limit: float = 1.4
@export var maneuver_speed: float = 5.0
## A real car cutting a sharp 90 degree corner necessarily strays from the
## L-shaped path centre line for a moment, and its heading error genuinely
## spikes past 90 degrees while it does - both a lateral-offset trigger and a
## heading-error trigger tried here fired constantly at routine corners, not
## just at dead ends, and reversing there just added risk (backing blind
## toward whatever was behind it) for no benefit, since forward steering
## handles an ordinary corner fine on its own.
##
## So the three-point turn is gated on road topology instead of a heuristic:
## `_pick_next()` marks a dead end when a street has nowhere to go but back
## the way it came, which shows up in the path as an A-B-A cusp (see
## `_dead_end_distance` below). Only near that specific point does a large
## heading error mean "the path wants a turn tighter than the street has" -
## everywhere else it just means an ordinary corner, and is left to steering.
@export var turn_trigger_angle_deg: float = 100.0
## Heading error the car must be back under before it resumes driving forward.
@export var turn_release_angle_deg: float = 25.0
## How close to the dead-end cusp (arc length along the path, in metres) the
## reverse-out logic is even considered.
@export var dead_end_proximity: float = 9.0

@export var stuck_speed_threshold: float = 0.5
@export var stuck_time_threshold: float = 1.5
@export var stuck_unstick_duration: float = 1.0
## Reverse throttle is capped well under full power (unlike driving forward):
## backing blind into unseen street furniture (a lamp post, a bench) at full
## reverse force, with this car's very grippy tyres, is what was catching a
## wheel and levering the whole chassis into a flip instead of just scraping.
@export var max_reverse_throttle: float = 0.35

## Safety net for whatever the two guards above don't catch. If the chassis
## stays tipped past this (degrees from upright) or ends up this far under the
## nearest road tile, something has gone wrong (wedged on a prop, fell off the
## road) and it teleports back onto the grid instead of tumbling or falling
## forever. The angle is low on purpose: normal driving (with roll influence
## already turned down on this chassis) never tips this far, so the only way
## to reach it is genuinely climbing onto something, and catching it early
## means less angular momentum has built up for the brake below to arrest.
@export var recovery_tilt_deg: float = 35.0
@export var recovery_tilt_duration: float = 0.6
@export var recovery_fall_depth: float = 4.0
## Brake force applied directly the instant a tilt is caught. Zeroing the
## engine alone leaves the wheels freewheeling, which doesn't stop a chassis
## that's already rolling on contact with whatever it climbed onto.
@export var recovery_brake_force: float = 60.0
## Last-resort watchdog: if the car hasn't moved this many metres in this many
## seconds, it's wedged against something small enough that neither the stuck
## detector's forward/reverse pulses nor the tilt guard ever trip (rocking in
## place against a lamp post did exactly this - upright the whole time, so the
## tilt guard never saw it, and each pulse gained just enough ground to reset
## the short-timeout stuck detector before the next stuck-check could fire).
@export var stuck_progress_radius: float = 3.0
@export var stuck_progress_timeout: float = 8.0

## Fan of raycasts checked behind the car while it backs up (see `_backing_up`
## below) - the one manoeuvre where the AI commits to a heading and reverses
## into ground it hasn't looked at. Same idea as the "lidar" steering bias in
## hsaikia/GodotDriver: each ray pushes steering away from it, weighted by how
## close the hit is, so a lamp post a metre off centre is scraped past instead
## of driven into square. This fixes the cause rather than just the fallout the
## guards above catch: it stops the wheel from getting caught in the first
## place, in the specific manoeuvre that was catching it.
@export var obstacle_sensor_count: int = 5
@export var obstacle_sensor_fov_deg: float = 55.0
@export var obstacle_sensor_range: float = 5.0
@export var obstacle_sensor_mask: int = 1
@export var obstacle_avoidance_steering_weight: float = 1.2

var _vehicle: VehicleBody3D = null
var _tilt_timer: float = 0.0
var _progress_anchor: Vector3 = Vector3.ZERO
var _progress_anchor_set: bool = false
var _progress_timer: float = 0.0

var _links: Array[PackedInt32Array] = []
var _path_indices: PackedInt32Array = PackedInt32Array()
var _path: Array[Vector3] = []
var _cumulative_distances: Array[float] = []
var _total_length: float = 0.0
## Arc length (along `_path`) of a dead-end cusp if the current path window
## contains one, else negative: see `turn_trigger_angle_deg` above.
var _dead_end_distance: float = -1.0

var _stuck_timer: float = 0.0
## The unstick pulse: throttle can be either sign here, since being jammed
## while reversing is escaped by pulling forward and vice versa.
var _unstick_timer: float = 0.0
var _unstick_throttle: float = 0.0
var _unstick_steering: float = 0.0
var _last_steering: float = 0.0
var _backing_up: bool = false


func _ready() -> void:
	_vehicle = get_parent() as VehicleBody3D
	_build_links()


## Two nodes are linked when they are one grid step apart. The step is read off
## the data (the closest pair) so the graph survives a different tile size.
func _build_links() -> void:
	_links.clear()

	var count : int = road_nodes.size()
	for _index : int in count:
		_links.append(PackedInt32Array())

	if count < 2:
		return

	var step : float = INF
	for first : int in count:
		for second : int in range(first + 1, count):
			step = minf(step, road_nodes[first].distance_to(road_nodes[second]))

	# A diagonal is 1.41 steps away, so 1.3 separates neighbours cleanly.
	var link_distance : float = step * 1.3
	for first : int in count:
		for second : int in range(first + 1, count):
			if road_nodes[first].distance_to(road_nodes[second]) <= link_distance:
				_links[first].append(second)
				_links[second].append(first)


## Returns (throttle, steering), both in the scale Input.get_axis produces.
func get_control_input(
	position : Vector3,
	vehicle_transform : Transform3D,
	velocity : Vector3
) -> Vector2:
	if road_nodes.size() < 2:
		return Vector2.ZERO

	var delta : float = get_physics_process_delta_time()

	var up_dot : float = vehicle_transform.basis.y.dot(Vector3.UP)

	# The moment the chassis tips past the threshold, stop feeding it torque:
	# a wheel caught on a curb or a prop only flips over if the engine keeps
	# pushing against it after it's already lost the ground. This is the guard
	# that would have arrested the flip that used to send the car through the
	# map, before the recovery teleport below is ever needed.
	if up_dot < cos(deg_to_rad(recovery_tilt_deg)):
		_tilt_timer += delta
		if _tilt_timer > recovery_tilt_duration:
			_recover(position)
			return Vector2.ZERO
		# Set straight on the body rather than returned: driveable_truck.gd
		# clears brake before asking for input and never touches it after, so
		# this holds for the frame and is cleared again on the next one.
		if _vehicle != null:
			_vehicle.brake = recovery_brake_force
		return Vector2(0.0, 0.0)
	_tilt_timer = 0.0

	# Backstop for anything the tilt guard doesn't catch (fell off the road
	# entirely without tipping over, for instance): a large drop below the
	# nearest road tile also gets teleported back.
	var nearest_index : int = _nearest_node(position)
	if nearest_index >= 0 and road_nodes[nearest_index].y - position.y > recovery_fall_depth:
		_recover(position)
		return Vector2.ZERO

	if not _progress_anchor_set:
		_progress_anchor = position
		_progress_anchor_set = true
	elif _flat_distance(position, _progress_anchor) > stuck_progress_radius:
		_progress_anchor = position
		_progress_timer = 0.0
	else:
		_progress_timer += delta
		if _progress_timer > stuck_progress_timeout:
			_recover(position)
			return Vector2.ZERO

	# The vehicle drives toward its local +Z (verified against VehicleBody3D:
	# a positive engine_force moves it that way), so that is "forward" here.
	var forward : Vector3 = vehicle_transform.basis.z
	forward.y = 0.0

	if forward.length_squared() < 0.0001:
		return Vector2.ZERO

	forward = forward.normalized()

	if _path.size() < 2:
		_seed_path(position, forward)
		if _path.size() < 2:
			return Vector2.ZERO

	# Signed speed along the nose: braking and reversing need the sign, an
	# unsigned magnitude would read a reversing car as "too fast forward".
	var forward_speed : float = velocity.dot(forward)
	var flat_speed : float = Vector3(velocity.x, 0.0, velocity.z).length()

	if _unstick_timer > 0.0:
		_unstick_timer -= delta
		return Vector2(_unstick_throttle, _unstick_steering)

	if flat_speed < stuck_speed_threshold:
		_stuck_timer += delta
		if _stuck_timer > stuck_time_threshold:
			_stuck_timer = 0.0
			_unstick_timer = stuck_unstick_duration
			# Jammed while already backing up (the case that used to grind the
			# wheel against a lamp post or a curb forever): pull forward off
			# it instead of reversing harder into the very thing it hit.
			# Otherwise reverse, same as backing off something ahead of it.
			if _backing_up:
				_backing_up = false
				_unstick_throttle = max_reverse_throttle
				_unstick_steering = _last_steering
			else:
				_unstick_throttle = -max_reverse_throttle
				# Opposite lock while backing up keeps rotating the car the
				# way it was already trying to turn, like a three-point turn.
				_unstick_steering = -_last_steering
			return Vector2(_unstick_throttle, _unstick_steering)
	else:
		_stuck_timer = 0.0

	# Project the car onto the closest point of the path first: if a collision
	# pushed it off the road, the next target is picked from where it actually
	# is, not from a node it lost.
	var route_distance : float = _closest_route_distance(position)
	route_distance = _advance_path(position, route_distance)

	var look_ahead : float = clampf(
		min_look_ahead + maxf(forward_speed, 0.0) * look_ahead_per_speed,
		min_look_ahead,
		max_look_ahead
	)

	var target : Vector3 = _point_at_distance(
		clampf(route_distance + look_ahead, 0.0, _total_length)
	)

	var to_target : Vector3 = target - position
	to_target.y = 0.0

	if to_target.length() < 0.05:
		return Vector2(0.0, 0.0)

	var target_direction : Vector3 = to_target.normalized()

	var cross_y : float = forward.cross(target_direction).y
	var forward_dot : float = forward.dot(target_direction)
	var signed_angle : float = atan2(cross_y, forward_dot)

	var steering_limit : float = (
		maneuver_steering_limit
		if absf(forward_speed) < maneuver_speed
		else 1.0
	)

	var steering : float = clampf(
		signed_angle / deg_to_rad(max_steering_angle_deg),
		-steering_limit,
		steering_limit
	)

	# Same heading error means far less lock at speed, otherwise the car
	# oscillates around the centre line and slaps the curbs.
	steering *= clampf(
		steering_calm_speed / maxf(absf(forward_speed), steering_calm_speed),
		min_steering_scale,
		1.0
	)

	_last_steering = steering

	var angle_deg : float = rad_to_deg(absf(signed_angle))

	# Turning right around takes more road than the ~9 m-wide street has (the
	# curb sits only 4.5 m off the centre line), so near a genuine dead end
	# (see `_dead_end_distance`) the car backs out instead of trying to
	# complete a wide forward loop. Gated on actually being close to the cusp:
	# a heading-error spike far from any dead end is just an ordinary corner,
	# which plain forward steering already handles.
	var near_dead_end : bool = (
		_dead_end_distance >= 0.0
		and absf(route_distance - _dead_end_distance) < dead_end_proximity
	)
	if near_dead_end and angle_deg > turn_trigger_angle_deg:
		_backing_up = true
	elif angle_deg < turn_release_angle_deg or not near_dead_end:
		_backing_up = false

	if _backing_up:
		var avoidance : Vector2 = _obstacle_avoidance(position, -forward)
		var avoidance_bias : float = avoidance.x
		var clearance : float = avoidance.y

		var reverse_throttle : float = clampf(
			(-corner_speed - forward_speed) / speed_control_band,
			-max_reverse_throttle,
			1.0
		)
		# Ease off the closer something gets behind the car, on top of the cap
		# already on reverse power - a near miss should slow the car down, not
		# just steer around it at full speed.
		reverse_throttle *= lerpf(0.35, 1.0, clearance)

		var avoidance_steering : float = clampf(
			-steering + avoidance_bias * obstacle_avoidance_steering_weight,
			-steering_limit,
			steering_limit
		)
		return Vector2(reverse_throttle, avoidance_steering)

	var corner_blend : float = clampf(angle_deg / 45.0, 0.0, 1.0)
	var desired_speed : float = lerpf(cruise_speed, corner_speed, corner_blend)

	var throttle : float = clampf(
		(desired_speed - forward_speed) / speed_control_band,
		-1.0,
		1.0
	)

	return Vector2(throttle, steering)


## Casts a fan of rays toward `sensor_direction` (the back of the car, while
## reversing) and returns (steering bias away from the closest hit, clearance),
## where clearance is 1.0 for nothing in range and 0.0 for right on top of it.
func _obstacle_avoidance(position : Vector3, sensor_direction : Vector3) -> Vector2:
	if _vehicle == null:
		return Vector2(0.0, 1.0)

	var space_state : PhysicsDirectSpaceState3D = _vehicle.get_world_3d().direct_space_state
	var origin : Vector3 = position + Vector3.UP * 0.6
	var excluded : Array[RID] = [_vehicle.get_rid()]

	var weighted_angle : float = 0.0
	var weight_total : float = 0.0
	var nearest_ratio : float = 1.0

	for index : int in obstacle_sensor_count:
		var t : float = (
			float(index) / float(obstacle_sensor_count - 1)
			if obstacle_sensor_count > 1
			else 0.5
		)
		var angle_deg : float = lerpf(-obstacle_sensor_fov_deg, obstacle_sensor_fov_deg, t)
		var ray_direction : Vector3 = sensor_direction.rotated(Vector3.UP, deg_to_rad(angle_deg))

		var query : PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			origin,
			origin + ray_direction * obstacle_sensor_range
		)
		query.collision_mask = obstacle_sensor_mask
		query.exclude = excluded

		var hit : Dictionary = space_state.intersect_ray(query)
		if hit.is_empty():
			continue

		var distance_ratio : float = clampf(
			origin.distance_to(hit.position) / obstacle_sensor_range,
			0.0,
			1.0
		)
		nearest_ratio = minf(nearest_ratio, distance_ratio)

		# Weighted toward whichever ray is closest, so one near miss dominates
		# instead of averaging away against several far-off readings.
		var push : float = pow(1.0 - distance_ratio, 2.0)
		weighted_angle += -angle_deg * push
		weight_total += push

	var steering_bias : float = 0.0
	if weight_total > 0.0:
		steering_bias = clampf(
			(weighted_angle / weight_total) / obstacle_sensor_fov_deg,
			-1.0,
			1.0
		)

	return Vector2(steering_bias, nearest_ratio)


## Drops the car back onto the nearest road tile, upright and at rest, and
## forgets the current path so the next call re-seeds a fresh direction. Last
## resort for a car that ended up wedged, flipped or off the drivable grid.
func _recover(position : Vector3) -> void:
	if _vehicle == null:
		return

	var nearest_index : int = _nearest_node(position)
	if nearest_index < 0:
		return

	var spot : Vector3 = road_nodes[nearest_index] + Vector3(0.0, 0.6, 0.0)
	_vehicle.global_transform = Transform3D(Basis.IDENTITY, spot)
	_vehicle.linear_velocity = Vector3.ZERO
	_vehicle.angular_velocity = Vector3.ZERO

	_tilt_timer = 0.0
	_stuck_timer = 0.0
	_unstick_timer = 0.0
	_backing_up = false
	_progress_anchor_set = false
	_progress_timer = 0.0
	_path_indices = PackedInt32Array()
	_path.clear()
	_dead_end_distance = -1.0


## Starts the path at the nearest node, heading the way the car already points.
func _seed_path(position : Vector3, forward : Vector3) -> void:
	var start : int = _nearest_node(position)
	if start < 0 or _links[start].is_empty():
		return

	var best : int = -1
	var best_dot : float = -INF
	for neighbour : int in _links[start]:
		var direction : Vector3 = road_nodes[neighbour] - road_nodes[start]
		direction.y = 0.0
		var alignment : float = forward.dot(direction.normalized())
		if alignment > best_dot:
			best_dot = alignment
			best = neighbour

	_path_indices = PackedInt32Array([start, best])
	_fill_path()


## Drops nodes the car has driven past and picks new streets to keep the path
## topped up. Returns the route distance measured against the new path.
func _advance_path(position : Vector3, route_distance : float) -> float:
	var distance : float = route_distance
	var guard : int = 0

	while (
		_path_indices.size() > 2
		and _cumulative_distances.size() > 1
		and distance > _cumulative_distances[1]
		and guard < 8
	):
		_path_indices.remove_at(0)
		_fill_path()
		distance = _closest_route_distance(position)
		guard += 1

	return distance


func _fill_path() -> void:
	while _path_indices.size() < maxi(path_nodes, 2):
		var last : int = _path_indices[_path_indices.size() - 1]
		var previous : int = _path_indices[_path_indices.size() - 2]
		var next : int = _pick_next(previous, last)
		if next < 0:
			break
		_path_indices.append(next)

	_path.clear()
	for index : int in _path_indices:
		_path.append(road_nodes[index])

	_build_cumulative_distances()
	_find_dead_end_cusp()


## A dead end shows up in `_path_indices` as an A-B-A cusp: `_pick_next()`
## returns `previous` when a street has nowhere else to go, so the node right
## before and right after the tip are the same. Finds the first one in the
## current path window, if any.
func _find_dead_end_cusp() -> void:
	_dead_end_distance = -1.0

	for index : int in range(1, _path_indices.size() - 1):
		if _path_indices[index + 1] == _path_indices[index - 1]:
			_dead_end_distance = _cumulative_distances[index]
			return


## Picks where to go at `current`, having arrived from `previous`: a random
## street that isn't the way back. Only a dead end sends the car back.
func _pick_next(previous : int, current : int) -> int:
	var options : Array[int] = []
	for neighbour : int in _links[current]:
		if neighbour != previous:
			options.append(neighbour)

	if options.is_empty():
		return previous

	var through : Array[int] = []
	for option : int in options:
		if _branch_depth(current, option) >= min_branch_cells:
			through.append(option)

	var pool : Array[int] = through if not through.is_empty() else options
	return pool[randi() % pool.size()]


## How many tiles the branch leaving `current` toward `next` runs before it dead
## ends. A junction counts as "goes somewhere", so the walk stops there.
func _branch_depth(current : int, next : int) -> int:
	var previous : int = current
	var node : int = next
	var depth : int = 1

	while depth < min_branch_cells:
		var options : Array[int] = []
		for neighbour : int in _links[node]:
			if neighbour != previous:
				options.append(neighbour)

		if options.is_empty():
			return depth
		if options.size() > 1:
			return min_branch_cells

		previous = node
		node = options[0]
		depth += 1

	return depth


func _nearest_node(position : Vector3) -> int:
	var best : int = -1
	var best_distance_squared : float = INF

	for index : int in road_nodes.size():
		var flat : Vector2 = Vector2(
			position.x - road_nodes[index].x,
			position.z - road_nodes[index].z
		)
		if flat.length_squared() < best_distance_squared:
			best_distance_squared = flat.length_squared()
			best = index

	return best


func _build_cumulative_distances() -> void:
	_cumulative_distances.clear()
	var total : float = 0.0
	_cumulative_distances.append(0.0)

	for index : int in range(_path.size() - 1):
		total += _flat_distance(_path[index], _path[index + 1])
		_cumulative_distances.append(total)

	_total_length = total


## Projects `position` onto every path segment and returns the distance along
## the path of the closest point. Heights are ignored: the car rides the road
## surface, while the nodes sit on the nominal road height.
func _closest_route_distance(position : Vector3) -> float:
	var best_distance : float = 0.0
	var best_offset : float = INF

	for index : int in range(_path.size() - 1):
		var segment_start : Vector3 = _path[index]
		var segment_end : Vector3 = _path[index + 1]
		var segment : Vector2 = Vector2(
			segment_end.x - segment_start.x,
			segment_end.z - segment_start.z
		)
		var to_car : Vector2 = Vector2(
			position.x - segment_start.x,
			position.z - segment_start.z
		)

		var segment_length_squared : float = segment.length_squared()
		var along : float = 0.0
		if segment_length_squared > 0.0001:
			along = clampf(to_car.dot(segment) / segment_length_squared, 0.0, 1.0)

		var offset : float = (to_car - segment * along).length()
		if offset < best_offset:
			best_offset = offset
			best_distance = _cumulative_distances[index] + segment.length() * along

	return best_distance


func _point_at_distance(distance : float) -> Vector3:
	if _path.is_empty():
		return Vector3.ZERO
	if distance <= 0.0:
		return _path[0]
	if distance >= _total_length:
		return _path[_path.size() - 1]

	for index : int in range(_path.size() - 1):
		var segment_start_distance : float = _cumulative_distances[index]
		var segment_end_distance : float = _cumulative_distances[index + 1]

		if distance <= segment_end_distance:
			var segment_length : float = segment_end_distance - segment_start_distance
			var along : float = (
				0.0 if segment_length < 0.0001
				else (distance - segment_start_distance) / segment_length
			)
			return _path[index].lerp(_path[index + 1], along)

	return _path[_path.size() - 1]


func _flat_distance(first : Vector3, second : Vector3) -> float:
	return Vector2(first.x - second.x, first.z - second.z).length()
