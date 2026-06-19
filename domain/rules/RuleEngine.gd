## RuleEngine.gd
## Stateless validator for all game actions.
## Every method is a pure function: (inputs) → RuleResult.
## Nothing here mutates game state — it only reads and judges.
##
## Consumers:
##   - BoardView / CardTooltip  → which actions to show the player
##   - GameDirector             → gate-keep before executing any action
##   - AI controller            → enumerate legal moves
##   - EffectStack              → validate effect activations
##
## All checks follow the same signature pattern:
##   can_X(relevant_cards, player, zm, ctx) → RuleResult
class_name RuleEngine
extends RefCounted

# ══════════════════════════════════════════════════════════════════════════════
# NORMAL SUMMON
# ══════════════════════════════════════════════════════════════════════════════

## Can `player` normal summon `card` this turn?
## `tribute_targets` are the monsters the player intends to tribute (may be empty).
static func can_normal_summon(
	card:             CardInstance,
	player:           Player,
	zm:               ZoneManager,
	ctx:              TurnContext,
	tribute_targets:  Array[CardInstance] = []
) -> RuleResult:

	# ── Phase ─────────────────────────────────────────────────────────────────
	if not ctx.is_main_phase():
		return RuleResult.fail(RuleResult.Reason.WRONG_PHASE,
			"Normal summon only allowed during Main Phase.")
  # ── Chain State ──────────────────────────────────────────────────────────
	if ctx.chain_open:
		return RuleResult.fail(RuleResult.Reason.CHAIN_OPEN,
			"Cannot summon while a chain is open.")
	if ctx.turn_player != player:
		return RuleResult.fail(RuleResult.Reason.NOT_YOUR_TURN,
			"Only the turn player can normal summon.")

	# ── Card must be a monster in hand ────────────────────────────────────────
	if not card.definition.is_monster():
		return RuleResult.fail(RuleResult.Reason.NOT_A_MONSTER,
			"%s is not a monster." % card.definition.card_name)

	if not card.is_in_hand():
		return RuleResult.fail(RuleResult.Reason.NOT_IN_HAND,
			"%s is not in hand." % card.definition.card_name)

	# ── Extra deck monsters cannot be normal summoned ─────────────────────────
	if card.definition.is_extra_deck_monster():
		return RuleResult.fail(RuleResult.Reason.WRONG_SUMMON_METHOD,
			"Extra Deck monsters cannot be Normal Summoned.")

	# ── Ritual monsters cannot be normal summoned ─────────────────────────────
	if card.definition.monster_kind == CardDefinition.MonsterKind.RITUAL:
		return RuleResult.fail(RuleResult.Reason.WRONG_SUMMON_METHOD,
			"Ritual monsters cannot be Normal Summoned.")

	# ── Normal summon count ───────────────────────────────────────────────────
	if player.normal_summons_remaining <= 0:
		return RuleResult.fail(RuleResult.Reason.NO_NORMAL_SUMMONS_LEFT,
			"No normal summons remaining this turn.")

	# ── Tribute check ─────────────────────────────────────────────────────────
	var required := card.definition.tribute_count()
	if required > 0:
		# Player must have enough monsters to tribute
		if zm.monster_count(player) < required:
			return RuleResult.fail(RuleResult.Reason.INSUFFICIENT_TRIBUTES,
				"Need %d tribute%s; you only control %d monster%s." % [
					required, "s" if required > 1 else "",
					zm.monster_count(player), "s" if zm.monster_count(player) != 1 else ""
				])

		# Validate the specific tribute targets provided
		if tribute_targets.size() > 0:
			if tribute_targets.size() < required:
				return RuleResult.fail(RuleResult.Reason.INSUFFICIENT_TRIBUTES,
					"Selected %d tribute%s but %d required." % [
						tribute_targets.size(), "s" if tribute_targets.size() != 1 else "",
						required
					])
			for tribute in tribute_targets:
				if tribute.controller != player:
					return RuleResult.fail(RuleResult.Reason.INSUFFICIENT_TRIBUTES,
						"Cannot tribute %s — you don't control it." % tribute.definition.card_name)
				if not tribute.is_on_field():
					return RuleResult.fail(RuleResult.Reason.INSUFFICIENT_TRIBUTES,
						"%s is not on the field." % tribute.definition.card_name)
	else:
		# No tribute needed — zone must have space after paying
		# (if requiring tribute, freed slot counts as open)
		if zm.monster_zone_of(player).is_full():
			return RuleResult.fail(RuleResult.Reason.MONSTER_ZONE_FULL,
				"Monster zone is full.")

	# ── Player flags ──────────────────────────────────────────────────────────
	if player.has_flag(&"cannot_normal_summon"):
		return RuleResult.fail(RuleResult.Reason.CANNOT_SPECIAL_SUMMON,
			"You cannot Normal Summon this turn.")

	# ── Card flags ────────────────────────────────────────────────────────────
	if card.has_flag(&"cannot_be_normal_summoned"):
		return RuleResult.fail(RuleResult.Reason.WRONG_SUMMON_METHOD,
			"%s cannot be Normal Summoned." % card.definition.card_name)

	return RuleResult.ok()


