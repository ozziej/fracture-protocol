class_name RtsFormationLayout
extends RefCounted

## Deterministic formation geometry shared by issued group orders and persistent
## production rallies. Keeping this stateless makes the resulting destinations
## safe to serialise as ordinary simulation positions.

const DEFAULT_SPACING := 1.6
const RALLY_SPACING := 1.85


static func group_offset(index: int, total: int, spacing := DEFAULT_SPACING) -> Vector3:
	if total <= 1:
		return Vector3.ZERO
	var columns := int(ceil(sqrt(float(total))))
	var rows := int(ceil(float(total) / float(columns)))
	var row := index / columns
	var column := index % columns
	var members_in_row := mini(columns, total - row * columns)
	return Vector3(
		(column - (members_in_row - 1) * 0.5) * spacing,
		0.0,
		(row - (rows - 1) * 0.5) * spacing
	)


static func persistent_rally_offset(index: int, spacing := RALLY_SPACING) -> Vector3:
	if index <= 0:
		return Vector3.ZERO
	# Fill square rings from the centre out. A 24-slot force therefore receives
	# unique, compact destinations without moving earlier arrivals when a later
	# unit completes production.
	var remaining := index - 1
	var ring := 1
	while remaining >= ring * 8:
		remaining -= ring * 8
		ring += 1
	var side_length := ring * 2
	var x := -ring
	var z := -ring
	if remaining < side_length:
		x += remaining
	elif remaining < side_length * 2:
		x = ring
		z += remaining - side_length
	elif remaining < side_length * 3:
		x = ring - (remaining - side_length * 2)
		z = ring
	else:
		z = ring - (remaining - side_length * 3)
	return Vector3(float(x) * spacing, 0.0, float(z) * spacing)
