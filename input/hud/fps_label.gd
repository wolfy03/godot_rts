extends Label

@export var refresh_interval: float = 0.25

var _refresh_timer: Timer

func _ready() -> void:
	_refresh_timer = Timer.new()
	_refresh_timer.wait_time = maxf(refresh_interval, 0.05)
	_refresh_timer.timeout.connect(_refresh_text)
	add_child(_refresh_timer)
	_refresh_timer.start()
	_refresh_text()

func _refresh_text() -> void:
	text = "%d FPS " % Engine.get_frames_per_second()