# ══════════════════════════════════════════════════════════════════════════════
# SPECIAL SUMMON
# ══════════════════════════════════════════════════════════════════════════════

## Can `card` be special summoned by `player` using `method`?
## Does NOT validate material requirements (those are effect-specific).
static func can_special_summon(
	card:    CardInstance,
	player:  Player,
	zm:      ZoneManager,
	ctx:     TurnContext,
	method:  StringName = &"effect"
) -> RuleResult:

	if card.has_flag(&"cannot_be_special_summoned"):
		return RuleResult.fail(RuleResult.Reason.CANNOT_SPECIAL_SUMMON,
			"%s cannot be Special Summoned." % card.definition.card_name)

	if player.has_flag(&"cannot_special_summon"):
		return RuleResult.fail(RuleResult.Reason.CANNOT_SPECIAL_SUMMON,
			"You cannot Special Summon this turn.")

	# Extra deck monsters go to the extra monster zone
	if card.definition.is_extra_deck_monster():
		var emz := zm.get_player_zone(player, Zone.ZoneType.EXTRA_MONSTER)
		if emz.is_full():
			return RuleResult.fail(RuleResult.Reason.EXTRA_DECK_ZONE_FULL,
				"Extra Monster Zone is full.")
	else:
		if zm.monster_zone_of(player).is_full():
			return RuleResult.fail(RuleResult.Reason.MONSTER_ZONE_FULL,
				"Monster zone is full.")

	return RuleResult.ok()


# ══════════════════════════════════════════════════════════════════════════════
# SET
# ══════════════════════════════════════════════════════════════════════════════

## Can `player` set `card` face-down?
static func can_set(
	card:   CardInstance,
	player: Player,
	zm:     ZoneManager,
	ctx:    TurnContext
) -> RuleResult:

	if not ctx.is_main_phase():
		return RuleResult.fail(RuleResult.Reason.WRONG_PHASE,
			"Cards can only be set during the Main Phase.")
	if ctx.chain_open: # ← Add this
		return RuleResult.fail(RuleResult.Reason.CHAIN_OPEN,
			"Cannot set cards while a chain is open.")
	if ctx.turn_player != player:
		return RuleResult.fail(RuleResult.Reason.NOT_YOUR_TURN)

	if not card.is_in_hand():
		return RuleResult.fail(RuleResult.Reason.NOT_IN_HAND,
			"%s must be in hand to set." % card.definition.card_name)

	if card.definition.is_monster():
		# Monsters can be set (face-down DEF) — counts as a normal summon
		if player.normal_summons_remaining <= 0:
			return RuleResult.fail(RuleResult.Reason.NO_NORMAL_SUMMONS_LEFT,
				"Setting a monster uses your normal summon.")
		if card.definition.requires_tribute():
			return RuleResult.fail(RuleResult.Reason.WRONG_SUMMON_METHOD,
				"Level 5+ monsters cannot be set without tribute.")
		if zm.monster_zone_of(player).is_full():
			return RuleResult.fail(RuleResult.Reason.MONSTER_ZONE_FULL)
		return RuleResult.ok()

	if card.definition.is_spell() or card.definition.is_trap():
		if zm.spell_zone_of(player).is_full():
			return RuleResult.fail(RuleResult.Reason.SPELL_ZONE_FULL,
				"Spell/Trap zone is full.")
		# Quick-play spells can be set, normal spells can be set, traps must be set
		return RuleResult.ok()

	return RuleResult.fail(RuleResult.Reason.CANNOT_SET,
		"%s cannot be set." % card.definition.card_name)


