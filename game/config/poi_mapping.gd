extends RefCounted

# poi_mapping.gd — OSM tag to PlaceCategory mapping
# Single source of truth per docs/design_resources_and_base.md §1 & §6

static func resolve_category(tags: Dictionary) -> String:
	# Haunted zones check first (highest priority per design docs)
	var amenity := str(tags.get("amenity", ""))
	var historic := str(tags.get("historic", ""))
	var landuse := str(tags.get("landuse", ""))
	var leisure := str(tags.get("leisure", ""))
	var tourism := str(tags.get("tourism", ""))
	var shop := str(tags.get("shop", ""))

	if landuse == "cemetery" or amenity == "grave_yard" or historic == "ruins":
		return "haunted"
	if tags.has("abandoned") or tags.has("disused"):
		return "haunted"

	# Landmark check
	if tourism in ["attraction", "monument", "memorial"] or historic == "monument":
		return "landmark"

	# Medical check
	if amenity in ["pharmacy", "clinic", "dentist", "doctors", "hospital"]:
		return "medical"

	# Grocery & Food check
	if shop in ["supermarket", "convenience", "bakery", "greengrocer", "deli"]:
		return "grocery"
	if amenity in ["cafe", "restaurant", "fast_food", "food_court"]:
		return "grocery"

	# Hardware check
	if shop in ["hardware", "doityourself", "trade"]:
		return "hardware"

	# Roadside check
	if amenity == "fuel" or shop in ["car_repair", "car_parts"]:
		return "roadside"

	# Civic check
	if amenity in ["school", "library", "townhall", "post_office", "police", "fire_station", "college", "university", "community_centre"]:
		return "civic"

	# Bigbox / Mall check
	if shop in ["mall", "department_store"]:
		return "bigbox"

	# Park check
	if leisure in ["park", "dog_park", "garden", "nature_reserve", "pitch", "playground"]:
		return "park"

	return ""
