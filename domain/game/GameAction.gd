## GameAction.gd
## Base class for all player actions.
## Implements the Command pattern:
##   - Validates before executing (via RuleEngine)
##   - Executes against the live game state
##   - Carries enough data to serialize for replay / networking
##
## GameDirector receives a GameAction, calls validate(), and if valid calls execute().
## Nothing else should mutate game state directly.
class_name GameAction
extends RefCounted

# ─── Identity ─────────────────────────────────────────────────────────────────

## The player who submitted this action.
var player: Player = null

## Monotonically increasing action number — set by GameDirector.
var action_id: int = 0

## Wall-clock timestamp — set by GameDirector.
var timestamp: float = 0.0

# ─── Interface ────────────────────────────────────────────────────────────────

## Check whether this action is currently legal.
## Returns a RuleResult so the caller knows why it failed.
func validate(
	_zm:    ZoneManager,
	_tm:    TurnManager,
	_stack: EffectStack
) -> RuleResult:
	return RuleResult.fail(RuleResult.Reason.OK, "GameAction.validate() not overridden")

## Execute the action against the live game state.
## Only called after validate() returned ok.
func execute(
	_zm:    ZoneManager,
	_tm:    TurnManager,
	_stack: EffectStack
) -> void:
	push_error("GameAction.execute() not overridden in %s" % get_class())

## Human-readable description for logs / replay UI.
func describe() -> String:
	return "GameAction"

## Serialise to a dictionary for networking / replay saving.
func to_dict() -> Dictionary:
	return {
		"type":      get_class(),
		"player_id": player.player_id if player else -1,
		"action_id": action_id,
		"timestamp": timestamp,
	}


# ══════════════════════════════════════════════════════════════════════════════
# NORMAL SUMMON
# ══════════════════════════════════════════════════════════════════════════════

class NormalSummonAction extends GameAction:
	var card:             CardInstance
	var tribute_targets:  Array[CardInstance] = []
	## Destination slot (-1 = first available)
	var target_slot:      int = -1

	static func make(
		p:        Player,
		c:        CardInstance,
		tributes: Array[CardInstance] = [],
		slot:     int = -1
	) -> NormalSummonAction:
		var a              := NormalSummonAction.new()
		a.player           = p
		a.card             = c
		a.tribute_targets  = tributes
		a.target_slot      = slot
		return a

	func validate(zm: ZoneManager, tm: TurnManager, _stack: EffectStack) -> RuleResult:
		return RuleEngine.can_normal_summon(card, player, zm, tm.context, tribute_targets)

	func execute(zm: ZoneManager, tm: TurnManager, _stack: EffectStack) -> void:
		# Pay tributes first
		for tribute in tribute_targets:
			zm.move(tribute, zm.graveyard_of(player), ZoneManager.MoveReason.TRIBUTE)

		# Place on field
		if target_slot >= 0:
			zm.move_to_slot(card, zm.monster_zone_of(player), target_slot,
				ZoneManager.MoveReason.NORMAL_SUMMON)
		else:
			zm.move_to_first_slot(card, zm.monster_zone_of(player),
				ZoneManager.MoveReason.NORMAL_SUMMON)

		card.record_normal_summon(tm.current_turn())
		player.normal_summons_remaining -= 1

		# Emit summon event for trigger evaluation
		var event := GameEvent.card_summoned(card, true)
		_stack_ref.evaluate_triggers(event, zm)

	## Injected by GameDirector so execute() can reach the stack.
	var _stack_ref: EffectStack = null

	func describe() -> String:
		return "Normal Summon %s" % card.definition.card_name

	func to_dict() -> Dictionary:
		var d         := super.to_dict()
		d["card_id"]  = card.instance_id
		d["tributes"] = tribute_targets.map(func(t): return t.instance_id)
		d["slot"]     = target_slot
		return d


# ══════════════════════════════════════════════════════════════════════════════
# SET
# ══════════════════════════════════════════════════════════════════════════════

class SetAction extends GameAction:
	var card:        CardInstance
	var target_slot: int = -1

	static func make(p: Player, c: CardInstance, slot: int = -1) -> SetAction:
		var a        := SetAction.new()
		a.player     = p
		a.card       = c
		a.target_slot = slot
		return a

	func validate(zm: ZoneManager, tm: TurnManager, _stack: EffectStack) -> RuleResult:
		return RuleEngine.can_set(card, player, zm, tm.context)

	func execute(zm: ZoneManager, tm: TurnManager, _stack: EffectStack) -> void:
		if card.definition.is_monster():
			if target_slot >= 0:
				zm.move_to_slot(card, zm.monster_zone_of(player), target_slot,
					ZoneManager.MoveReason.SET)
			else:
				zm.move_to_first_slot(card, zm.monster_zone_of(player),
					ZoneManager.MoveReason.SET)
			card.face_state = CardInstance.FaceState.FACE_DOWN
			card.position   = CardDefinition.Position.FACE_DOWN_DEF
			card.record_normal_summon(tm.current_turn())
			player.normal_summons_remaining -= 1
		else:
			if target_slot >= 0:
				zm.move_to_slot(card, zm.spell_zone_of(player), target_slot,
					ZoneManager.MoveReason.SET)
			else:
				zm.move_to_first_slot(card, zm.spell_zone_of(player),
					ZoneManager.MoveReason.SET)
			card.face_state = CardInstance.FaceState.FACE_DOWN

	func describe() -> String:
		return "Set %s" % card.definition.card_name

	func to_dict() -> Dictionary:
		var d        := super.to_dict()
		d["card_id"] = card.instance_id
		d["slot"]    = target_slot
		return d