# ══════════════════════════════════════════════════════════════════════════════
# ATTACK
# ══════════════════════════════════════════════════════════════════════════════

## Can `attacker` declare an attack against `target`?
## Pass target = null for a direct attack check.
static func can_attack(
	attacker: CardInstance,
	target:   CardInstance,   ## null = direct attack
	player:   Player,
	zm:       ZoneManager,
	ctx:      TurnContext
) -> RuleResult:

	# ── Phase ─────────────────────────────────────────────────────────────────
	if not ctx.is_battle_phase():
		return RuleResult.fail(RuleResult.Reason.NOT_BATTLE_PHASE,
			"Attacks can only be declared during the Battle Phase.")

	if ctx.turn_player != player:
		return RuleResult.fail(RuleResult.Reason.NOT_YOUR_TURN)

	if ctx.chain_open:
		return RuleResult.fail(RuleResult.Reason.CHAIN_OPEN,
			"Cannot declare an attack while a chain is open.")

	# ── Attacker validity ─────────────────────────────────────────────────────
	if not attacker.is_on_field():
		return RuleResult.fail(RuleResult.Reason.NOT_A_FIELD_MONSTER,
			"%s is not on the field." % attacker.definition.card_name)

	if not attacker.definition.is_monster():
		return RuleResult.fail(RuleResult.Reason.NOT_A_FIELD_MONSTER)

	if attacker.controller != player:
		return RuleResult.fail(RuleResult.Reason.NOT_YOUR_TURN,
			"You don't control %s." % attacker.definition.card_name)

	if not attacker.is_face_up():
		return RuleResult.fail(RuleResult.Reason.CANNOT_ATTACK,
			"Face-down monsters cannot attack.")

	if not attacker.is_in_atk_position():
		return RuleResult.fail(RuleResult.Reason.CANNOT_ATTACK,
			"Monsters in DEF position cannot attack.")

	if attacker.has_attacked:
		return RuleResult.fail(RuleResult.Reason.ALREADY_ATTACKED,
			"%s has already attacked this turn." % attacker.definition.card_name)

	if attacker.has_flag(&"cannot_attack"):
		return RuleResult.fail(RuleResult.Reason.CANNOT_ATTACK,
			"%s cannot attack." % attacker.definition.card_name)

	# Summoning sickness: normal summoned monsters can't attack same turn
	if attacker.has_summoning_sickness(ctx.turn_number):
		return RuleResult.fail(RuleResult.Reason.SUMMONING_SICKNESS,
			"%s cannot attack the turn it was Normal Summoned." % attacker.definition.card_name)

	# ── Target validity ───────────────────────────────────────────────────────
	var opponent := _opponent_of(player, zm)
	if opponent == null:
		return RuleResult.fail(RuleResult.Reason.NO_VALID_ATTACK_TARGET, "No opponent found.")

	if target == null:
		# Direct attack: only allowed when opponent has no monsters
		if zm.monster_count(opponent) > 0:
			return RuleResult.fail(RuleResult.Reason.DIRECT_ATTACK_BLOCKED,
				"Cannot attack directly while opponent controls monsters.")
		# Check if any opponent monster has "must be attacked" flag — not applicable here
		return RuleResult.ok()

	# Attack against a specific target
	if not target.is_on_field():
		return RuleResult.fail(RuleResult.Reason.NO_VALID_ATTACK_TARGET,
			"%s is not on the field." % target.definition.card_name)

	if target.controller == player:
		return RuleResult.fail(RuleResult.Reason.NO_VALID_ATTACK_TARGET,
			"Cannot attack your own monster.")

	if not target.definition.is_monster():
		return RuleResult.fail(RuleResult.Reason.NO_VALID_ATTACK_TARGET,
			"Can only attack monsters.")

	if target.has_flag(&"cannot_be_attacked"):
		return RuleResult.fail(RuleResult.Reason.NO_VALID_ATTACK_TARGET,
			"%s cannot be attacked." % target.definition.card_name)

	# If opponent has a monster with "must be attacked first" flag, enforce it
	var must_attack_first := _find_must_attack_first(opponent, zm)
	if must_attack_first != null and target != must_attack_first:
		return RuleResult.fail(RuleResult.Reason.NO_VALID_ATTACK_TARGET,
			"%s must be attacked first." % must_attack_first.definition.card_name)

	return RuleResult.ok()


