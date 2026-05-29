## CardDefinition.gd
## Immutable data resource. One per card type in the database.
## Never modified at runtime — CardInstance wraps this.
class_name CardDefinition
extends Resource

# ─── Enums ────────────────────────────────────────────────────────────────────

enum CardType    { MONSTER, SPELL, TRAP }
enum Attribute   { DARK, LIGHT, EARTH, WATER, FIRE, WIND, DIVINE }
enum SpellType   { NORMAL, CONTINUOUS, EQUIP, FIELD, QUICK_PLAY, RITUAL }
enum TrapType    { NORMAL, CONTINUOUS, COUNTER }
enum MonsterKind { NORMAL, EFFECT, RITUAL, FUSION, SYNCHRO, XYZ, LINK, PENDULUM }
enum Position    { ATK, DEF, FACE_DOWN_DEF, FACE_DOWN_ATK }

# ─── Core Identity ─────────────────────────────────────────────────────────────

@export var card_id:    StringName  ## Unique key, e.g. &"dark_magician"
@export var card_name:  String
@export var card_type:  CardType
@export var card_text:  String
@export var artwork:    Texture2D

# ─── Monster-only Fields ───────────────────────────────────────────────────────

@export_group("Monster")
@export var attribute:    Attribute
@export var monster_type: String      ## "Dragon", "Spellcaster", etc.
@export var monster_kind: MonsterKind
@export var level:        int         ## Stars / Rank / Link Rating
@export var atk:          int
@export var def:          int         ## 0 for Link monsters

# ─── Spell/Trap Sub-type ──────────────────────────────────────────────────────

@export_group("Spell / Trap")
@export var spell_type: SpellType
@export var trap_type:  TrapType

# ─── Pendulum ─────────────────────────────────────────────────────────────────

@export_group("Pendulum")
@export var pendulum_scale:  int
@export var pendulum_effect: String

# ─── Effects ──────────────────────────────────────────────────────────────────

## Ordered list of effects; index matches CardInstance.used_effects keys.
## Untyped to avoid class parse-order issues — elements are EffectDefinition.
var effects: Array = []

# ─── Computed Helpers ─────────────────────────────────────────────────────────

func is_monster() -> bool:
	return card_type == CardType.MONSTER

func is_spell() -> bool:
	return card_type == CardType.SPELL

func is_trap() -> bool:
	return card_type == CardType.TRAP

func is_extra_deck_monster() -> bool:
	return monster_kind in [
		MonsterKind.FUSION,
		MonsterKind.SYNCHRO,
		MonsterKind.XYZ,
		MonsterKind.LINK,
	]

func is_main_deck_monster() -> bool:
	return is_monster() and not is_extra_deck_monster()

func can_be_normal_summoned() -> bool:
	return monster_kind in [MonsterKind.NORMAL, MonsterKind.EFFECT]

func requires_tribute() -> bool:
	return can_be_normal_summoned() and level >= 5

func tribute_count() -> int:
	if level >= 7:
		return 2
	if level >= 5:
		return 1
	return 0

func _to_string() -> String:
	return "CardDefinition(%s)" % card_name
