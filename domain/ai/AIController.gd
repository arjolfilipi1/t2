## AIController.gd
## Simple rule-based AI controller.
##
## Decision priority (Main Phase):
##   1. Activate effects  — highest ATK boost / search / destruction first
##   2. Normal summon     — highest ATK monster available
##   3. Set spell/trap    — if hand is large and field is thin
##
## Decision priority (Battle Phase):
##   4. Attack with every available monster — strongest attacker first,
##      weakest opponent target first (trades up when favourable)
##
## The AI never passes priority on an open chain unless it genuinely has
## nothing legal to play. It handles InputRequest callbacks (target
## selection, discard, tribute) with simple heuristics.
##
## Usage:
##   var ai := AIController.new()
##   add_child(ai)
##   ai.setup(ai_player, game_director)
##   # Then connect GameDirector signals so AI fires when it's its turn:
##   game_director.phase_changed.connect(ai._on_phase_changed)
##   game_director.stack.priority_passed.connect(ai._on_priority_passed)
##   game_director.awaiting_input.connect(ai._on_awaiting_input)
class_name AIController
extends Node

# ─── Config ───────────────────────────────────────────────────────────────────

## Milliseconds of artificial thinking delay between actions.
## Set to 0 in tests, ~400-800 for a natural feel in play.
@export var think_delay_ms: int = 600

## If true, print every decision to the Output panel.
@export var verbose: bool = true

# ─── Dependencies ─────────────────────────────────────────────────────────────

var _player: Player       = null
var _gd:     GameDirector = null

# ─── State ────────────────────────────────────────────────────────────────────

## True while the AI is working through its turn actions.
var _thinking: bool = false

## Actions queued for sequential execution with delays.
var _action_queue: Array[Callable] = []

# ─── Setup ────────────────────────────────────────────────────────────────────

func setup(ai_player: Player, game_director: GameDirector) -> void:
	_player = ai_player
	_gd     = game_director

	game_director.phase_changed.connect(_on_phase_changed)
	game_director.stack.priority_passed.connect(_on_priority_passed)
	game_director.awaiting_input.connect(_on_awaiting_input)
	game_director.action_executed.connect(_on_action_executed)

# ─── Phase Triggers ───────────────────────────────────────────────────────────

func _on_phase_changed(_phase_name: String, _turn: int, active_player: Player) -> void:
	if active_player != _player:
		return
	if _thinking:
		return

	var phase := _gd.tm.context.phase
	match phase:
		TurnContext.Phase.DRAW:
			# Draw phase is handled automatically by TurnManager.
			# Advance through it after a brief pause.
			_queue_action(func(): _gd.advance_phase(_player))

		TurnContext.Phase.STANDBY:
			_queue_action(func(): _gd.advance_phase(_player))

		TurnContext.Phase.MAIN_1:
			_plan_main_phase()

		TurnContext.Phase.BATTLE_START:
			_plan_battle_phase()

		TurnContext.Phase.MAIN_2:
			# After battle, may want to set more spells/traps
			_plan_main_phase_2()

		TurnContext.Phase.END:
			# TurnManager handles END housekeeping automatically
			pass

# ─── Priority Window ──────────────────────────────────────────────────────────

func _on_priority_passed(to_player: Player) -> void:
	if to_player != _player:
		return
	if _thinking:
		return

	# Check if we have anything to chain
	var la := _gd.legal_actions_for(_player)
	if not la.can_activate.is_empty() and not _gd.stack.chain_is_empty():
		# We might want to chain a quick effect or counter trap
		var response := _choose_chain_response(la)
		if response != null:
			_queue_action(response)
			return

	# Nothing to chain — pass priority
	_queue_action(func(): _gd.pass_priority(_player))

# ─── Input Requests ───────────────────────────────────────────────────────────

func _on_awaiting_input(request: InputRequest) -> void:
	if request.player != _player:
		return
	# Handle asynchronously so the UI can show the decision
	_queue_action(func(): _handle_input_request(request))

func _handle_input_request(request: InputRequest) -> void:
	match request.type:
		InputRequest.RequestType.TARGET_SELECTION:
			_resolve_target_selection(request)
		InputRequest.RequestType.DISCARD_SELECTION:
			_resolve_discard_selection(request)
		InputRequest.RequestType.TRIBUTE_SELECTION:
			_resolve_tribute_selection(request)
		InputRequest.RequestType.TRIGGER_SELECTION:
			_resolve_trigger_selection(request)
		InputRequest.RequestType.SEARCH_SELECTION:
			_resolve_search_selection(request)
		_:
			# Unknown request type — pick the first candidate
			if not request.candidates.is_empty():
				_gd.resolve_input([request.candidates[0]])
			else:
				_gd.resolve_input([])

