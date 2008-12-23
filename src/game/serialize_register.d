//this module contains calls to register all classes for serialization
//actually, not really "all", but most
module game.serialize_register;

import utils.reflection;

import game.action, game.actionsprite, game.controller, game.crate, game.game,
    game.glevel, game.spriteactions, game.sprite, game.worm,
    game.weapon.actions, game.weapon.actionweapon, game.weapon.projectile,
    game.weapon.ray, game.weapon.spawn, game.weapon.tools, game.weapon.weapon,
    game.sequence;
import physics.world;

import game.gametask : serialize_types;

void initGameSerialization() {
    serialize_types = new Types();
    serialize_types.registerClasses!(GameEngine, PhysicWorld,
        GameController, WormSprite, GameLandscape, ActionContext, ActionList,
        TimedAction, ActionSprite, GameController, ServerMemberControl,
        ServerTeam, ServerTeamMember, WeaponSet, WeaponItem, CollectableBomb,
        CollectableWeapon, CollectableMedkit, CrateSprite, GameLandscape,
        LandscapeGeometry, SpriteAction, SetStateAction, GravityCenterAction,
        ProximitySensorAction, WalkerAction, RandomJumpAction,
        StuckTriggerAction, GObjectSprite, WeaponAction, ExplosionAction,
        BeamAction, InsertBitmapAction, EarthquakeAction, ActionShooter,
        ProjectileSprite, HomingAction, RayShooter, RenderLaser, SpawnAction,
        Jetpack, Rope, WormSprite, GravestoneSprite);
    //stuff that (maybe) should not be serialized
    //all ctors are marked with "xxx class"
    serialize_types.registerClasses!(ActionContainer, ActionListClass,
        TimedActionClass, ActionStateInfo, ActionSpriteClass, CrateSpriteClass,
        StaticStateInfo, GOSpriteClass, SpriteActionClass, SetStateActionClass,
        GravityCenterActionClass, ProximitySensorActionClass, WalkerActionClass,
        RandomJumpActionClass, StuckTriggerActionClass, ExplosionActionClass,
        BeamActionClass, InsertBitmapActionClass, EarthquakeActionClass,
        ActionWeapon, ProjectileStateInfo, ProjectileSpriteClass,
        HomingActionClass, RayWeapon, SpawnActionClass, ToolClass,
        WormStateInfo, WormSpriteClass, GravestoneSpriteClass,
        SequenceStateList, SequenceState, SequenceUpdate, WormSequenceUpdate,
        Sequence, NapalmStateDisplay, NapalmState, WormStateDisplay,
        SubSequence, WormState);
}

