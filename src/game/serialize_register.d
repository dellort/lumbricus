//this module contains calls to register all classes for serialization
//actually, not really "all", but most
module game.serialize_register;

import utils.reflection;

import utils.timesource;
import game.actionsprite, game.controller, game.crate, game.game,
    game.glevel, game.sprite, game.worm,
    game.weapon.actionweapon, game.weapon.projectile,
    game.weapon.ray, game.weapon.rope, game.weapon.weapon,
    game.weapon.napalm, game.weapon.melee, game.weapon.jetpack,
    game.weapon.girder, game.sequence,
    game.gamemodes.turnbased, game.gamemodes.shared,
    game.gamemodes.mdebug, game.gamemodes.realtime, game.weapon.drill,
    game.controller_plugins, game.levelgen.renderer, game.action.base,
    game.action.list, game.action.weaponactions, game.action.spriteactions,
    game.action.spawn, game.action.wcontext, game.action.common,
    game.wcontrol, game.events, game.controller_events;
import common.scene, common.animation;
import physics.world;
import utils.random;

import game.gameshell : serialize_types;

void initGameSerialization() {
    serialize_types = new Types();
    serialize_types.registerClasses!(Random, GameEngine, PhysicWorld,
        GameController, WormSprite, GameLandscape, ActionContext,
        ActionSprite, GameController, ActionListRunner, ControlRotateAction,
        Team, TeamMember, WeaponSet, CollectableBomb,
        CollectableWeapon, CollectableMedkit, CrateSprite, GameLandscape,
        LandscapeGeometry, Sprite, BeamHandler, ActionShooter,
        ProjectileSprite, RayShooter, Sequence,
        Jetpack, Rope, Drill, GirderControl, WormSprite, WormSelectHelper,
        GravestoneSprite, WrapFireInfo, RandomJumpAction,
        Animator,
        RenderLandscape, RenderRope, Scene,
        RenderCrosshair,
        NapalmSprite, ModeTurnbased, ModeDebug, TimeSource, StuckTriggerAction,
        TimeSourceFixFramerate, TimeStatus, HomingAction, SpriteAction,
        MeleeShooter, WeaponContext, DelayedObj,
        ModeRealtime, PrepareStatus, CollectableToolCrateSpy,
        CollectableToolDoubleTime, ControllerMsgs, ControllerStats,
        ControllerPersistence, CollectableToolDoubleDamage, /+LandscapeBitmap,+/
        GravityCenterAction, ProximitySensorAction, TimerAction,
        WormControl,
        SimpleAnimationDisplay, WwpNapalmDisplay, WwpJetpackDisplay,
        WwpWeaponDisplay, Events, GlobalEvents);
    registerSerializableEventHandlers!(
        OnGameStart,
        OnGameEnd,
        OnSuddenDeath,
        OnDamage,
        OnDemolish,
        OnSpriteDie,
        OnTeamMemberStartDie,
        OnTeamMemberActivate,
        OnTeamMemberDeactivate,
        OnFireWeapon,
        OnTeamSkipTurn,
        OnTeamSurrender,
        OnVictory,
        OnCrateDrop,
        OnCrateCollect,
        OnWeaponSetChanged
    )(serialize_types);
}
