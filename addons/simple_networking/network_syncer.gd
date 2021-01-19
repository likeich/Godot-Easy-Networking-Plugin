extends Node

export var server_owned: bool = false
export var synced_properties: PoolStringArray = [] # Where synced vars are placed.
export var synced_booleans: PoolStringArray = [] # Maximum of up to 64 booleans
export var updates_per_second := 60.0
export var update_percent_required := 100.0
export var print_latency: bool = false

var can_update := true
var previous_full_state: Networking.State # The last state with no null values.
var sync_timer = Timer.new()
var update_count := 0

onready var body = get_parent() # The object being networked.

func _ready():
	if server_owned:
		body.set_network_master(1)
	
	previous_full_state = Networking.State.new(fill_properties(), 0, OS.get_system_time_msecs())
	
	sync_timer.autostart = true
	sync_timer.wait_time = (1.0 / updates_per_second)
	sync_timer.one_shot = true
	sync_timer.connect("timeout", self, "send_state")
	add_child(sync_timer)

# Used to create the state custom_data from the properties export var.
func fill_properties() -> Array:
	var properties: Array = []
	for property_num in synced_properties.size():
		properties.append(body.get(synced_properties[property_num]))
	
	return properties

# Used to create the state custom_bools from the booleans export var.
func fill_booleans() -> int:
	var lbool = Networking.LongBool.new()
	for property_num in synced_booleans.size():
		lbool.set_value(property_num, body.get(synced_booleans[property_num]))
	
	return lbool.get_data()

# Sends the state to the server if it has new information to send.
func send_state():
	if !is_instance_valid(get_tree().network_peer) or !is_network_master(): return
	
	update_count += 1
	
	# Nulls state variables that are the same to save bandwidth.
	var state: Networking.State = Networking.State.new(fill_properties(), fill_booleans(), OS.get_system_time_msecs())
	
	#Calculates if a required packet should be sent.
	var calculation: int = int(round((update_percent_required / 100) * updates_per_second))
	if update_count % int(round(updates_per_second / calculation)) == 0: 
		print("Req: ", update_count)
		set_previous_full_state(state)
		Networking.send_state(state, body.name)
		sync_timer.start((1 / updates_per_second))
		
		if update_count >= updates_per_second:
			update_count = 0
		
		return
	
	var changed := set_changed_states(state)
	if !changed: 
		sync_timer.start((1 / updates_per_second))
		
		if update_count >= updates_per_second:
			update_count = 0
		
		return
	
	set_previous_full_state(state)
	Networking.send_state(state, body.name)
	sync_timer.start((1 / updates_per_second))
	
	if update_count >= updates_per_second:
		update_count = 0

# Sets the received variables in the parent object.
func interpolate_state(old_state: Networking.State, new_state: Networking.State, interp_ratio: float = .5):
	for num in new_state.custom_data.size():
		if new_state.custom_data[num] == null: # Can be null from set_changed_states.
			continue
		elif body.has_method("interpolate_" + synced_properties[num]):
			body.call("interpolate_" + synced_properties[num], old_state.custom_data[num], new_state.custom_data[num], interp_ratio)
		elif body.has_method("net_set_" + synced_properties[num]):
			body.call("net_set_" + synced_properties[num], new_state.custom_data[num])
		else:
			body.set(synced_properties[num], lerp(old_state.custom_data[num], new_state.custom_data[num], interp_ratio))
	
	var lbool := Networking.LongBool.new(new_state.custom_bools)
	for num in synced_booleans.size():
		body.set(synced_booleans[num], lbool.get_value(num))

# Updates the previous full state var and returns if the state has new data.
func set_changed_states(new_state: Networking.State) -> bool:
	for num in new_state.custom_data.size():
		if new_state.custom_data[num] != previous_full_state.custom_data[num]:
			return true
	
	if new_state.custom_bools != previous_full_state.custom_bools:
		return true
	
	return false

# Sets the previous full state by ignoring null values.
func set_previous_full_state(new_state: Networking.State):
	for property in previous_full_state.custom_data.size():
		if new_state.custom_data[property] != null:
			previous_full_state.custom_data[property] = new_state.custom_data[property]
	previous_full_state.custom_bools = new_state.custom_bools
	previous_full_state.timestamp = new_state.timestamp
