//this module contains calls to register all classes for serialization
//actually, not really "all", but most
module game.serialize_register;

import utils.reflection;

import framework.timesource;
import game.action, game.actionsprite, game.controller, game.crate, game.game,
    game.gamepublic, game.glevel, game.spriteactions, game.sprite, game.worm,
    game.weapon.actions, game.weapon.actionweapon, game.weapon.projectile,
    game.weapon.ray, game.weapon.spawn, game.weapon.tools, game.weapon.weapon,
    game.weapon.napalm, game.weapon.melee, game.sequence,
    game.gamemodes.roundbased, game.gamemodes.roundbased_shared,
    game.gamemodes.mdebug, game.gamemodes.realtime;
import physics.world;
import utils.random;

import game.gameshell : serialize_types;

void initGameSerialization() {
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
        SequenceUpdate, SpawnAction, Jetpack, Rope, WormSprite,
        GravestoneSprite, WormSequenceUpdate, WrapFireInfo,
        GameEngineGraphics, AnimationGraphic, LineGraphic,
        Crosshair, LandscapeGraphic, NapalmSequenceUpdate,
        NapalmSprite, WeaponHandle, ModeRoundbased, ModeDebug, TimeSource,
        TimeSourceFixFramerate, EventAggregator, DieAction, RoundbasedStatus,
        TeamAction, AoEDamageAction, ImpulseAction, MeleeWeapon, MeleeShooter,
        ModeRealtime);
    //stuff that (maybe) should not be serialized
    //all ctors are marked with "xxx class"
    serialize_types.registerClasses!(ActionContainer, ActionListClass,
        TimedActionClass, ActionStateInfo, ActionSpriteClass, CrateSpriteClass,
        StaticStateInfo, GOSpriteClass, SpriteActionClass, SetStateActionClass,
        GravityCenterActionClass, ProximitySensorActionClass, WalkerActionClass,
        RandomJumpActionClass, StuckTriggerActionClass, ExplosionActionClass,
        BeamActionClass, InsertBitmapActionClass, EarthquakeActionClass,
        ActionWeapon, ProjectileStateInfo, ProjectileSpriteClass,
        HomingActionClass, RayWeapon, SpawnActionClass, ToolClass, RopeClass,
        WormStateInfo, WormSpriteClass, GravestoneSpriteClass,
        SequenceStateList, NapalmStateDisplay, NapalmState, WormStateDisplay,
        SubSequence, WormState, NapalmSpriteClass, DieActionClass,
        TeamActionClass, AoEDamageActionClass, ImpulseActionClass,
        ActionStateInfo, ProjectileStateInfo, CrateStateInfo,
        ControlRotateActionClass);
}