# ══════════════════════════════════════════════════════════════════════════════
# ACTIVATE EFFECT
# ══════════════════════════════════════════════════════════════════════════════

class ActivateEffectAction extends GameAction:
	var card:         CardInstance
	var effect_index: int
	var targets:      Array[CardInstance] = []

	static func make(
		p:      Player,
		c:      CardInstance,
		idx:    int,
		tgts:   Array[CardInstance] = []
	) -> ActivateEffectAction:
		var a          := ActivateEffectAction.new()
		a.player       = p
		a.card         = c
		a.effect_index = idx
		a.targets      = tgts
		return a

	func validate(zm: ZoneManager, tm: TurnManager, stack: EffectStack) -> RuleResult:
		return RuleEngine.can_activate_effect(
			card, effect_index, player, zm, tm.context, stack
		)

	func execute(zm: ZoneManager, _tm: TurnManager, stack: EffectStack) -> void:
		var eff: EffectDefinition = card.definition.effects[effect_index]

		# Pay costs before going on chain
		EffectCost.CostExecutor.pay_all(eff, card, zm, player)

		# If it's a spell/trap on the field, flip face-up on activation
		if card.is_on_field() and card.is_face_down():
			card.face_state = CardInstance.FaceState.FACE_UP

		# Push onto chain
		stack.push(eff, card, player, targets)

	func describe() -> String:
		var eff_name := ""
		if effect_index < card.definition.effects.size():
			eff_name = card.definition.effects[effect_index].effect_name
		return "Activate %s (%s)" % [card.definition.card_name, eff_name]

	func to_dict() -> Dictionary:
		var d              := super.to_dict()
		d["card_id"]       = card.instance_id
		d["effect_index"]  = effect_index
		d["target_ids"]    = targets.map(func(t): return t.instance_id)
		return d


# ══════════════════════════════════════════════════════════════════════════════
# DECLARE ATTACK
# ══════════════════════════════════════════════════════════════════════════════

class DeclareAttackAction extends GameAction:
	var attacker: CardInstance
	var target:   CardInstance   ## null = direct attack

	static func make(p: Player, atk: CardInstance, tgt: CardInstance = null) -> DeclareAttackAction:
		var a      := DeclareAttackAction.new()
		a.player   = p
		a.attacker = atk
		a.target   = tgt
		return a

	func validate(zm: ZoneManager, tm: TurnManager, stack: EffectStack) -> RuleResult:
		return RuleEngine.can_attack(attacker, target, player, zm, tm.context)

	func execute(_zm: ZoneManager, tm: TurnManager, stack: EffectStack) -> void:
		# TurnManager drives the battle sub-phases
		tm.begin_battle_step(attacker, target)
		# Priority window opened inside begin_battle_step — both players
		# may respond before GameDirector calls begin_damage_step()

	func describe() -> String:
		if target == null:
			return "%s attacks directly" % attacker.definition.card_name
		return "%s attacks %s" % [attacker.definition.card_name, target.definition.card_name]

	func to_dict() -> Dictionary:
		var d             := super.to_dict()
		d["attacker_id"]  = attacker.instance_id
		d["target_id"]    = target.instance_id if target else -1
		return d


# ══════════════════════════════════════════════════════════════════════════════
# RESOLVE BATTLE DAMAGE
# ══════════════════════════════════════════════════════════════════════════════

