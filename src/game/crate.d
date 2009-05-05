module game.crate;

import game.gobject;
import game.animation;
import physics.world;
import game.game;
import game.gamepublic;
import game.controller;
import game.sequence;
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
import tango.math.Math;
import tango.util.Convert;
import str = stdx.string;

///Base class for stuff in crates that can be collected by worms
class Collectable {
    ///The crate is being collected by a worm
    abstract void collect(CrateSprite parent, ServerTeamMember member);

    //translation ID for contents; used to display collect messages
    //could also be used for crate-spy
    abstract char[] id();

    //create a controller message when this item was collected
    abstract void collectMessage(GameController logic, ServerTeamMember member);

    ///The crate explodes
    void blow(CrateSprite parent) {
        //default is do nothing
    }

    char[] toString() {
        return id();
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

    char[] id() {
        return "weapons." ~ weapon.name;
    }

    void collectMessage(GameController logic, ServerTeamMember member) {
        logic.messageAdd("collect_item", [member.name(), "_." ~ id(),
            to!(char[])(quantity)]);
    }

    override void blow(CrateSprite parent) {
        //think about the crate-sheep
        //xxx maybe make this more generic
        auto aw = cast(ActionWeapon)weapon;
        if (aw && aw.onBlowup) {
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

    char[] id() {
        return "game_msg.crate.medkit";
    }

    void collectMessage(GameController logic, ServerTeamMember member) {
        logic.messageAdd("collect_medkit", [member.name(),
            to!(char[])(amount)]);
    }

    void collect(CrateSprite parent, ServerTeamMember member) {
        member.addHealth(amount);
    }
}

abstract class CollectableTool : Collectable {
    this() {
    }

    this (ReflectCtor c) {
    }

    void collectMessage(GameController logic, ServerTeamMember member) {
        logic.messageAdd("collect_tool", [member.name(), "_." ~ id()]);
    }

    void collect(CrateSprite parent, ServerTeamMember member) {
        //roundabout way, but I hope it makes a bit sense with double time tool?
        if (!parent.engine.controller.collectTool(member, this)) {
            //this is executed if nobody knew what to do with the tool
        }
    }
}

class CollectableToolCrateSpy : CollectableTool {
    this() {
    }
    this (ReflectCtor c) {
    }

    char[] id() {
        return "game_msg.crate.cratespy";
    }
}

class CollectableToolDoubleTime : CollectableTool {
    this() {
    }
    this (ReflectCtor c) {
    }

    char[] id() {
        return "game_msg.crate.doubletime";
    }
}

class CollectableToolDoubleDamage : CollectableTool {
    this() {
    }
    this (ReflectCtor c) {
    }

    char[] id() {
        return "game_msg.crate.doubledamage";
    }
}

///Blows up the crate without giving the worm anything
///Note that you can add other collectables in the same crate
class CollectableBomb : Collectable {
    this (ReflectCtor c) {
    }
    this() {
    }

    char[] id() {
        return "game_msg.crate.bomb";
    }

    void collectMessage(GameController logic, ServerTeamMember member) {
        logic.messageAdd("collect_bomb", [member.name()]);
    }

    void collect(CrateSprite parent, ServerTeamMember member) {
        //harharhar :D
        parent.detonate();
    }
}

private enum CrateType {
    weapon,
    med,
    tool,
}

class CrateSprite : ActionSprite {
    private {
        CrateSpriteClass myclass;
        PhysicZoneCircle crateZone;
        ZoneTrigger collectTrigger;
        bool mNoParachute;

        CrateType mCrateType;

        TextGraphic mSpy;
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
        if (mSpy) {
            mSpy.remove();
            mSpy = null;
        }
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
        auto member = engine.controller.memberFromGameObject(finder, true);
        if (!member) {
            log("crate {} can't be collected by {}", this, finder);
            return;
        }
        //only collect crates when it's your turn
        if (!member.active)
            return;
        engine.controller.events.onCrate(member, stuffies);
        //transfer stuffies
        foreach (Collectable c; stuffies) {
            c.collectMessage(engine.controller, member);
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

    protected void setCurrentAnimation() {
        if (!graphic)
            return;

        graphic.setState(currentState.myAnimation[mCrateType]);
    }

    override protected void updateActive() {
        if (active) {
            foreach (coll; stuffies) {
                if (cast(CollectableMedkit)coll) {
                    mCrateType = CrateType.med;
                    break;
                }
                if (cast(CollectableTool)coll) {
                    mCrateType = CrateType.tool;
                    break;
                }
            }
        }
        super.updateActive();
    }

    override CrateStateInfo currentState() {
        return cast(CrateStateInfo)super.currentState();
    }

    override void doEvent(char[] id, bool stateonly = false) {
        super.doEvent(id, stateonly);
        if (id == "ondetonate") {
            blowStuffies();
        }
    }

    override void simulate(float deltaT) {
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

        bool show_spy = engine.controller.crateSpyActive()
            && currentState is myclass.st_normal;
        if (show_spy != !!mSpy) {
            if (mSpy) {
                mSpy.remove();
                mSpy = null;
            } else {
                mSpy = new TextGraphic();
                mSpy.attach = Vector2f(0.5f, 1.0f);
                //xxx needs a better way to get the contents of the crate
                if (stuffies.length > 0) {
                    mSpy.msg.id = stuffies[0].id();
                }
                engine.graphics.add(mSpy);
            }
        }

        //comedy
        if (mSpy && graphic && graphic.graphic) {
            auto g = cast(AnimationGraphic)graphic.graphic;
            if (g && g.animation) {
                mSpy.pos = toVector2i(physics.pos)
                    - g.animation.bounds.size.Y / 2;
            }
        }

        super.simulate(deltaT);
    }
}

class CrateStateInfo : ActionStateInfo {
    SequenceState[CrateType.max+1] myAnimation;

    //xxx class
    this (ReflectCtor c) {
        super(c);
    }
    this () {
    }

    override void loadFromConfig(ConfigNode sc, ConfigNode physNode,
        GOSpriteClass owner)
    {
        super.loadFromConfig(sc, physNode, owner);
        if (sc["animation"].length > 0) {
            auto csc = cast(CrateSpriteClass)owner;
            for (CrateType ct = CrateType.min; ct <= CrateType.max; ct++) {
                myAnimation[ct] = csc.findSequenceState2(ct,
                    sc["animation"]);
            }
        }
    }
}

//the factories work over the sprite classes, so we need one
class CrateSpriteClass : ActionSpriteClass {
    float enterParachuteSpeed;
    float collectRadius;

    StaticStateInfo st_creation, st_normal, st_parachute, st_drowning;
    char[][CrateType.max+1] mySequencePrefix;

    //xxx class
    this (ReflectCtor c) {
        super(c);
    }

    this(GameEngine e, char[] r) {
        super(e, r);
    }
    override void loadFromConfig(ConfigNode config) {
        mySequencePrefix[CrateType.weapon] = config["sequence_object"];
        mySequencePrefix[CrateType.med] = config["sequence_object_med"];
        mySequencePrefix[CrateType.tool] = config["sequence_object_tool"];

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

    override protected CrateStateInfo createStateInfo() {
        return new CrateStateInfo();
    }

    private SequenceState findSequenceState2(CrateType type, char[] pseudo_name)
    {
        return engine.sequenceStates.findState(mySequencePrefix[type] ~ '_' ~
            pseudo_name, false);
    }

    static this() {
        SpriteClassFactory.register!(typeof(this))("crate_mc");
    }
}

