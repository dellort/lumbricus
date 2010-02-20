module game.controller_events;

//The idea behind this file is to have the whole "plugin interface" in a single
//  place, so when developing a plugin, you know where to look for available
//  events, instead of having to browse the whole code for declare() calls
//xxx: oh was that the idea?

import framework.i18n; //for LocalizedMessage
import game.controller;
import game.game;
import game.gobject;
import game.sprite;
import game.crate;
import game.events;
import game.gamemodes.base;
import game.weapon.weapon;
import game.temp;
import physics.misc;
import utils.configfile;
import utils.md;
import utils.factory;
import utils.vector2;

///let the client display a message (like it's done on round's end etc.)
///this is a bit complicated because message shall be translated on the
///client (i.e. one client might prefer Klingon, while the other is used
///to Latin); so msgid and args are passed to the translation functions
///this returns a value, that is incremented everytime a new message is
///available
///a random int is passed along, so all clients with the same locale
///will select the same message
struct GameMessage {
    LocalizedMessage lm;
    Team actor;    //who did the action (for message color), null for neutral
    Team viewer;   //who should see it (only players with Team
                   //  in getOwnedTeams() see the message), null for all
}

//note how all events could be moved to better places (unlike before)
//xxx: move all events where they belong to
//  leaving them here until we figure out how events should work

//xxx: sender is a dummy object, should be controller or something
alias DeclareEvent!("game_start", GameObject) OnGameStart;
alias DeclareEvent!("game_end", GameObject) OnGameEnd;
alias DeclareEvent!("game_sudden_death", GameObject) OnSuddenDeath;
alias DeclareEvent!("game_message", GameObject, GameMessage) OnGameMessage;
//for test code
alias DeclareEvent!("game_init", GameObject) OnGameInit;
//add a HUD object to the GUI;
//  char[] id = type of the HUD object to add
//  Object info = status object, that is used to pass information to the HUD
alias DeclareEvent!("game_hud_add", GameObject, char[], Object) OnHudAdd;
//called when the game is loaded from savegame
//xxx this event is intederministic and must not have influence on game state
alias DeclareEvent!("game_reload", GameObject) OnGameReload;
//called on a non-fatal game error, with a message for the gui
alias DeclareEvent!("game_error", GameObject, char[]) OnGameError;
//victim, cause, type, damage
//  cause can be null (e.g. for fall damage)
alias DeclareEvent!("sprite_damage", Sprite, GameObject, DamageCause,
    float) OnDamage;
//well whatever this is
//should be avoided in scripting; the Vector2f will allocate a table
alias DeclareEvent!("sprite_impact", Sprite, Vector2f) OnSpriteImpact;
//cause, number of pixels
//apparently the victim is 0 to N bitmap based GameLandscapes
alias DeclareEvent!("demolish", GameObject, int) OnDemolish;
//called when sprite is finally dead (for worms: when done blowing up)
alias DeclareEvent!("sprite_die", Sprite) OnSpriteDie;
//on Sprite.waterStateChange()
alias DeclareEvent!("sprite_waterstate", Sprite) OnSpriteWaterState;
//with Sprite.activate()
alias DeclareEvent!("sprite_activate", Sprite) OnSpriteActivate;
//with Sprite.setState()
alias DeclareEvent!("sprite_setstate", StateSprite) OnSpriteSetState;
//whenever the glue status changes (checked/called every frame)
alias DeclareEvent!("sprite_gluechanged", Sprite) OnSpriteGlueChanged;
//physics.lifepower <= 0
alias DeclareEvent!("sprite_zerohp", Sprite) OnSpriteZeroHp;
//reached the ocean floor
//alias DeclareEvent!("sprite_drowned", Sprite) OnSpriteDrowned;
//starting to blow itself up
//xxx is this really needed
alias DeclareEvent!("team_member_start_die", TeamMember) OnTeamMemberStartDie;
alias DeclareEvent!("team_member_set_active", TeamMember, bool)
    OnTeamMemberSetActive;
//first time a team does an action (should probably be per team member?)
//xxx actually those should be WormControl events?
alias DeclareEvent!("team_on_first_action", Team) OnTeamFirstAction;
alias DeclareEvent!("team_member_on_lost_control", TeamMember) OnTeamMemberLostControl;
alias DeclareEvent!("team_set_active", Team, bool) OnTeamSetActive;
//sprite firing the weapon, used weapon, refired
alias DeclareEvent!("shooter_fire", Shooter, bool) OnFireWeapon;
alias DeclareEvent!("team_skipturn", Team) OnTeamSkipTurn;
alias DeclareEvent!("team_surrender", Team) OnTeamSurrender;
//the team wins; all OnVictory events will be raised before game_end (so you can
//  know exactly who wins, even if there can be 0 or >1 winners)
alias DeclareEvent!("team_victory", Team) OnVictory;
//sender is the newly dropped crate
alias DeclareEvent!("crate_drop", CrateSprite) OnCrateDrop;
//sender is the crate, first parameter is the collecting team member
alias DeclareEvent!("crate_collect", CrateSprite, TeamMember) OnCrateCollect;
//when a worm collects a tool from a crate
alias DeclareEvent!("collect_tool", TeamMember, CollectableTool) OnCollectTool;
//number of weapons changed
alias DeclareEvent!("weaponset_changed", WeaponSet) OnWeaponSetChanged;
//a crate is being blown up, and the crate contains this weapon
//  Sprite = the sprite for the crate
alias DeclareEvent!("weapon_crate_blowup", WeaponClass, Sprite)
    OnWeaponCrateBlowup;

//base class for custom plugins
//now I don't really know what the point of this class was anymore
//xxx: this is only for "compatibility"; GamePluginFactory now produces
//  GameObjects (not GamePlugins)
abstract class GamePlugin : GameObject {
    this(GameEngine c, ConfigNode opts) {
        super(c, "plugin");
        internal_active = true;
    }

    protected GameController controller() {
        return engine.controller;
    }

    override bool activity() {
        return false;
    }
}

//and another factory...
//plugins register here, so the Controller can load them
alias StaticFactory!("GamePlugins", GameObject, GameEngine, ConfigNode)
    GamePluginFactory;
