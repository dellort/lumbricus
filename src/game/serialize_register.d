//this module contains calls to register all classes for serialization
//actually, not really "all", but most
module game.serialize_register;

import utils.reflection;

import game.action, game.actionsprite, game.controller, game.crate, game.game,
    game.gamepublic, game.glevel, game.spriteactions, game.sprite, game.worm,
    game.weapon.actions, game.weapon.actionweapon, game.weapon.projectile,
    game.weapon.ray, game.weapon.spawn, game.weapon.tools, game.weapon.weapon,
    game.weapon.napalm, game.sequence;
import physics.world;
import utils.configfile;

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
        ProjectileSprite, HomingAction, RayShooter, RenderLaser, Sequence,
        SequenceUpdate, SpawnAction, Jetpack, Rope, WormSprite,
        GravestoneSprite, WormSequenceUpdate, WrapFireInfo,
        GameEngineGraphics, AnimationGraphic, LineGraphic,
        TargetCross, ExplosionGfx, LandscapeGraphic, NapalmSequenceUpdate,
        NapalmSprite);
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
        SequenceStateList, NapalmStateDisplay, NapalmState, WormStateDisplay,
        SubSequence, WormState, NapalmSpriteClass);
    //hopefully will get removed again
    //serialize_types.registerClasses!(ConfigNode, ConfigValue);
}
