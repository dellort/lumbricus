module game.plugin.crate;

import framework.lua;
import game.controller;
import game.core;
import game.events;
import game.game;
import game.input;
import game.plugins;
import game.sequence;
import game.sprite;
import game.teamtheme;
import game.hud.teaminfo;
import game.weapon.weapon;
import game.weapon.weaponset;
import gui.rendertext;
import physics.all;
import utils.vector2;
import utils.time;
import utils.misc;
import utils.array;
import utils.configfile;
import utils.log;
import str = utils.string;
import tango.util.Convert;

//hack for message display
alias DeclareEvent!("team_member_collect_crate", TeamMember, CrateSprite)
    OnTeamMemberCollectCrate;
//when a worm collects a tool from a crate
alias DeclareEvent!("collect_tool", TeamMember, CollectableTool) OnCollectTool;
//sender is the newly dropped crate
alias DeclareEvent!("crate_drop", CrateSprite) OnCrateDrop;
//sender is the crate, first parameter is the collecting team member
alias DeclareEvent!("crate_collect", CrateSprite, GameObject) OnCrateCollect;
//make crates fall faster by pressing "space" (also known as unParachute)
alias DeclareGlobalEvent!("game_crate_skip") OnGameCrateSkip;

//keep in sync with Lua
enum CrateType {
    unknown,
    weapon,
    med,
    tool,
}

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

class TeamCollectable : Collectable {
    override void collect(CrateSprite parent, GameObject finder) {
    }

    abstract void teamcollect(CrateSprite parent, TeamMember member);
}

///Adds a weapon to your inventory
class CollectableWeapon : TeamCollectable {
    WeaponClass weapon;
    int quantity;

    this(WeaponClass w, int quantity = 1) {
        weapon = w;
        this.quantity = quantity;
    }

    void teamcollect(CrateSprite parent, TeamMember member) {
        member.team.addWeapon(weapon, quantity);
    }

    CrateType type() {
        return CrateType.weapon;
    }

    char[] id() {
        return "weapons." ~ weapon.name;
    }

    override void blow(CrateSprite parent) {
        //think about the crate-sheep
        //ok, made more generic
        OnWeaponCrateBlowup.raise(weapon, parent);
    }
}

///Gives the collecting worm some health
class CollectableMedkit : TeamCollectable {
    int amount;

    this(int amount = 50) {
        this.amount = amount;
    }

    CrateType type() {
        return CrateType.med;
    }

    char[] id() {
        return "game_msg.crate.medkit";
    }

    void teamcollect(CrateSprite parent, TeamMember member) {
        member.addHealth(amount);
    }
}

class CollectableTool : TeamCollectable {
    private {
        char[] mToolID;
    }

    this(char[] tool_id) {
        mToolID = tool_id;
    }

    override CrateType type() {
        return CrateType.tool;
    }

    override char[] id() {
        return "game_msg.crate." ~ mToolID;
    }

    char[] toolID() {
        return mToolID;
    }

    void teamcollect(CrateSprite parent, TeamMember member) {
        //roundabout way, but I hope it makes a bit sense with double time tool?
        OnCollectTool.raise(member, this);
    }
}

class CrateSprite : Sprite {
    private {
        CrateSpriteClass myclass;
        PhysicZoneCircle crateZone;
        ZoneTrigger collectTrigger;
        bool mNoParachute;

        CrateType mCrateType;

        FormattedText mSpy;
        GameInfo mGameInfo;
    }

    //contents of the crate
    Collectable[] stuffies;

    protected this (CrateSpriteClass spriteclass) {
        super(spriteclass);
        myclass = spriteclass;

        crateZone = new PhysicZoneCircle(physics, myclass.collectRadius);
        collectTrigger = new ZoneTrigger(crateZone);
        collectTrigger.collision
            = engine.physicWorld.collide.findCollisionID("crate_collect");
        collectTrigger.onTrigger = &oncollect;
        //doesntwork
        //collectTrigger.collision = physics.collision;
        engine.physicWorld.add(collectTrigger);
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

    void detonate() {
        if (physics) {
            physics.lifepower = 0;
            //call zero-hp event handler
            simulate();
        }
    }

    override protected void onKill() {
        collectTrigger.dead = true;
        mSpy = null;
        super.onKill();
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
            //if (!wasCollected)
            //    log("crate {} can't be collected by {}", this, goOther);
        }
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
                mSpy = WormLabels.textCreate();
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

    private bool spyVisible(Sequence s) {
        //only controller dependency left in this file
        if (!mGameInfo) {
            mGameInfo = engine.singleton!(GameInfo)();
        }
        auto m = mGameInfo ? mGameInfo.control.getControlledMember() : null;
        if (!m)
            return false;
        return m.team.hasCrateSpy() && !isUnderWater();
    }
}

class CrateSpriteClass : SpriteClass {
    float collectRadius = 1000;

    this(GameCore e, char[] r) {
        super(e, r);
    }

    override CrateSprite createSprite() {
        return new CrateSprite(this);
    }
}


class CratePlugin : GameObject2 {
    private {
        //Medkit, medkit+tool, medkit+tool+unrigged weapon
        //  (rest is rigged weapon)
        float[3] mCrateProbs = [0.20f, 0.40f, 0.95f];
        //list of tool crates that can drop
        char[][] mActiveCrateTools;

        GameController mController;
        WeaponSet mCrateSet;
        InputGroup mInput;
    }

