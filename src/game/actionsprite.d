module game.actionsprite;

import framework.framework;
import game.gobject;
import game.game;
import game.gfxset;
import game.sequence;
import game.action.base;
import game.action.wcontext;
import game.sprite;
import game.weapon.weapon;
import physics.world;

import utils.vector2;
import utils.configfile;
import utils.misc;
import utils.mybox;
import utils.log;
import utils.factory;
import utils.time;
import utils.reflection;

class ActionSprite : GObjectSprite {
    protected Vector2f mLastImpactNormal = {0, -1};
    protected WrapFireInfo mFireInfo;
    bool doubleDamage;

    private {
        ActionContext[] mActiveActionsGlobal;
        ActionContext[] mActiveActionsState;

        bool mEnableEvents = true;

        bool mOldGlueStatus;
    }

    override ActionSpriteClass type() {
        return cast(ActionSpriteClass)mType;
    }

    override ActionStateInfo currentState() {
        return cast(ActionStateInfo)super.currentState();
    }

    override void simulate(float deltaT) {
        if (physics.lifepower <= 0)
            doEvent("onzerolife");
        bool glue = physics.isGlued;
        if (glue != mOldGlueStatus) {
            mOldGlueStatus = glue;
            if (glue)
                doEvent("onglue");
        }
        super.simulate(deltaT);
    }

    override protected void physImpact(PhysicBase other, Vector2f normal) {
        super.physImpact(other, normal);
        mLastImpactNormal = normal;
        doEvent("onimpact");
        mLastImpactNormal = Vector2f(0, -1);
    }

    override protected void physDamage(float amout, int cause) {
        super.physDamage(amout, cause);
        doEvent("ondamage");
    }

    override protected void die() {
        doEvent("ondie");
        super.die();
    }

    //when called: currentState is to
    //must not call setState (alone danger for recursion forbids it)
    override protected void stateTransition(StaticStateInfo from,
        StaticStateInfo to)
    {
        super.stateTransition(from, to);
        cleanActiveActions(mActiveActionsState);
        //no events if disabled by state info
        auto asi = cast(ActionStateInfo)to;
        assert(!!asi);
        enableEvents = !asi.disableEvents;
        if (!mEnableEvents) {
            //stop all global actions in a no-event state
            cleanActiveActions(mActiveActionsGlobal);
        }
        //run state-initialization event
        doEvent("oncreate", true);
    }

    private void cleanActiveActions(ref ActionContext[] actionsList) {
        //check an array of actions for actions still running and stop
        foreach (a; actionsList) {
            //xxx: changed from "if (a.active) a.abort();", might cause trouble
            a.abort();
        }
        actionsList = null;
    }

    override ActionStateInfo findState(char[] name) {
        return cast(ActionStateInfo)super.findState(name);
    }

    override protected void updateActive() {
        super.updateActive();
        if (active) {
            //"oncreate" is the sprite or state initialize event
            doEvent("oncreate");
        } else {
            cleanActiveActions(mActiveActionsState);
            //cleanup old global actions still running (like oncreate)
            cleanActiveActions(mActiveActionsGlobal);
        }
    }

    //fill the FireInfo struct with current data
    protected void updateFireInfo() {
        mFireInfo.info.strength = physics.velocity.length; //xxx confusing units :-)
        if (mFireInfo.info.strength > 0)
            mFireInfo.info.dir = physics.velocity.normal;
        else
            //NaN protection
            mFireInfo.info.dir = Vector2f(0, -1);
        mFireInfo.info.pos = physics.pos;
        mFireInfo.info.shootbyRadius = physics.posp.radius;
        mFireInfo.info.surfNormal = mLastImpactNormal;
    }

    WeaponContext createContext() {
        auto ctx = new WeaponContext(engine);
        ctx.ownerSprite = this;
        ctx.createdBy = this;
        updateFireInfo();
        ctx.fireInfo = mFireInfo;
        return ctx;
    }