# ─── Main Phase Planning ──────────────────────────────────────────────────────

func _plan_main_phase() -> void:
	_thinking = true
	_action_queue.clear()

	var la := _gd.legal_actions_for(_player)
	_log("Main phase — %s" % la)

	# 1. Activate effects (draw, search, destroy — highest value first)
	for card in _priority_sorted_activations(la):
		var effects: Array = la.activatable_effects_for(card)
		for eff_idx in effects:
			_queue_action(_make_activate_action(card, eff_idx))

	# 2. Normal summon — highest ATK monster
	if not la.can_normal_summon.is_empty():
		var to_summon := _best_summon_candidate(la.can_normal_summon)
		var tributes  := _choose_tributes(to_summon)
		_queue_action(func():
			_gd.normal_summon(_player, to_summon, tributes)
		)

	# 3. Set a spell or trap if we have one and the field is empty/thin
	var field_spells := _gd.zm.spell_count(_player)
	if field_spells < 2:
		for card in la.can_set:
			if not card.definition.is_monster():
				_queue_action(func(): _gd.set_card(_player, card))
				break  # Set one per turn is enough for this AI

	# 4. Advance to Battle Phase
	_queue_action(func(): _gd.advance_phase(_player))

	_thinking = false
	_flush_queue()

func _plan_main_phase_2() -> void:
	_thinking = true
	_action_queue.clear()

	var la := _gd.legal_actions_for(_player)

	# After battle: activate any remaining effects, then end turn
	for card in _priority_sorted_activations(la):
		var effects: Array = la.activatable_effects_for(card)
		for eff_idx in effects:
			_queue_action(_make_activate_action(card, eff_idx))

	_queue_action(func(): _gd.advance_phase(_player))

	_thinking = false
	_flush_queue()

# ─── Battle Phase Planning ────────────────────────────────────────────────────

func _plan_battle_phase() -> void:
	_thinking = true
	_action_queue.clear()

	var la := _gd.legal_actions_for(_player)

	# Collect all attack declarations sorted by attacker ATK descending
	var attackers: Array[CardInstance] = []
	for card in la.can_attack.keys():
		attackers.append(card)
	attackers.sort_custom(func(a, b): return a.get_atk() > b.get_atk())

	for attacker in attackers:
		var targets: Array = la.attack_targets_for(attacker)
		var target := _choose_attack_target(attacker, targets)
		var chosen_target := target  ## capture for closure
		var chosen_attacker := attacker
		_queue_action(func():
			_gd.declare_attack(_player, chosen_attacker, chosen_target)
		)

	# End battle phase
	_queue_action(func(): _gd.tm.end_battle_phase())

	_thinking = false
	_flush_queue()

# ─── Chain Response ───────────────────────────────────────────────────────────

func _choose_chain_response(la: LegalActions) -> Callable:
	## Only respond with counter traps (Spell Speed 3) or quick effects (SS2)
	## that are still legal on the current chain.
	for card in la.can_activate.keys():
		var effects: Array = la.activatable_effects_for(card)
		for eff_idx in effects:
			var eff: EffectDefinition = card.definition.effects[eff_idx]
			if eff.spell_speed >= _gd.stack.minimum_spell_speed():
				return _make_activate_action(card, eff_idx)
	return Callable()

# ─── Effect Activation Helpers ────────────────────────────────────────────────

## Returns activatable cards sorted by effect priority:
##   destruction > search/draw > stat boost > other
func _priority_sorted_activations(la: LegalActions) -> Array:
	var cards := la.can_activate.keys()
	cards.sort_custom(func(a: CardInstance, b: CardInstance) -> bool:
		return _effect_priority(a, la) > _effect_priority(b, la)
	)
	return cards

func _effect_priority(card: CardInstance, la: LegalActions) -> int:
	## Score the card's best effect to decide activation order.
	var best := 0
	for eff_idx in la.activatable_effects_for(card):
		var score := _score_effect(card.definition.effects[eff_idx])
		if score > best:
			best = score
	return best