    this(GameCore c, ConfigNode conf) {
        super(c, "crate_plugin");
        c.scripting.register(gCrateRegistry);
        //plugins are singleton; we can abuse this fact to allow using this
        //  plugin from other plugins
        c.addSingleton(this);
        c.scripting.addSingleton(this);
        mController = engine.singleton!(GameController)();

        OnGameStart.handler(engine.events, &doGameStart);
        OnCollectTool.handler(engine.events, &doCollectTool);
        OnCrateCollect.handler(engine.events, &doCollectCrate);

        auto probs = conf.getValue!(float[])("probs");
        //the values don't have to add up to 1
        float sum = 0;
        foreach (float p; probs) {
            sum += p;
        }
        //check if it was a valid list
        if (sum > 0) {
            //accumulate probabilities for easy random selection
            float curAcc = 0;
            for (int i = 0; i < mCrateProbs.length && i < probs.length; i++) {
                curAcc += probs[i] / sum;
                mCrateProbs[i] = curAcc;
            }
        }
        log.trace("Crate probabilites: {}", mCrateProbs);

        //those work for all gamemodes
        addCrateTool("cratespy");
        addCrateTool("doubledamage");

        mInput = new InputGroup();
        //global
        mInput.add("crate_test", &inpDropCrate);
        //adding this after team input important for weapon_fire to work as
        //  expected (only execute if no team active)
        //should be ok because plugins are loaded after GameController
        mInput.add("weapon_fire", &inpInstantDropCrate);
        engine.input.addSub(mInput);
    }

    private Log log() {
        return engine.log;
    }

    void addCrateTool(char[] id) {
        assert(arraySearch(mActiveCrateTools, id) < 0);
        mActiveCrateTools ~= id;
    }

    Collectable[] fillCrate() {
        Collectable[] ret;
        float r = engine.rnd.nextDouble2();
        if (r < mCrateProbs[0]) {
            //medkit
            ret ~= new CollectableMedkit(50);
        } else if (r < mCrateProbs[1]) {
            //tool
            ret ~= new CollectableTool(mActiveCrateTools[engine.rnd.next(cast(uint)$)]);
        } else {
            //weapon
            auto content = mCrateSet ? mCrateSet.chooseRandomForCrate() : null;
            if (content) {
                ret ~= new CollectableWeapon(content, content.crateAmount);
                if (r > mCrateProbs[2]) {
                    //add a bomb to that :D
                    ret ~= new CollectableBomb();
                }
            } else {
                log.warn("failed to create crate contents");
            }
        }
        return ret;
    }

    //  silent = true to prevent generating an event (for debug drop, to
    //           prevent message spam)
    bool dropCrate(bool silent = false, Collectable[] contents = null) {
        Vector2f from, to;
        if (!engine.placeObjectRandom(10, 25, from, to)) {
            log.warn("couldn't find a safe drop-position for crate");
            return false;
        }

        Sprite s = engine.resources.get!(SpriteClass)("x_crate").createSprite();
        CrateSprite crate = cast(CrateSprite)s;
        assert(!!crate);
        //put stuffies into it
        if (!contents.length) {
            crate.stuffies = fillCrate();
        } else {
            crate.stuffies = contents;
        }
        //actually start it
        crate.activate(from);
        if (!silent) {
            //xxx move into CrateSprite.activate()
            OnCrateDrop.raise(crate);
        }
        log.minor("drop crate {} -> {}", from, to);
        return true;
    }

    private bool inpDropCrate() {
        dropCrate(true);
        return true;
    }

    private bool inpInstantDropCrate() {
        instantDropCrate();
        return true;
    }

    void instantDropCrate() {
        log.trace("instant drop crate");
        OnGameCrateSkip.raise(engine.events);
    }

    private void doGameStart() {
        //crate weapon set is named "crate_set" (will fall back to "default")
        mCrateSet = mController.initWeaponSet("crate_set", true, true);
    }

    private void doCollectCrate(CrateSprite crate, GameObject finder) {
        if (crate.wasCollected())
            return;
        //for some weapons like animal-weapons, transitive should be true
        //and normally a non-collecting weapon should just explode here??
        auto member = mController.memberFromGameObject(finder, true);
        if (!member)
            return;
        //only collect crates when it's your turn
        if (!member.active)
            return;
        OnTeamMemberCollectCrate.raise(member, crate);
        //transfer stuffies
        foreach (Collectable c; crate.stuffies) {
            c.collect(crate, finder);
            if (auto tc = cast(TeamCollectable)c)
                tc.teamcollect(crate, member);
        }
        //and destroy crate
        crate.collected();
    }

    //xxx wouldn't need this anymore, but doubletime still makes it a bit messy
    private void doCollectTool(TeamMember collector, CollectableTool tool) {
        char[] id = tool.toolID();
        if (id == "cratespy") {
            collector.team.addCrateSpy();
        }
        if (id == "doubledamage") {
            collector.team.addDoubleDamage();
        }
    }

    override bool activity() {
        return false;
    }

    static this() {
        GamePluginFactory.register!(typeof(this))("crate");
    }
}

//xxx is it ok to have Lua binding stuff here? Not sure about that, but we don't
//    want to register functions of a non-loaded plugin
//^ don't know; the registered functions would be simply useless, nothing else
private LuaRegistry gCrateRegistry;

static this() {
    gCrateRegistry = new typeof(gCrateRegistry)();

    gCrateRegistry.methods!(CratePlugin, "dropCrate", "addCrateTool",
        "fillCrate");

    gCrateRegistry.ctor!(CollectableTool, char[])();
    gCrateRegistry.ctor!(CollectableWeapon, WeaponClass, int)();
    gCrateRegistry.ctor!(CollectableBomb)();
    gCrateRegistry.ctor!(CollectableMedkit)();

    gCrateRegistry.ctor!(CrateSpriteClass, GameCore, char[])();
    gCrateRegistry.properties!(CrateSpriteClass, "collectRadius");
    gCrateRegistry.methods!(CrateSprite, "blowStuffies")();
    gCrateRegistry.property_ro!(CrateSprite, "crateType")();
}