## Returns all legal attack targets for `attacker`, including null for direct attack.
static func get_attack_targets(
	attacker: CardInstance,
	player:   Player,
	zm:       ZoneManager,
	ctx:      TurnContext
) -> Array:   ## Array[CardInstance?]
	var targets: Array = []
	var opponent := _opponent_of(player, zm)
	if opponent == null:
		return targets

	var opp_monsters := zm.monsters_on_field(opponent)
	if opp_monsters.is_empty():
		# Direct attack is the only option
		if can_attack(attacker, null, player, zm, ctx).valid:
			targets.append(null)
	else:
		var must_first := _find_must_attack_first(opponent, zm)
		for monster in opp_monsters:
			var check_target := must_first if must_first != null else monster
			if can_attack(attacker, check_target, player, zm, ctx).valid:
				targets.append(monster)
			if must_first != null:
				break  ## Only that one target is valid

	return targets


# ══════════════════════════════════════════════════════════════════════════════
# BATTLE DAMAGE RESOLUTION
# ══════════════════════════════════════════════════════════════════════════════

## Resolve the outcome of attacker vs target.
## Returns a BattleResult describing what happens.
static func resolve_battle(
	attacker: CardInstance,
	target:   CardInstance   ## null = direct attack
) -> BattleResult:
	var result := BattleResult.new()
	result.attacker = attacker
	result.target   = target

	if target == null:
		# Direct attack
		result.attacker_damage    = 0
		result.defender_damage    = attacker.get_atk()
		result.attacker_destroyed = false
		result.target_destroyed   = false
		return result

	var atk_val  := attacker.get_atk()
	var def_face_up := target.is_face_up()

	if not def_face_up:
		# Flip the target face-up for damage calculation
		target.face_state = CardInstance.FaceState.FACE_UP

	var def_atk := target.get_atk()
	var def_def := target.get_def()

	if target.is_in_atk_position():
		# ATK vs ATK
		if atk_val > def_atk:
			result.defender_damage    = atk_val - def_atk
			result.target_destroyed   = true
		elif atk_val < def_atk:
			result.attacker_damage    = def_atk - atk_val
			result.attacker_destroyed = true
		else:
			# Tie — both destroyed, no damage
			result.attacker_destroyed = true
			result.target_destroyed   = true
	else:
		# ATK vs DEF
		if atk_val > def_def:
			result.target_destroyed  = true
			# Piercing: only if attacker has flag
			if attacker.has_flag(&"piercing"):
				result.defender_damage = atk_val - def_def
		elif atk_val < def_def:
			result.attacker_damage = def_def - atk_val
		# Equal: nothing happens

	return result


# ══════════════════════════════════════════════════════════════════════════════
# EFFECT ACTIVATION
# ══════════════════════════════════════════════════════════════════════════════

