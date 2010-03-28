module game.core;

//should not be part of the game module import cycle
//will kill anyone who makes this module a part of the cycle

import common.animation;
import common.scene;
import common.resset;
import framework.framework;
import game.effects;
import game.events;
import game.particles;
import game.teamtheme;
import game.temp;
import game.levelgen.level;
import game.lua.base;
import gui.rendertext;
import physics.world;
import utils.misc;
import utils.random;
import utils.timesource;

//for now, this is the base class of GameEngine
//it makes some parts of GfxSet uneeded as well
//in the future, this class should replace both GameEngine and GfxSet
//gobject.d and glue.d should be merged into this file as well
//this class should only contain "essential" stuff, in whatever this means, and
//  stuff that still causes trouble right now (in one way or another) should
//  remain in the deprecated, old classes
//- there may be some stuff that doesn't really belong here, but as long as it
//  doesn't cause dependency trouble, it's ok
abstract class GameCore {
    private {
        Object[ClassInfo] mSingletons;
        TimeSourcePublic mGameTime, mInterpolateTime;
        Scene mScene;
        Random mRnd;
        Events mEvents;
        ScriptingObj mScripting;
        Level mLevel;
        PhysicWorld mPhysicWorld;
        ResourceSet mResources;
        ParticleWorld mParticleWorld;
        //for neutral text, I use GameCore as key (hacky but simple)
        FormattedText[Object] mTempTextThemed;
    }

    this(Level a_level, TimeSourcePublic a_gameTime,
        TimeSourcePublic a_interpolateTime)
    {
        //random seed will be fixed later during intialization
        mRnd = new Random();
        mRnd.seed(1);

        mPhysicWorld = new PhysicWorld(rnd);

        mScene = new Scene();

        mEvents = new Events();

        mParticleWorld = new ParticleWorld();

        mResources = new ResourceSet();

        mLevel = a_level;
        mGameTime = a_gameTime;
        mInterpolateTime = a_interpolateTime;

        mScripting = createScriptingObj();
        //scripting.addSingleton(this); doesn't work as expected
        scripting.addSingleton(rnd);
        scripting.addSingleton(physicWorld);
        scripting.addSingleton(physicWorld.collide);
        scripting.addSingleton(level);
    }

    //-- boring getters (but better than making everything world-writeable)

    ///looks like scene is now used for both deterministic and undeterministic
    /// stuff - normally shouldn't matter
    final Scene scene() { return mScene; }
    final Random rnd() { return mRnd; }
    final Events events() { return mEvents; }
    final ScriptingObj scripting() { return mScripting; }
    ///level being played, must not modify returned object
    final Level level() { return mLevel; }
    final PhysicWorld physicWorld() { return mPhysicWorld; }
    final ResourceSet resources() { return mResources; }
    ///time of last frame that was simulated (fixed framerate, deterministic)
    final TimeSourcePublic gameTime() { return mGameTime; }
    ///indeterministic time synchronous to gameTime, which interpolates between
    /// game engine frames
    final TimeSourcePublic interpolateTime() { return mInterpolateTime; }
    ///indeterministic particle engine
    final ParticleWorld particleWorld() { return mParticleWorld; }

    //-- can be used to avoid static module dependencies

    final void addSingleton(Object o) {
        auto key = o.classinfo;
        assert (!(key in mSingletons), "singleton exists already");
        mSingletons[key] = o;
    }

    final T singleton(T)() {
        auto ps = T.classinfo in mSingletons;
        if (!ps)
            assert(false, "singleton doesn't exist");
        //cast must always succeed, else addSingleton is broken
        return castStrict!(T)(*ps);
    }

    //-- indeterministic drawing functions


    //draw some text with a border around it, in the usual worms label style
    //see getTempLabel()
    //the bad:
    //- slow, may trigger memory allocations (at the very least it will use
    //  slow array appends, even if no new memory is really allocated)
    //- does a lot more work than just draw text and a box
    //- slow because it formats text on each frame
    //- it sucks, maybe I'll replace it by something else
    //=> use FormattedText instead with GfxSet.textCreate()
    //the good:
    //- uses the same drawing code as other _game_ labels
    //- for very transient labels, this probably performs better than allocating
    //  a FormattedText and keeping it around
    //- no need to be deterministic
    final void drawTextFmt(Canvas c, Vector2i pos, char[] fmt, ...) {
        auto txt = getTempLabel();
        txt.setTextFmt_fx(true, fmt, _arguments, _argptr);
        txt.draw(c, pos);
    }

    //return a temporary label in worms style
    //see drawTextFmt() for the why and when to use this
    //how to use:
    //- use txt.setTextFmt() to set the text on the returned object
    //- possibly call txt.textSize() to get the size including label border
    //- call txt.draw()
    //- never touch the object again, as it will be used by other code
    //- you better not change any obscure properties of the label (like font)
    //if theme is !is null, the label will be in the team's color
    final FormattedText getTempLabel(TeamTheme theme = null) {
        //xxx: AA lookup could be avoided by using TeamTheme.colorIndex
        Object idx = theme ? theme : this;
        if (auto p = idx in mTempTextThemed)
            return *p;

        FormattedText res;
        if (theme) {
            res = theme.textCreate();
        } else {
            res = WormLabels.textCreate();
        }
        res.shrink = ShrinkMode.none;
        mTempTextThemed[idx] = res;
        return res;
    }

    final void animationEffect(Animation ani, Vector2i at, AnimationParams p) {
        //if this function gets used a lot, maybe it would be worth it to fuse
        //  this with the particle engine (cf. showExplosion())
        Animator a = new Animator(interpolateTime);
        a.auto_remove = true;
        a.setAnimation(ani);
        a.pos = at;
        a.params = p;
        a.zorder = GameZOrder.Effects;
        scene.add(a);
    }
}