    ///runs a sprite-specific event defined in the config file
    //xxx should be private, but is used by some actions
    void doEvent(char[] id, bool stateonly = false) {
        if (!mEnableEvents || !active)
            return;
        //logging: this is slow (esp. napalm)
        //engine.mLog("Projectile: Execute event "~id);

        //run a global or state-specific action by id, if defined
        void execAction(char[] id, bool state = false) {
            ActionClass ac;
            if (state) ac = currentState.actions.action(id);
            else ac = type.actions.action(id);
            if (ac) {
                //run action if found
                //xxx: why is a new ctx created for each event?
                auto ctx = createContext();
                ac.execute(ctx);
                if (!ctx.done) {
                    //action still reports active after execute call, so add
                    //it to the active actions list to allow later cleanup
                    if (state) mActiveActionsState ~= ctx;
                    else mActiveActionsGlobal ~= ctx;
                }
            }
        }

        if (!stateonly)
            execAction(id, false);
        execAction(id, true);

        if (id == "ondetonate") {
            //reserved event that kills the sprite
            die();
            return;
        }
        if (id in type.detonateMap || id in currentState.detonateMap) {
            //current event should cause the projectile to detonate
            //xxx reserved identifier
            doEvent("ondetonate");
        }
    }

    //shortcut to blow up the sprite
    void detonate() {
        doEvent("ondetonate");
    }

    //set to disable event processing (also disables death by ondetonate event)
    void enableEvents(bool enable) {
        mEnableEvents = enable;
    }
    bool enableEvents() {
        return mEnableEvents;
    }

    protected this(GameEngine engine, GOSpriteClass type) {
        super(engine, type);
        mFireInfo = new WrapFireInfo();
    }

    this (ReflectCtor c) {
        super(c);
        c.types().registerMethod(this, &physDamage, "physDamage");
        c.types().registerMethod(this, &physImpact, "physImpact");
    }
}

class ActionStateInfo : StaticStateInfo {
    ActionContainer actions;

    bool[char[]] detonateMap;

    bool disableEvents = false;

    private {
        //for forward references
        char[] actionsTmp;
    }

    //xxx class
    this (ReflectCtor c) {
        super(c);
    }

    this(char[] owner_name, char[] this_name) {
        super(this_name);
        actions = new ActionContainer(owner_name ~ "::" ~ this_name);
    }

    override void loadFromConfig(ConfigNode sc, ConfigNode physNode,
        GOSpriteClass owner)
    {
        super.loadFromConfig(sc, physNode, owner);

        auto acnode = sc.findNode("actions");
        if (acnode) {
            //"actions" is a node containing action defs
            //actions = new ActionContainer(mCntName);
            actions.loadFromConfig(owner.gfx, acnode);
        } else {
            //"actions" is a reference to another state
            actionsTmp = sc["actions"];
        }

        disableEvents = sc.getBoolValue("disable_events", disableEvents);

        auto detonateNode = sc.getSubNode("detonate");
        foreach (char[] name, char[] value; detonateNode) {
            //xxx sry
            if (value == "true" && name != "ondetonate") {
                detonateMap[name] = true;
            }
        }
    }

    override void fixup(GOSpriteClass owner) {
        super.fixup(owner);
        if (actionsTmp.length > 0) {
            auto st = cast(ActionSpriteClass)owner.findState(actionsTmp, true);
            if (st)
                actions = st.actions;
            actionsTmp = null;
        }
    }
}

class ActionSpriteClass : GOSpriteClass {
    ActionContainer actions;
    bool canRefire = false;

    bool[char[]] detonateMap;

    this (GfxSet gfx, char[] regname) {
        super(gfx, regname);

        actions = new ActionContainer(name);
    }

    //xxx class
    this (ReflectCtor c) {
        super(c);
    }

    ActionSprite createSprite(GameEngine engine) {
        return new ActionSprite(engine, this);
    }

    override void loadFromConfig(ConfigNode config) {
        super.loadFromConfig(config);

        asLoadFromConfig(config);
    }

    protected void asLoadFromConfig(ConfigNode config) {
        actions.loadFromConfig(gfx, config.getSubNode("actions"));

        canRefire = config.getBoolValue("can_refire", canRefire);

        auto detonateNode = config.getSubNode("detonate");
        foreach (char[] name, char[] value; detonateNode) {
            //xxx sry
            if (value == "true" && name != "ondetonate") {
                detonateMap[name] = true;
            }
        }
    }

    override protected ActionStateInfo createStateInfo(char[] a_name) {
        return new ActionStateInfo(name, a_name);
    }
}
