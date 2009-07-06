//this module contains calls to register all classes for serialization
//actually, not really "all", but most
module game.serialize_register;

import utils.reflection;

import framework.timesource;
import game.action, game.actionsprite, game.controller, game.crate, game.game,
    game.gamepublic, game.glevel, game.spriteactions, game.sprite, game.worm,
    game.weapon.actions, game.weapon.actionweapon, game.weapon.projectile,
    game.weapon.ray, game.weapon.spawn, game.weapon.rope, game.weapon.weapon,
    game.weapon.napalm, game.weapon.melee, game.weapon.jetpack, game.sequence,
    game.gamemodes.turnbased, game.gamemodes.turnbased_shared,
    game.gamemodes.mdebug, game.gamemodes.realtime, game.weapon.drill,
    game.controller_plugins;
import physics.world;
import utils.random;

import game.gameshell : serialize_types;

void initGameSerialization() {
version(Posix) {
    serialize_types = new Types();
    serialize_types.registerClasses!(Random, GameEngine, PhysicWorld,
        GameController, WormSprite, GameLandscape, ActionContext, ActionList,
        TimedAction, ActionSprite, GameController,
        ServerTeam, ServerTeamMember, WeaponSet, WeaponItem, CollectableBomb,
        CollectableWeapon, CollectableMedkit, CrateSprite, GameLandscape,
        LandscapeGeometry, SpriteAction, SetStateAction, GravityCenterAction,
        ProximitySensorAction, WalkerAction, RandomJumpAction,
        StuckTriggerAction, GObjectSprite, WeaponAction, ExplosionAction,
        BeamAction, InsertBitmapAction, EarthquakeAction, ActionShooter,
        ProjectileSprite, HomingAction, RayShooter, RenderLaser, Sequence,
        SequenceUpdate, SpawnAction, Jetpack, Rope, Drill, WormSprite,
        GravestoneSprite, WormSequenceUpdate, WrapFireInfo,
        GameEngineGraphics, AnimationGraphic, LineGraphic, TextGraphic,
        CrosshairGraphic, LandscapeGraphic, NapalmSequenceUpdate,
        NapalmSprite, ModeTurnbased, ModeDebug, TimeSource,
        TimeSourceFixFramerate, DieAction, TurnbasedStatus,
        TeamAction, AoEDamageAction, ImpulseAction, MeleeWeapon, MeleeShooter,
        ModeRealtime, RealtimeStatus, CollectableToolCrateSpy,
        CollectableToolDoubleTime, ControllerMsgs, ControllerStats,
        ControllerPersistence, CollectableToolDoubleDamage);
    //stuff that is actually redundant and wouldn't need to be in savegames
    //but excluding this from savegames would be too much work for nothing
    //keeping them separate still makes sense if we ever need faster snapshots
    //(all data stored by these classes doesn't or shouldn't change, and thus
    // doesn't need to be snapshotted)
    serialize_types.registerClasses!(ActionContainer, ActionListClass,
        TimedActionClass, ActionStateInfo, ActionSpriteClass, CrateSpriteClass,
        StaticStateInfo, GOSpriteClass, SpriteActionClass, SetStateActionClass,
        GravityCenterActionClass, ProximitySensorActionClass, WalkerActionClass,
        RandomJumpActionClass, StuckTriggerActionClass, ExplosionActionClass,
        BeamActionClass, InsertBitmapActionClass, EarthquakeActionClass,
        ActionWeapon, ProjectileStateInfo, ProjectileSpriteClass,
        HomingActionClass, RayWeapon, SpawnActionClass, JetpackClass, RopeClass,
        WormStateInfo, WormSpriteClass, GravestoneSpriteClass,
        SequenceStateList, NapalmStateDisplay, NapalmState, WormStateDisplay,
        SubSequence, WormState, NapalmSpriteClass, DieActionClass,
        TeamActionClass, AoEDamageActionClass, ImpulseActionClass,
        ActionStateInfo, ProjectileStateInfo, CrateStateInfo,
        ControlRotateActionClass, DrillClass);
}
}
