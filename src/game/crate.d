module game.crate;

import game.core;
import game.events;
import game.sequence;
import game.sprite;
import game.teamtheme;
import gui.rendertext;
import physics.all;
import utils.vector2;
import utils.time;
import utils.misc;

//sender is the newly dropped crate
alias DeclareEvent!("crate_drop", CrateSprite) OnCrateDrop;
//sender is the crate, first parameter is the collecting team member
alias DeclareEvent!("crate_collect", CrateSprite, GameObject) OnCrateCollect;

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

class CrateSprite : Sprite {
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

    protected this (CrateSpriteClass spriteclass) {
        super(spriteclass);
        myclass = spriteclass;

        crateZone = new PhysicZoneCircle(Vector2f(), myclass.collectRadius);
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

    override void simulate() {
        //this also makes it near impossible to implement it in Lua
        //should connect them using constraints (or so)
        crateZone.pos = physics.pos;

        super.simulate();
    }

    private bool spyVisible(Sequence s) {
        //only controller dependency left in this file
        auto m = engine.getControlledTeamMember();
        if (!m)
            return false;
        return m.crate_spy && !isUnderWater();
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

