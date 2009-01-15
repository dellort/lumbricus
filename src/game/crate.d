module game.crate;

import game.gobject;
import game.animation;
import physics.world;
import game.game;
import game.controller;
import game.weapon.weapon;
import game.sprite;
import game.actionsprite;
import game.action;
import game.weapon.actionweapon;
import utils.misc;
import utils.vector2;
import utils.time;
import utils.log;
import utils.misc;
import utils.configfile;
import utils.reflection;
import std.math;
import str = std.string;

///Base class for stuff in crates that can be collected by worms
class Collectable {
    ///The crate is being collected by a worm
    abstract void collect(CrateSprite parent, ServerTeamMember member);

    ///The crate explodes
    void blow(CrateSprite parent) {
        //default is do nothing
    }

    this () {
    }
    this (ReflectCtor c) {
    }
}

///Adds a weapon to your inventory
class CollectableWeapon : Collectable {
    WeaponClass weapon;
    int quantity;

    this(WeaponClass w, int quantity = 1) {
        weapon = w;
        this.quantity = quantity;
    }

    this (ReflectCtor c) {
    }

    void collect(CrateSprite parent, ServerTeamMember member) {
        member.mTeam.addWeapon(weapon, quantity);
    }

    override void blow(CrateSprite parent) {
        //think about the crate-sheep
        //xxx maybe make this more generic
        auto aw = cast(ActionWeapon)weapon;
        if (aw.onBlowup) {
            auto ac = aw.onBlowup.createInstance(parent.engine);
            //run in context of parent crate
            auto ctx = new ActionContext(&parent.readParam);
            ac.execute(ctx);
        }
    }
}

///Gives the collecting worm some health
class CollectableMedkit : Collectable {
    int amount;

    this(int amount = 50) {
        this.amount = amount;
    }

    this (ReflectCtor c) {
    }

    void collect(CrateSprite parent, ServerTeamMember member) {
        //xxx not sure if the controller can handle it
        member.worm.physics.lifepower += amount;
    }
}

///Blows up the crate without giving the worm anything
///Note that you can add other collectables in the same crate
class CollectableBomb : Collectable {
    this (ReflectCtor c) {
    }
    this() {
    }

    void collect(CrateSprite parent, ServerTeamMember member) {
        //harharhar :D
        parent.detonate();
    }
}

class CrateSprite : ActionSprite {
    private {
        CrateSpriteClass myclass;
        PhysicZoneCircle crateZone;
        ZoneTrigger collectTrigger;
        bool mNoParachute;
    }

    //contents of the crate
    Collectable[] stuffies;

    protected this (GameEngine engine, CrateSpriteClass spriteclass) {
        super(engine, spriteclass);
        myclass = spriteclass;

        crateZone = new PhysicZoneCircle(Vector2f(), myclass.collectRadius);
        collectTrigger = new ZoneTrigger(crateZone);
        collectTrigger.collision
            = engine.physicworld.collide.findCollisionID("crate_collect");
        collectTrigger.onTrigger = &oncollect;
        //doesntwork
        //collectTrigger.collision = physics.collision;
        engine.physicworld.add(collectTrigger);
    }

    this (ReflectCtor c) {
        super(c);
        Types t = c.types();
        t.registerMethod(this, &oncollect, "oncollect");
    }

    private void collected() {
        stuffies = null;
        die();
    }

    void blowStuffies() {
        foreach (Collectable c; stuffies) {
            c.blow(this);
        }
    }

    override protected void die() {
        collectTrigger.dead = true;
        super.die();
    }

    private void oncollect(PhysicTrigger sender, PhysicObject other) {
        if (other is physics)
            return; //lol
        auto goOther = cast(GameObject)(other.backlink);
        if (goOther)
            collectCrate(goOther);
    }

    void collectCrate(GameObject finder) {
        //for some weapons like animal-weapons, transitive should be true
        //and normally a non-collecting weapon should just explode here??
        auto member = engine.controller.memberFromGameObject(finder, false);
        if (!member) {
            engine.mLog("crate %s can't be collected by %s", this, finder);
            return;
        }
        //only collect crates when it's your turn
        if (!member.active)
            return;
        engine.mLog("%s collects crate %s", member, this);
        //transfer stuffies
        foreach (Collectable c; stuffies) {
            c.collect(this, member);
        }
        //and destroy crate
        collected();
    }

    void unParachute() {
        if (currentState == myclass.st_parachute)
            setState(myclass.st_normal);
        mNoParachute = true;
    }

    override void doEvent(char[] id, bool stateonly = false) {
        super.doEvent(id, stateonly);
        if (id == "ondetonate") {
            blowStuffies();
        }
    }

    override protected void physUpdate() {
        crateZone.pos = physics.pos;
        if (physics.isGlued) {
            setState(myclass.st_normal);
            mNoParachute = false;
        } else {
            //falling too fast -> parachute
            //xxx: if it flies too fast or in a too wrong direction, explode
            if (currentState !is myclass.st_drowning
                && physics.velocity.length > myclass.enterParachuteSpeed
                && !mNoParachute)
            {
                setState(myclass.st_parachute);
            }
        }
        super.physUpdate();
    }
}

//the factories work over the sprite classes, so we need one
class CrateSpriteClass : ActionSpriteClass {
    float enterParachuteSpeed;
    float collectRadius;

    StaticStateInfo st_creation, st_normal, st_parachute, st_drowning;

    //xxx class
    this (ReflectCtor c) {
        super(c);
    }

    this(GameEngine e, char[] r) {
        super(e, r);
    }
    override void loadFromConfig(ConfigNode config) {
        super.loadFromConfig(config);

        enterParachuteSpeed = config.getFloatValue("enter_parachute_speed");
        collectRadius = config.getFloatValue("collect_radius");

        //done, read out the stupid states :/
        st_creation = findState("creation");
        st_normal = findState("normal");
        st_parachute = findState("parachute");
        st_drowning = findState("drowning");
    }
    override CrateSprite createSprite() {
        return new CrateSprite(engine, this);
    }

    static this() {
        SpriteClassFactory.register!(typeof(this))("crate_mc");
    }
}

