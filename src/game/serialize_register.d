//this module contains calls to register all classes for serialization
//actually, not really "all", but most
module game.serialize_register;

import utils.reflection;

import framework.timesource;
import game.actionsprite, game.controller, game.crate, game.game,
    game.gamepublic, game.glevel, game.sprite, game.worm,
    game.weapon.actionweapon, game.weapon.projectile,
    game.weapon.ray, game.weapon.rope, game.weapon.weapon,
    game.weapon.napalm, game.weapon.melee, game.weapon.jetpack, game.sequence,
    game.gamemodes.turnbased, game.gamemodes.turnbased_shared,
    game.gamemodes.mdebug, game.gamemodes.realtime, game.weapon.drill,
    game.controller_plugins, game.levelgen.renderer, game.action.base,
    game.action.list, game.action.weaponactions, game.action.spriteactions,
    game.action.spawn, game.action.wcontext, game.action.common;
import physics.world;
import utils.random;

import game.gameshell : serialize_types;

void initGameSerialization() {
    serialize_types = new Types();
    serialize_types.registerClasses!(Random, GameEngine, PhysicWorld,
        GameController, WormSprite, GameLandscape, ActionContext,
        ActionSprite, GameController, ActionListRunner, ControlRotateAction,
        ServerTeam, ServerTeamMember, WeaponSet, WeaponItem, CollectableBomb,
        CollectableWeapon, CollectableMedkit, CrateSprite, GameLandscape,
        LandscapeGeometry, GObjectSprite, BeamHandler, ActionShooter,
        ProjectileSprite, RayShooter, RenderLaser, Sequence,
        SequenceUpdate, Jetpack, Rope, Drill, WormSprite, WormSelectHelper,
        GravestoneSprite, WormSequenceUpdate, WrapFireInfo, RandomJumpAction,
        GameEngineGraphics, AnimationGraphic, LineGraphic, TextGraphic,
        CrosshairGraphic, LandscapeGraphic, NapalmSequenceUpdate,
        NapalmSprite, ModeTurnbased, ModeDebug, TimeSource, StuckTriggerAction,
        TimeSourceFixFramerate, TurnbasedStatus, HomingAction, SpriteAction,
        MeleeWeapon, MeleeShooter, WeaponContext, DelayedObj,
        ModeRealtime, RealtimeStatus, CollectableToolCrateSpy,
        CollectableToolDoubleTime, ControllerMsgs, ControllerStats,
        ControllerPersistence, CollectableToolDoubleDamage, LandscapeBitmap,
        GravityCenterAction, ProximitySensorAction, WalkerAction);
    //stuff that is actually redundant and wouldn't need to be in savegames
    //but excluding this from savegames would be too much work for nothing
    //keeping them separate still makes sense if we ever need faster snapshots
    //(all data stored by these classes doesn't or shouldn't change, and thus
    // doesn't need to be snapshotted)
    serialize_types.registerClasses!(ActionContainer, ActionListClass,
        ActionStateInfo, ActionSpriteClass, CrateSpriteClass,
        StaticStateInfo, GOSpriteClass,
        ActionWeapon, ProjectileStateInfo, ProjectileSpriteClass,
        RayWeapon, JetpackClass, RopeClass, SpawnActionClass,
        ImpulseActionClass, AoEDamageActionClass,
        WormStateInfo, WormSpriteClass, GravestoneSpriteClass,
        SequenceStateList, NapalmStateDisplay, NapalmState, WormStateDisplay,
        SubSequence, WormState, NapalmSpriteClass,
        ProjectileStateInfo, CrateStateInfo, DrillClass);
    actionSerializeRegister(serialize_types);
}
