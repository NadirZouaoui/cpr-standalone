extends Node

func _ready() -> void:
	var list := load("res://resources/hazards/hazards_pass1.tres") as HazardList
	for pass_index in 3:
		list.shuffle_items()
		var out: Array[String] = []
		for item in list.items:
			out.append("%s%s" % ["R" if item.is_real else "f", item.id])
		print("run %d: %s" % [pass_index, " ".join(out)])
	get_tree().quit()
