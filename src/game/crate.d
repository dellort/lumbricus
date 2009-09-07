module game.crate;

import game.gobject;
import game.animation;
import physics.world;
import game.game;
import game.gfxset;
import game.gamepublic;
import game.controller;
import game.sequence;
import game.weapon.weapon;
import game.sprite;
import game.actionsprite;
import game.action.base;
import game.weapon.actionweapon;
import game.temp;
import utils.misc;
import utils.vector2;
import utils.time;
import utils.log;
import utils.misc;
import utils.configfile;
import utils.reflection;
import utils.factory;
import tango.math.Math;
import tango.util.Convert;

///Base class for stuff in crates that can be collected by worms
class Collectable {
    ///The crate is being collected by a worm
    abstract void collect(CrateSprite parent, TeamMember member);

    //translation ID for contents; used to display collect messages
    //could also be used for crate-spy
    abstract char[] id();

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

    void collect(CrateSprite parent, TeamMember member) {
        member.team.addWeapon(weapon, quantity);
    }

    char[] id() {
        return "weapons." ~ weapon.name;
    }

    override void blow(CrateSprite parent) {
        //think about the crate-sheep
        //xxx maybe make this more generic
        auto aw = cast(ActionWeapon)weapon;
        if (aw && aw.onBlowup) {
            //run in context of parent crate
            auto ctx = parent.createContext;
            aw.onBlowup.execute(ctx);
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

    void collect(CrateSprite parent, TeamMember member) {
        member.addHealth(amount);
    }
}

abstract class CollectableTool : Collectable {
    this() {
    }

    this (ReflectCtor c) {
    }

    void collect(CrateSprite parent, TeamMember member) {
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

    static this() {
        CrateToolFactory.register!(typeof(this))("cratespy");
    }
}

//for now only for turnbased gamemode, but maybe others will follow
class CollectableToolDoubleTime : CollectableTool {
    this() {
    }
    this (ReflectCtor c) {
    }

    char[] id() {
        return "game_msg.crate.doubletime";
    }

    static this() {
        CrateToolFactory.register!(typeof(this))("doubletime");
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

    static this() {
        CrateToolFactory.register!(typeof(this))("doubledamage");
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

    void collect(CrateSprite parent, TeamMember member) {
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

        CrateType mCrateType;

        RenderText mSpy;
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
        t.registerMethod(this, &spyVisible, "spyVisible");
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
        mSpy = null;
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
        engine.controller.events.onCrateCollect(member, stuffies);
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

    override protected void setCurrentAnimation() {
        if (!graphic)
            return;

        graphic.setState(currentState.myAnimation[mCrateType]);
    }

    override protected void updateActive() {
        bool bomb;
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
            foreach (coll; stuffies) {
                if (cast(CollectableBomb)coll)
                    bomb = true;
            }
        }
        super.updateActive();
        if (active) {
            //xxx needs a better way to get the contents of the crate
            if (stuffies.length > 0 && mCrateType != CrateType.med) {
                mSpy = new RenderText(engine);
                char[] msg = "\\t(" ~ stuffies[0].id() ~ ")";
                if (bomb)
                    msg = "\\c(team_red)" ~ msg;
                mSpy.markupText = msg;
                mSpy.visibility = &spyVisible;
                assert(!!graphic);
                graphic.attachText = mSpy;
            }
        } else {
            mSpy = null;
        }
    }

    //only valid after crate has been filled and activated
    CrateType crateType() {
        return mCrateType;
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

        super.simulate(deltaT);
    }

    //for TextGraphic.visibleDg : returns true if spy is shown (m is the
    //  client's controlled member)
    private bool spyVisible(TeamMember m) {
        if (m)
            return m.team.hasCrateSpy()
                && (currentState !is myclass.st_drowning);
        return false;
    }
}

class CrateStateInfo : ActionStateInfo {
    SequenceState[CrateType.max+1] myAnimation;

    //xxx class
    this (ReflectCtor c) {
        super(c);
    }
    this(char[] owner_name, char[] this_name) {
        super(owner_name, this_name);
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
    SequenceType[CrateType.max+1] mySequences;

    //xxx class
    this (ReflectCtor c) {
        super(c);
    }

    this(GfxSet e, char[] r) {
        super(e, r);
    }
    override void loadFromConfig(ConfigNode config) {
        SequenceType sq(char[] name) {
            return gfx.resources.get!(SequenceType)(config[name]);
        }
        mySequences[CrateType.weapon] = sq("sequence_object");
        mySequences[CrateType.med] = sq("sequence_object_med");
        mySequences[CrateType.tool] = sq("sequence_object_tool");

        super.loadFromConfig(config);

        enterParachuteSpeed = config.getFloatValue("enter_parachute_speed");
        collectRadius = config.getFloatValue("collect_radius");

        //done, read out the stupid states :/
        st_creation = findState("creation");
        st_normal = findState("normal");
        st_parachute = findState("parachute");
        st_drowning = findState("drowning");
    }
    override CrateSprite createSprite(GameEngine engine) {
        return new CrateSprite(engine, this);
    }

    override protected CrateStateInfo createStateInfo(char[] a_name) {
        return new CrateStateInfo(name, a_name);
    }

    private SequenceState findSequenceState2(CrateType type, char[] name) {
        return mySequences[type].findState(name);
    }

    static this() {
        SpriteClassFactory.register!(typeof(this))("crate_mc");
    }
}

StaticFactory!("CrateTools", CollectableTool) CrateToolFactory;
