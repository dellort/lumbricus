module game.crate;

import game.gobject;
import physics.world;
import game.game;
import game.gfxset;
import game.controller_events;
import game.sequence;
import game.weapon.spawn;
import game.sprite;
import game.temp;
import gui.rendertext;
import utils.misc;
import utils.vector2;
import utils.time;
import utils.log;
import utils.misc;
import utils.configfile;

///Base class for stuff in crates that can be collected by worms
///most Collectable subclasses have been moved to controller.d (dependencies...)
class Collectable {
    ///The crate is being collected by a worm
    abstract void collect(CrateSprite parent, GameObject finder);

    //translation ID for contents; used to display collect messages
    //could also be used for crate-spy
    abstract char[] id();

    //what animation to show
    CrateType type() {
        return CrateType.unknown;
    }

    ///The crate explodes
    void blow(CrateSprite parent) {
        //default is do nothing
    }

    char[] toString() {
        return id();
    }

    this () {
    }
}

///Blows up the crate without giving the worm anything
///Note that you can add other collectables in the same crate
class CollectableBomb : Collectable {
    this() {
    }

    char[] id() {
        return "game_msg.crate.bomb";
    }

    void collect(CrateSprite parent, GameObject finder) {
        //harharhar :D
        parent.detonate();
    }
}

class CrateSprite : StateSprite {
    private {
        CrateSpriteClass myclass;
        PhysicZoneCircle crateZone;
        ZoneTrigger collectTrigger;
        bool mNoParachute;

        CrateType mCrateType;

        FormattedText mSpy;
    }

    //contents of the crate
    Collectable[] stuffies;

    protected this (GameEngine engine, CrateSpriteClass spriteclass) {
        super(engine, spriteclass);
        myclass = spriteclass;

        myclass.doinit(engine); //hack until crates (possibly) are moved to Lua

        crateZone = new PhysicZoneCircle(Vector2f(), myclass.collectRadius);
        collectTrigger = new ZoneTrigger(crateZone);
        collectTrigger.collision
            = engine.physicworld.collide.findCollisionID("crate_collect");
        collectTrigger.onTrigger = &oncollect;
        //doesntwork
        //collectTrigger.collision = physics.collision;
        engine.physicworld.add(collectTrigger);
    }

    void collected() {
        stuffies = null;
        kill();
    }

    bool wasCollected() {
        return stuffies.length == 0;
    }

    void blowStuffies() {
        foreach (Collectable c; stuffies) {
            c.blow(this);
        }
    }

    override protected void onKill() {
        collectTrigger.dead = true;
        mSpy = null;
        super.onKill();
    }

    private void onZeroHp() {
        detonate();
    }

    void detonate() {
        if (isUnderWater())
            return;
        engine.explosionAt(physics.pos, 50, this);
        kill();
        auto napalm = engine.gfx.findSpriteClass(myclass.napalm_class);
        spawnCluster(napalm, this, 40, 0, 0, 60);
        blowStuffies();
    }

    private void oncollect(PhysicTrigger sender, PhysicObject other) {
        if (other is physics)
            return; //lol
        auto goOther = cast(GameObject)(other.backlink);
        if (goOther) {
            //callee is expected to call .collect() on each item, and then
            //  .collected() on the crate; if the finder (goOther) can't collect
            //  the crate (e.g. because it's a weapon), just do nothing
            //(crates explode because of the weapon's impact explosion)
            OnCrateCollect.raise(this, goOther);
            if (!wasCollected)
                log("crate {} can't be collected by {}", this, goOther);
        }
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

    override protected void updateInternalActive() {
        bool bomb;
        if (internal_active) {
            foreach (coll; stuffies) {
                if (coll.type != CrateType.unknown) {
                    mCrateType = coll.type;
                    break;
                }
            }
            foreach (coll; stuffies) {
                if (cast(CollectableBomb)coll)
                    bomb = true;
            }
        }
        super.updateInternalActive();
        if (internal_active) {
            //xxx needs a better way to get the contents of the crate
            if (stuffies.length > 0 && mCrateType != CrateType.med) {
                mSpy = engine.gfx.textCreate();
                mSpy.setTextFmt(true, r"{}\t({})", bomb ? r"\c(team_red)" : "",
                    stuffies[0].id());
                assert(!!graphic);
                graphic.attachText = mSpy;
                graphic.textVisibility = &spyVisible;
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

    private bool spyVisible(Sequence s) {
        //only controller dependency left in this file
        auto m = engine.callbacks.getControlledTeamMember();
        if (!m)
            return false;
        return m.team.hasCrateSpy() && (currentState !is myclass.st_drowning);
    }
}

class CrateStateInfo : StaticStateInfo {
    SequenceState[CrateType.max+1] myAnimation;

    this(char[] this_name) {
        super(this_name);
    }

    override void loadFromConfig(ConfigNode sc, ConfigNode physNode,
        StateSpriteClass owner)
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

class CrateSpriteClass : StateSpriteClass {
    float enterParachuteSpeed;
    float collectRadius;
    char[] napalm_class;

    StaticStateInfo st_creation, st_normal, st_parachute, st_drowning;
    SequenceType[CrateType.max+1] mySequences;

    private bool didinit;

    this(GfxSet e, char[] r) {
        super(e, r);
    }
    private void doinit(GameEngine engine) {
        if (didinit)
            return;
        didinit = true;
        OnSpriteZeroHp.handler(engine.events, &onZeroHp);
    }
    override void loadFromConfig(ConfigNode config) {
        SequenceType sq(char[] name) {
            return gfx.resources.get!(SequenceType)(config[name]);
        }
        mySequences[CrateType.unknown] = sq("sequence_object");
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

        napalm_class = config["napalm"];
    }
    override CrateSprite createSprite(GameEngine engine) {
        return new CrateSprite(engine, this);
    }

    override protected CrateStateInfo createStateInfo(char[] a_name) {
        return new CrateStateInfo(a_name);
    }

    private SequenceState findSequenceState2(CrateType type, char[] name) {
        return mySequences[type].findState(name);
    }

    private void onZeroHp(Sprite sender) {
        auto spr = cast(CrateSprite)sender;
        if (spr)
            spr.onZeroHp();
    }
}

