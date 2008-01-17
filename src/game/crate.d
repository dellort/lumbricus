module game.crate;

import game.gobject;
import game.animation;
import physics.world;
import game.game;
import game.sprite;
import utils.misc;
import utils.vector2;
import utils.time;
import utils.log;
import utils.misc;
import utils.configfile;
import std.math;
import str = std.string;

class CrateSprite : GObjectSprite {
    private {
        CrateSpriteClass myclass;
        CircularTrigger collectTrigger;
    }

    //type will be mostly WeaponClass for weapon-crates
    //other crates (tool, medi) contain stuff I didn't think about yet
    Object[] stuffies;

    protected this (GameEngine engine, CrateSpriteClass spriteclass) {
        super(engine, spriteclass);
        myclass = spriteclass;

        collectTrigger = new CircularTrigger(Vector2f(), myclass.collectRadius);
        collectTrigger.onTrigger = &oncollect;
        //doesntwork
        //collectTrigger.collision = physics.collision;
        engine.physicworld.add(collectTrigger);
    }

    public void collected() {
        die();
    }

    override protected void die() {
        collectTrigger.dead = true;
        super.die();
    }

    private void oncollect(PhysicTrigger sender, PhysicObject other) {
        if (other is physics)
            return; //lol
        engine.collectCrate(this, other);
    }

    override protected void physUpdate() {
        collectTrigger.pos = physics.pos;
        if (physics.isGlued) {
            setState(myclass.st_normal);
        } else {
            //falling too fast -> parachute
            //xxx: if it flies too fast or in a too wrong direction, explode
            if (physics.velocity.length > myclass.enterParachuteSpeed) {
                setState(myclass.st_parachute);
            }
        }
        super.physUpdate();
    }
}

//the factories work over the sprite classes, so we need one
class CrateSpriteClass : GOSpriteClass {
    float enterParachuteSpeed;
    float collectRadius;

    StaticStateInfo st_creation, st_normal, st_parachute;

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
    }
    override CrateSprite createSprite() {
        return new CrateSprite(engine, this);
    }

    static this() {
        SpriteClassFactory.register!(typeof(this))("crate_mc");
    }
}