func _score_effect(eff: EffectDefinition) -> int:
	## Heuristic scores by resolution step types present.
	var score := 0
	for step in eff.resolution_steps:
		if step is EffectResolutionStep.DestroyTargetsStep:       score += 80
		if step is EffectResolutionStep.DestroyAllMonstersStep:   score += 90
		if step is EffectResolutionStep.SearchDeckStep:           score += 70
		if step is EffectResolutionStep.DrawCardsStep:            score += 65
		if step is EffectResolutionStep.SpecialSummonTargetStep:  score += 75
		if step is EffectResolutionStep.BanishTargetsStep:        score += 60
		if step is EffectResolutionStep.ReturnToHandStep:         score += 55
		if step is EffectResolutionStep.ModifyStatStep:           score += 30
		if step is EffectResolutionStep.GainLifePointsStep:       score += 20
		if step is EffectResolutionStep.DealDamageStep:           score += 35
	return score

func _make_activate_action(card: CardInstance, eff_idx: int) -> Callable:
	## Closure that activates one effect, selecting targets if needed.
	return func():
		var eff: EffectDefinition = card.definition.effects[eff_idx]
		var targets: Array[CardInstance] = []
		if eff.targets_required > 0:
			targets = _pick_targets(eff)
			if targets.size() < eff.targets_required:
				_log("  Skipping %s — not enough valid targets" % eff.effect_name)
				return
		_log("  Activate: %s on %s" % [eff.effect_name, card.definition.card_name])
		_gd.activate_effect(_player, card, eff_idx, targets)

# ─── Targeting Heuristics ─────────────────────────────────────────────────────

func _pick_targets(eff: EffectDefinition) -> Array[CardInstance]:
	var candidates := RuleEngine.get_legal_targets(eff, _player, _gd.zm)
	if candidates.is_empty():
		return []

	# Destruction effects: target opponent's highest ATK monsters first
	var destroys := eff.resolution_steps.any(
		func(s): return s is EffectResolutionStep.DestroyTargetsStep
	)
	if destroys:
		candidates.sort_custom(func(a: CardInstance, b: CardInstance) -> bool:
			# Opponent's monsters first, then by ATK descending
			var a_opp := a.controller != _player
			var b_opp := b.controller != _player
			if a_opp != b_opp:
				return a_opp
			return a.get_atk() > b.get_atk()
		)

	# Stat boost effects: target own highest ATK monster
	var boosts := eff.resolution_steps.any(
		func(s): return s is EffectResolutionStep.ModifyStatStep
	)
	if boosts:
		candidates.sort_custom(func(a: CardInstance, b: CardInstance) -> bool:
			var a_own := a.controller == _player
			var b_own := b.controller == _player
			if a_own != b_own:
				return a_own
			return a.get_atk() > b.get_atk()
		)

	var result: Array[CardInstance] = []
	for i in min(eff.targets_required, candidates.size()):
		result.append(candidates[i])
	return result

# ─── Summon Heuristics ────────────────────────────────────────────────────────

func _best_summon_candidate(candidates: Array[CardInstance]) -> CardInstance:
	## Pick the highest-ATK monster we can summon.
	var best: CardInstance = candidates[0]
	for card in candidates:
		if card.get_atk() > best.get_atk():
			best = card
	return best

func _choose_tributes(card: CardInstance) -> Array[CardInstance]:
	var needed := card.definition.tribute_count()
	if needed == 0:
		return []
	## Sacrifice lowest-ATK monsters first to preserve best attackers.
	var field := _gd.zm.monsters_on_field(_player).duplicate()
	field.sort_custom(func(a: CardInstance, b: CardInstance) -> bool:
		return a.get_atk() < b.get_atk()
	)
	var tributes: Array[CardInstance] = []
	for i in needed:
		tributes.append(field[i])
	return tributes

# ─── Attack Heuristics ────────────────────────────────────────────────────────

func _choose_attack_target(
	attacker: CardInstance,
	targets:  Array
) -> CardInstance:
	## null = direct attack — always take it if available
	if null in targets:
		return null

	var valid: Array[CardInstance] = []
	for t in targets:
		if t != null:
			valid.append(t)

	if valid.is_empty():
		return null

	## Prefer to destroy without taking damage:
	##   ATK > target ATK (for ATK-position targets)
	##   ATK > target DEF (for DEF-position targets)
	var safe_kills: Array[CardInstance] = []
	for target in valid:
		if target.is_in_atk_position() and attacker.get_atk() > target.get_atk():
			safe_kills.append(target)
		elif target.is_in_def_position() and attacker.get_atk() > target.get_def():
			safe_kills.append(target)

	if not safe_kills.is_empty():
		## Among safe kills, target lowest ATK (trade efficiently)
		safe_kills.sort_custom(func(a, b): return a.get_atk() < b.get_atk())
		return safe_kills[0]

	## No safe kill — attack lowest DEF target to minimise damage taken
	valid.sort_custom(func(a: CardInstance, b: CardInstance) -> bool:
		var a_stat := a.get_def() if a.is_in_def_position() else a.get_atk()
		var b_stat := b.get_def() if b.is_in_def_position() else b.get_atk()
		return a_stat < b_stat
	)
	return valid[0]

