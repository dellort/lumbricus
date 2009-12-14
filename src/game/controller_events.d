module game.controller_events;

//The idea behind this file is to have the whole "plugin interface" in a single
//  place, so when developing a plugin, you know where to look for available
//  events, instead of having to browse the whole code for declare() calls

import game.controller;
import game.game;
import game.gobject;
import game.sprite;
import game.crate;
import game.events;
import game.gamemodes.base;
import game.weapon.weapon;
import game.temp;
import utils.md;
import utils.reflection;
import utils.factory;

enum WormEvent {
    wormStartDie,   //starting to blow itself up
    wormDie,        //done blowing up
    wormDrown,      //death by drowning (reached ocean floor)
    wormActivate,
    wormDeactivate,
}

enum TeamEvent {
    skipTurn,
    surrender,
}

//note how all events could be moved to better places (unlike before)
//xxx: move all events where they belong to

//xxx: sender is a dummy object, should be controller or something
alias DeclareEvent!("game_start", GameObject) OnGameStart;
alias DeclareEvent!("game_end", GameObject) OnGameEnd;
alias DeclareEvent!("sudden_death", GameObject) OnSuddenDeath;
//victim, cause, damage
alias DeclareEvent!("damage", GObjectSprite, GameObject, float) OnDamage;
//cause, number of pixels
//apparently the victim is 0 to N bitmap based GameLandscapes
alias DeclareEvent!("demolish", GameObject, int) OnDemolish;
//xxx this should...
//  - be split in team events and actual worm events
//  - the actual worm events (drown, die) actually are general sprite events
//  - probably make TeamMembers GameObjects (and use it for the sender param)
//right now the sender is a dummy
alias DeclareEvent!("worm_event", GameObject, WormEvent, TeamMember) OnWormEvent;
//sprite firing the weapon, used weapon, refired
alias DeclareEvent!("fire_weapon", GObjectSprite, WeaponClass, bool) OnFireWeapon;
//xxx same as OnWormEvent
alias DeclareEvent!("team_event", GameObject, TeamEvent, Team) OnTeamEvent;
//oh look, this isn't a TeamEvent
//also called on a tie, with winner = null
//xxx team should be sender (that winner=null thing wouldn't work anymore)
alias DeclareEvent!("team_victory", GameObject, Team) OnVictory;
//sender is the newly dropped crate
alias DeclareEvent!("crate_drop", CrateSprite) OnCrateDrop;
//sender is the crate, first parameter is the collecting team member
alias DeclareEvent!("crate_collect", CrateSprite, TeamMember) OnCrateCollect;

//base class for custom plugins
//now I don't really know what the point of this class was anymore
abstract class GamePlugin : GameObject {
    protected {
        GameController controller;
    }

    this(GameEngine c) {
        super(c, "plugin");
        active = true;
        controller = engine.controller;
    }
    this(ReflectCtor c) {
        super(c);
    }

    override bool activity() {
        return false;
    }
}

//and another factory...
//plugins register here, so the Controller can load them
alias StaticFactory!("GamePlugins", GamePlugin, GameEngine)
    GamePluginFactory;