## Internal action — GameDirector creates this after both players pass priority
## in BATTLE_STEP. Not submitted by the player directly.
class ResolveBattleDamageAction extends GameAction:
	var attacker: CardInstance
	var target:   CardInstance

	static func make(p: Player, atk: CardInstance, tgt: CardInstance) -> ResolveBattleDamageAction:
		var a      := ResolveBattleDamageAction.new()
		a.player   = p
		a.attacker = atk
		a.target   = tgt
		return a

	func validate(_zm: ZoneManager, tm: TurnManager, _stack: EffectStack) -> RuleResult:
		if tm.context.phase != TurnContext.Phase.DAMAGE_STEP:
			return RuleResult.fail(RuleResult.Reason.WRONG_PHASE, "Not in damage step")
		return RuleResult.ok()

	func execute(zm: ZoneManager, tm: TurnManager, stack: EffectStack) -> void:
		var result := RuleEngine.resolve_battle(attacker, target)

		# Apply LP damage
		var defender_player := _find_controller(target, zm) if target != null \
			else _opponent(player, zm)
		if result.attacker_damage > 0:
			player.take_damage(result.attacker_damage)
		if result.defender_damage > 0:
			defender_player.take_damage(result.defender_damage)

		# Destroy cards
		if result.attacker_destroyed:
			zm.move(attacker, zm.graveyard_of(attacker.controller),
				ZoneManager.MoveReason.BATTLE_DESTROY)
		if result.target_destroyed and target != null:
			zm.move(target, zm.graveyard_of(target.controller),
				ZoneManager.MoveReason.BATTLE_DESTROY)

		# Fire damage events for triggers
		if result.attacker_damage > 0:
			stack.evaluate_triggers(
				GameEvent.damage_dealt(result.attacker_damage, player, defender_player, true), zm)
		if result.defender_damage > 0:
			stack.evaluate_triggers(
				GameEvent.damage_dealt(result.defender_damage, defender_player, player, true), zm)

		tm.end_damage_step()

	func _find_controller(card: CardInstance, _zm: ZoneManager) -> Player:
		return card.controller

	func _opponent(p: Player, zm: ZoneManager) -> Player:
		for zone in zm._zones.values():
			if zone.owner != null and zone.owner != p:
				return zone.owner
		return p

	func describe() -> String:
		return "Resolve battle: %s vs %s" % [
			attacker.definition.card_name,
			target.definition.card_name if target else "direct"
		]


# ══════════════════════════════════════════════════════════════════════════════
# CHANGE BATTLE POSITION
# ══════════════════════════════════════════════════════════════════════════════

class ChangeBattlePositionAction extends GameAction:
	var card:         CardInstance
	var new_position: CardDefinition.Position

	static func make(
		p:   Player,
		c:   CardInstance,
		pos: CardDefinition.Position
	) -> ChangeBattlePositionAction:
		var a          := ChangeBattlePositionAction.new()
		a.player       = p
		a.card         = c
		a.new_position = pos
		return a

	func validate(_zm: ZoneManager, tm: TurnManager, _stack: EffectStack) -> RuleResult:
		return RuleEngine.can_change_battle_position(card, player, tm.context)

	func execute(_zm: ZoneManager, _tm: TurnManager, _stack: EffectStack) -> void:
		card.position = new_position
		if new_position == CardDefinition.Position.ATK:
			card.face_state = CardInstance.FaceState.FACE_UP
		card.set_flag(&"position_changed_this_turn")

	func describe() -> String:
		return "Change %s to %s" % [
			card.definition.card_name,
			"ATK" if new_position == CardDefinition.Position.ATK else "DEF"
		]


# ══════════════════════════════════════════════════════════════════════════════
# PASS PRIORITY
# ══════════════════════════════════════════════════════════════════════════════

class PassPriorityAction extends GameAction:
	static func make(p: Player) -> PassPriorityAction:
		var a    := PassPriorityAction.new()
		a.player = p
		return a

	func validate(_zm: ZoneManager, _tm: TurnManager, stack: EffectStack) -> RuleResult:
		if stack.state != EffectStack.StackState.OPEN_WINDOW:
			return RuleResult.fail(RuleResult.Reason.CHAIN_OPEN,
				"No open priority window to pass.")
		if stack.priority_holder != player:
			return RuleResult.fail(RuleResult.Reason.NOT_YOUR_PRIORITY,
				"You don't hold priority.")
		return RuleResult.ok()

	func execute(_zm: ZoneManager, _tm: TurnManager, stack: EffectStack) -> void:
		stack.pass_priority(player)

	func describe() -> String:
		return "%s passes priority" % player.display_name


# ══════════════════════════════════════════════════════════════════════════════
# ADVANCE PHASE
# ══════════════════════════════════════════════════════════════════════════════

class AdvancePhaseAction extends GameAction:
	static func make(p: Player) -> AdvancePhaseAction:
		var a    := AdvancePhaseAction.new()
		a.player = p
		return a

	func validate(_zm: ZoneManager, tm: TurnManager, stack: EffectStack) -> RuleResult:
		if not stack.is_idle():
			return RuleResult.fail(RuleResult.Reason.CHAIN_OPEN,
				"Cannot advance phase while chain is open.")
		if tm.context.turn_player != player:
			return RuleResult.fail(RuleResult.Reason.NOT_YOUR_TURN,
				"Only the turn player can advance the phase.")
		return RuleResult.ok()

	func execute(_zm: ZoneManager, tm: TurnManager, _stack: EffectStack) -> void:
		tm.advance_phase()

	func describe() -> String:
		return "Advance phase"