## Can `player` activate effect at `effect_index` on `card`?
static func can_activate_effect(
	card:         CardInstance,
	effect_index: int,
	player:       Player,
	zm:           ZoneManager,
	ctx:          TurnContext,
	stack:        EffectStack
) -> RuleResult:
	
	# ── Basic guards ──────────────────────────────────────────────────────────
	if card.definition.effects.is_empty():
		return RuleResult.fail(RuleResult.Reason.NO_EFFECTS)

	if effect_index < 0 or effect_index >= card.definition.effects.size():
		return RuleResult.fail(RuleResult.Reason.EFFECT_NOT_FOUND,
			"Effect index %d out of range." % effect_index)

	var eff: EffectDefinition = card.definition.effects[effect_index]

	# ── Continuous effects don't activate ─────────────────────────────────────
	if eff.is_continuous:
		return RuleResult.fail(RuleResult.Reason.CONTINUOUS_ALREADY_ACTIVE,
			"Continuous effects are always active — they don't activate.")

	# ── Priority ──────────────────────────────────────────────────────────────
	if stack.priority_holder != player:
		print("not your prio")
		return RuleResult.fail(RuleResult.Reason.NOT_YOUR_PRIORITY,
			"You don't hold priority.")
	if ctx.chain_open and not stack.chain_is_empty():
		# Can activate effects only if you have priority
		if stack.priority_holder != player:
			return RuleResult.fail(RuleResult.Reason.CHAIN_OPEN,
				"Cannot activate while chain is open and you don't have priority.")
	# ── Spell speed ───────────────────────────────────────────────────────────
	if not stack.chain_is_empty():
		var min_speed := stack.minimum_spell_speed()
		if eff.spell_speed < min_speed:
			print("spell speed too low")
			return RuleResult.fail(RuleResult.Reason.SPELL_SPEED_TOO_LOW,
				"Spell Speed %d cannot be chained to Spell Speed %d." % [
					eff.spell_speed, min_speed
				])
	# ── Chain link requirement check ─────────────────────────────────────────
	if not stack.chain_is_empty():
		var current_depth := stack.depth()
		
		# The new link will be at depth + 1
		var new_link_number := current_depth + 1
		
		# Check exact chain link
		if eff.exact_chain_link > 0:
			if new_link_number != eff.exact_chain_link:
				return RuleResult.fail(RuleResult.Reason.CONDITIONS_NOT_MET,
					"This effect must be Chain Link %d (current would be %d)" % [eff.exact_chain_link, new_link_number])
		
		# Check minimum chain link
		if eff.min_chain_link > 0:
			if new_link_number < eff.min_chain_link:
				return RuleResult.fail(RuleResult.Reason.CONDITIONS_NOT_MET,
					"This effect requires Chain Link %d or higher (current would be %d)" % [eff.min_chain_link, new_link_number])
		
		# Check maximum chain link
		if eff.max_chain_link > 0:
			if new_link_number > eff.max_chain_link:
				return RuleResult.fail(RuleResult.Reason.CONDITIONS_NOT_MET,
					"This effect requires Chain Link %d or lower (current would be %d)" % [eff.max_chain_link, new_link_number])
	else:
		# Chain is empty - new link will be CL1
		if eff.min_chain_link > 1:
			return RuleResult.fail(RuleResult.Reason.CONDITIONS_NOT_MET,
				"This effect cannot be Chain Link 1 - requires CL%d or higher" % eff.min_chain_link)
		
		if eff.exact_chain_link > 1:
			return RuleResult.fail(RuleResult.Reason.CONDITIONS_NOT_MET,
				"This effect must be Chain Link %d" % eff.exact_chain_link)
	# Chain condition check — e.g. Ash Blossom only chains to search/draw/SS effects
	if not eff.chain_condition.is_null() and not stack.chain_is_empty():
		var top := stack.top_link()
		if not eff.chain_condition.call(top):
			print("conditions not met for ",card.definition.card_name)
			return RuleResult.fail(RuleResult.Reason.CONDITIONS_NOT_MET,
				"This effect cannot be chained to that effect.")
	# ── Once-per-turn-per-player ──────────────────────────────────────────────
	if eff.once_per_turn_per_player:
		if stack.was_player_effect_used_this_turn(player,card.definition.card_id,effect_index,ctx.turn_number):
			print("opt")
			return RuleResult.fail(RuleResult.Reason.ONCE_PER_TURN_USED,
			"%s's effect can only be used once per turn per name." % card.definition.card_name)
	# ── Once-per-turn ─────────────────────────────────────────────────────────
	if eff.once_per_turn and card.was_effect_used_this_turn(effect_index, ctx.turn_number):
		print("opt per card")
		return RuleResult.fail(RuleResult.Reason.ONCE_PER_TURN_USED,
			"%s's effect can only be used once per turn." % card.definition.card_name)

	if eff.once_per_duel and card.was_effect_used_this_duel(effect_index):
		print("opd per card")
		return RuleResult.fail(RuleResult.Reason.ONCE_PER_DUEL_USED,
			"%s's effect can only be used once per duel." % card.definition.card_name)

	# ── Phase / timing ────────────────────────────────────────────────────────
	var timing_result := _check_timing(eff, card, player, ctx, stack)
	if not timing_result.valid:
		print("no valid timing")
		return timing_result

	# ── Conditions ────────────────────────────────────────────────────────────
	for condition in eff.conditions:
		if not condition.evaluate(card, zm, player):
			return RuleResult.fail(RuleResult.Reason.CONDITIONS_NOT_MET,
				condition.describe())

	# ── Cost payability ───────────────────────────────────────────────────────
	if not EffectCost.CostExecutor.can_pay_all(eff, card, zm, player):
		return RuleResult.fail(RuleResult.Reason.COST_CANNOT_BE_PAID,
			"Cannot pay the activation cost: %s" % EffectCost.CostExecutor.describe_all(eff))

	# ── Targeting ─────────────────────────────────────────────────────────────
	if eff.targets_required > 0:
		var legal_targets := get_legal_targets(eff, player, zm)
		if legal_targets.size() < eff.targets_required:
			return RuleResult.fail(RuleResult.Reason.NO_VALID_TARGET,
				"Need %d target%s; only %d legal target%s available." % [
					eff.targets_required,
					"s" if eff.targets_required > 1 else "",
					legal_targets.size(),
					"s" if legal_targets.size() != 1 else ""
				])

	return RuleResult.ok()


