extends Area3D
class_name MoveCommandHandle

@onready var collision_shape: CollisionShape3D = $CollisionShape3D

var _selected_units: Dictionary
var _click_is_inside: bool

func _ready():
	# Vogel Spiral 방식에서는 Area3D 충돌 감지가 필요 없으므로
	# CollisionShape 초기화 및 body_entered 연결을 제거합니다.
	pass

func move_selected_units(selected_units: Dictionary,
						 click_position: Vector3,
						 attack_move: bool):
	position = click_position
	_selected_units = selected_units.duplicate()
	
	var top_left: Vector3 = Vector3.ZERO
	var bottom_right: Vector3 = Vector3.ZERO
	var first_unit: bool = true
	
	for unit: Unit in _selected_units.values():
		# queue_free() 전에 연결하므로 여기서는 안전하지만,
		# 어차피 queue_free() 직전까지만 살아있으면 되므로 연결 자체가 불필요.
		# 단, 유닛이 루프 도중 사라지는 엣지케이스 방어용으로 유지.
		unit.tree_exiting.connect(_remove_dead_unit.bind(unit))
		
		var pos = unit.global_position
		
		if first_unit:
			top_left = pos
			bottom_right = pos
			first_unit = false
			continue
		
		if pos.x < top_left.x:
			top_left.x = pos.x
		if pos.x > bottom_right.x:
			bottom_right.x = pos.x
		if pos.z < top_left.z:
			top_left.z = pos.z
		if pos.z > bottom_right.z:
			bottom_right.z = pos.z

	var selection_center = (bottom_right + top_left) / 2
	selection_center.y = click_position.y
	var center_click_diff = (selection_center - click_position).length()
	
	var box_length = 0.0
	if not first_unit:
		box_length = (bottom_right - top_left).length()
		
	_click_is_inside = center_click_diff < box_length
	
	var unit_index = 0
	
	for unit: Unit in _selected_units.values():
		# queue_free() 직전이므로 이 시점에 유닛이 소멸했을 가능성 방어
		if not is_instance_valid(unit):
			continue
		
		var target_unit_pos: Vector3
		
		if _click_is_inside:
			var r = 0.45
			if is_instance_valid(unit.navigation_agent):
				r = unit.navigation_agent.radius
			
			if unit_index == 0:
				# 첫 번째 유닛은 클릭 지점 정중앙
				target_unit_pos = click_position
			else:
				# Vogel's Spiral (해바라기 씨앗 패턴)
				# θ = n × 137.5° (황금각, 라디안: 2.39996...)
				# R = sqrt(n) × (유닛 반경 × 1.5)  ← sqrt로 균일 밀도 보장
				var golden_angle: float = 2.39996
				var theta: float = unit_index * golden_angle
				var spiral_radius: float = sqrt(float(unit_index)) * (r * 1.5)
				target_unit_pos = click_position + Vector3(cos(theta), 0.0, sin(theta)) * spiral_radius
			
			target_unit_pos.y = click_position.y
			unit_index += 1
		else:
			# 클릭 지점이 선택 영역 밖 → 대형 유지 이동 (기존 오프셋 방식)
			target_unit_pos = click_position + unit.global_position - selection_center
			target_unit_pos.y = click_position.y
		
		var data: MoveState.MoveCommandData = MoveState.MoveCommandData.new()
		data.target_position = target_unit_pos
		data.attack_move = attack_move
		unit.state_machine.transition_to_state(MoveState.ID, data)
	
	# 목표 할당 완료 → 이 핸들 객체는 역할 종료, 메모리 해제
	queue_free()

func remove_units(units: Dictionary):
	# queue_free() 이후 외부에서 호출될 수 있으므로 유효성 체크
	if not is_instance_valid(self):
		return
	for unit_id in units.keys():
		_selected_units.erase(unit_id)

func _remove_dead_unit(unit: Unit):
	# queue_free() 이후 시그널이 지연 발화될 수 있으므로 방어
	if not is_instance_valid(self):
		return
	_selected_units.erase(unit.get_instance_id())