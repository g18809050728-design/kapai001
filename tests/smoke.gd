extends SceneTree

func _initialize() -> void:
    var v := Engine.get_version_info()
    print("SMOKE_OK version=", v.string)
    var rng := RandomNumberGenerator.new()
    rng.seed = 12345
    print("rng_first=", rng.randi_range(0, 100))
    quit(0)