## Returns all cards that are legal targets for `effect` activated by `player`.
static func get_legal_targets(
	effect: EffectDefinition,
	player: Player,
	zm:     ZoneManager
) -> Array[CardInstance]:
	var candidates: Array[CardInstance] = []

	# Collect all on-field cards as initial candidate pool
	for zone in zm.all_field_zones():
		candidates.append_array(zone.get_cards())

	# Filter by target conditions
	return candidates.filter(func(card: CardInstance) -> bool:
		for cond in effect.target_conditions:
			if not cond.evaluate(card, zm, player):
				return false
		return true
	)


## Returns all effects on `card` that `player` can currently activate.
static func get_activatable_effects(
	card:   CardInstance,
	player: Player,
	zm:     ZoneManager,
	ctx:    TurnContext,
	stack:  EffectStack
) -> Array:   ## Array[int] — indices into card.definition.effects
	var result: Array = []
	for i in card.definition.effects.size():
		if can_activate_effect(card, i, player, zm, ctx, stack).valid:
			result.append(i)
	return result


# ══════════════════════════════════════════════════════════════════════════════
# CHANGE BATTLE POSITION
# ══════════════════════════════════════════════════════════════════════════════

static func can_change_battle_position(
	card:   CardInstance,
	player: Player,
	ctx:    TurnContext
) -> RuleResult:

	if not ctx.is_main_phase():
		return RuleResult.fail(RuleResult.Reason.WRONG_PHASE,
			"Can only change battle position during Main Phase.")
	if ctx.chain_open: # ← Add this
		return RuleResult.fail(RuleResult.Reason.CHAIN_OPEN,
			"Cannot change position while a chain is open.")
	if ctx.turn_player != player:
		return RuleResult.fail(RuleResult.Reason.NOT_YOUR_TURN)

	if not card.is_on_field():
		return RuleResult.fail(RuleResult.Reason.NOT_ON_FIELD)

	if card.controller != player:
		return RuleResult.fail(RuleResult.Reason.NOT_YOUR_TURN,
			"You don't control %s." % card.definition.card_name)

	if not card.is_face_up():
		return RuleResult.fail(RuleResult.Reason.CANNOT_CHANGE_POSITION,
			"Cannot change position of a face-down monster this way.")

	if card.has_flag(&"position_changed_this_turn"):
		return RuleResult.fail(RuleResult.Reason.CANNOT_CHANGE_POSITION,
			"%s already changed position this turn." % card.definition.card_name)

	if card.has_summoning_sickness(ctx.turn_number):
		return RuleResult.fail(RuleResult.Reason.CANNOT_CHANGE_POSITION,
			"%s cannot change position the turn it was Normal Summoned." % card.definition.card_name)

	if card.has_flag(&"cannot_change_position"):
		return RuleResult.fail(RuleResult.Reason.CANNOT_CHANGE_POSITION)

	return RuleResult.ok()


# ══════════════════════════════════════════════════════════════════════════════
# LEGAL ACTIONS  (aggregate — used by AI and tooltip)
# ══════════════════════════════════════════════════════════════════════════════