# ─── Input Request Handlers ───────────────────────────────────────────────────

func _resolve_target_selection(request: InputRequest) -> void:
	var candidates: Array[CardInstance] = []
	for c in request.candidates:
		candidates.append(c)

	## Simple: pick first N candidates that belong to the opponent
	var opp_targets: Array[CardInstance] = candidates.filter(
		func(c: CardInstance) -> bool: return c.controller != _player
	)
	var own_targets: Array[CardInstance] = candidates.filter(
		func(c: CardInstance) -> bool: return c.controller == _player
	)

	var chosen: Array[CardInstance] = []
	## Prefer opponent targets, then own targets if not enough
	for c in opp_targets:
		if chosen.size() >= request.max_choices:
			break
		chosen.append(c)
	for c in own_targets:
		if chosen.size() >= request.max_choices:
			break
		chosen.append(c)

	_gd.resolve_input(chosen)

func _resolve_discard_selection(request: InputRequest) -> void:
	## Discard lowest-value cards: normal monsters with no effects first
	var hand: Array[CardInstance] = []
	for c in request.candidates:
		hand.append(c)

	hand.sort_custom(func(a: CardInstance, b: CardInstance) -> bool:
		## Lower score = discard first
		return _hand_value(a) < _hand_value(b)
	)

	var chosen: Array[CardInstance] = []
	for i in min(request.min_choices, hand.size()):
		chosen.append(hand[i])
	_gd.resolve_input(chosen)

func _resolve_tribute_selection(request: InputRequest) -> void:
	## Tribute lowest-ATK monsters
	var monsters: Array[CardInstance] = []
	for c in request.candidates:
		monsters.append(c)
	monsters.sort_custom(func(a: CardInstance, b: CardInstance) -> bool:
		return a.get_atk() < b.get_atk()
	)
	var chosen: Array[CardInstance] = []
	for i in min(request.min_choices, monsters.size()):
		chosen.append(monsters[i])
	_gd.resolve_input(chosen)

func _resolve_trigger_selection(request: InputRequest) -> void:
	## Activate all optional triggers — AI always takes free effects
	var choices: Dictionary = {}
	for trigger in request.candidates:
		choices[trigger] = true
	_gd.resolve_input(choices)

func _resolve_search_selection(request: InputRequest) -> void:
	## Add the card with the highest ATK, or first card if non-monsters
	var candidates: Array[CardInstance] = []
	for c in request.candidates:
		candidates.append(c)

	candidates.sort_custom(func(a: CardInstance, b: CardInstance) -> bool:
		return a.get_atk() > b.get_atk()
	)
	_gd.resolve_input([candidates[0]] if not candidates.is_empty() else [])

func _hand_value(card: CardInstance) -> int:
	## Rough value estimate for discard prioritisation.
	if card.definition.effects.is_empty():
		return card.get_atk()            ## Normal monster: ATK is its value
	var score := card.get_atk()
	for eff in card.definition.effects:
		score += _score_effect(eff)
	return score

# ─── Action Queue ─────────────────────────────────────────────────────────────

func _queue_action(action: Callable) -> void:
	_action_queue.append(action)

func _flush_queue() -> void:
	if _action_queue.is_empty():
		return
	_execute_next()

func _execute_next() -> void:
	if _action_queue.is_empty():
		return
	if not _gd.stack.is_idle():
		_gd.stack.stack_idle.connect(_execute_next,CONNECT_ONE_SHOT)
	if think_delay_ms <= 0:
		var action := _action_queue.pop_front()
		action.call()
		## Continue immediately (tests / fast-forward mode)
		_execute_next()
	else:
		var timer := get_tree().create_timer(think_delay_ms / 1000.0)
		timer.timeout.connect(func():
			if _action_queue.is_empty():
				return
			var action := _action_queue.pop_front()
			action.call()
			_execute_next()
		)

func _on_action_executed(_action: GameAction) -> void:
	## If the executed action was ours and the queue has more, keep going
	pass  ## _execute_next() drives itself via timer chain

# ─── Logging ──────────────────────────────────────────────────────────────────

func _log(msg: String) -> void:
	if verbose:
		print("AI [%s]: %s" % [_player.display_name, msg])