## All actions `player` can legally take right now.
## Returns a dictionary keyed by action type for fast lookup.
static func get_all_legal_actions(
	player: Player,
	zm:     ZoneManager,
	ctx:    TurnContext,
	stack:  EffectStack
) -> LegalActions:
	var la := LegalActions.new()
	
	# Summoning and setting - from hand
	for card in zm.hand_of(player).get_cards():
		if can_normal_summon(card, player, zm, ctx).valid:
			la.can_normal_summon.append(card)  # ← Blue glow
		if can_set(card, player, zm, ctx).valid:
			la.can_set.append(card)
		var activatable := get_activatable_effects(card, player, zm, ctx, stack)
		if not activatable.is_empty():
			la.can_activate[card] = activatable  # ← Yellow/Orange glow
	
	# Field actions
	for card in zm.all_cards_on_field(player):
		if card.definition.is_monster() and ctx.is_battle_phase():
			var targets := get_attack_targets(card, player, zm, ctx)
			if not targets.is_empty():
				la.can_attack[card] = targets
		var activatable := get_activatable_effects(card, player, zm, ctx, stack)
		if not activatable.is_empty():
			la.can_activate[card] = activatable  # ← Yellow/Orange glow
		if can_change_battle_position(card, player, ctx).valid:
			la.can_change_position.append(card)
	
	return la


# ══════════════════════════════════════════════════════════════════════════════
# TIMING HELPER
# ══════════════════════════════════════════════════════════════════════════════

static func _check_timing(
	eff:    EffectDefinition,
	card:   CardInstance,
	player: Player,
	ctx:    TurnContext,
	stack:  EffectStack
) -> RuleResult:

	match eff.category:
		EffectDefinition.EffectCategory.IGNITION:
			# Ignition effects: main phase only, turn player only, chain must be empty
			if not ctx.is_main_phase():
				return RuleResult.fail(RuleResult.Reason.WRONG_TIMING,
					"Ignition effects can only be activated during Main Phase.")
			if ctx.turn_player != player:
				return RuleResult.fail(RuleResult.Reason.WRONG_TIMING,
					"Only the turn player can activate Ignition effects.")
			if not stack.chain_is_empty():
				return RuleResult.fail(RuleResult.Reason.WRONG_TIMING,
					"Cannot activate an Ignition effect while a chain is open.")

		EffectDefinition.EffectCategory.QUICK:
			# Quick effects (Spell Speed 2): any time player has priority
			# Can be during opponent's turn
			pass  ## Priority already checked in can_activate_effect

		EffectDefinition.EffectCategory.TRIGGER:
			# Trigger effects are auto-evaluated by EffectStack.evaluate_triggers()
			# If we're here, it means a player is manually confirming an optional trigger
			pass

		EffectDefinition.EffectCategory.CONTINUOUS:
			return RuleResult.fail(RuleResult.Reason.CONTINUOUS_ALREADY_ACTIVE)

	# Damage step restrictions
	if ctx.is_damage_step():
		# Only specific effect types are allowed in the damage step
		if eff.spell_speed < 3 and eff.category != EffectDefinition.EffectCategory.TRIGGER:
			if not card.has_flag(&"can_activate_in_damage_step"):
				return RuleResult.fail(RuleResult.Reason.WRONG_TIMING,
					"This effect cannot be activated during the Damage Step.")

	return RuleResult.ok()


# ══════════════════════════════════════════════════════════════════════════════
# INTERNAL HELPERS
# ══════════════════════════════════════════════════════════════════════════════

static func _opponent_of(player: Player, zm: ZoneManager) -> Player:
	for zone in zm._zones.values():
		if zone.owner != null and zone.owner != player:
			return zone.owner
	return null

static func _find_must_attack_first(opponent: Player, zm: ZoneManager) -> CardInstance:
	for card in zm.monsters_on_field(opponent):
		if card.has_flag(&"must_be_attacked_first"):
			return card
	return null


# ══════════════════════════════════════════════════════════════════════════════
# BATTLE RESULT  (inner value type)
# ══════════════════════════════════════════════════════════════════════════════

class BattleResult extends RefCounted:
	var attacker:          CardInstance = null
	var target:            CardInstance = null  ## null = direct attack
	var attacker_destroyed: bool = false
	var target_destroyed:   bool = false
	var attacker_damage:    int  = 0   ## LP lost by attacker's controller
	var defender_damage:    int  = 0   ## LP lost by defender's controller

	func is_direct_attack() -> bool:
		return target == null

	func _to_string() -> String:
		if is_direct_attack():
			return "BattleResult(direct: %d damage)" % defender_damage
		return "BattleResult(%s vs %s — atk_destroyed=%s def_destroyed=%s atk_dmg=%d def_dmg=%d)" % [
			attacker.definition.card_name,
			target.definition.card_name,
			attacker_destroyed, target_destroyed,
			attacker_damage, defender_damage
		]
