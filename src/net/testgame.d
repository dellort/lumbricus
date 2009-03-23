module net.testgame;

///This is a minimal multi-client test game, currently without any network
///functions.
///Contains: multiple clients, fixed framerate (tick-based), input handling,
///   separate physics/engine/display
///The "game" creates one directly controllable dot for each "player"
///
/// --== Challenge: Network this! ==--

import common.task;
import framework.framework;
import gui.widget;
import gui.wm;
import utils.time;
import utils.vector2;

//Fixed length of a game-engine tick
const cTickLength = timeMsecs(30);

//Physics engine
//State: mWorldSize
class GameTestPhysics {
    Vector2f mWorldSize;
    GameTestParticle[] mParticles;

    this(Vector2f worldSize) {
        mWorldSize = worldSize;
    }

    //makes a new particle that will be simulated
    GameTestParticle createParticle() {
        auto p = new GameTestParticle(this);
        mParticles ~= p;
        return p;
    }

    Vector2f worldSize() {
        return mWorldSize;
    }

    void tick() {
        //update all physical objects
        foreach (p; mParticles) {
            p.tick();
            //TODO: particle collisions
        }
    }
}

//Physical object
//State: mPos, mVel, mAccel
class GameTestParticle {
    Vector2f mPos, mVel, mAccel;
    GameTestPhysics mPhys;

    this(GameTestPhysics parent) {
        mPhys = parent;
        mPos = Vector2f(0);
        mVel = Vector2f(0);
    }

    void setPos(Vector2f p) {
        mPos = p;
    }
    void setAccel(Vector2f a) {
        mAccel = a;
    }
    Vector2f pos() {
        return mPos;
    }

    void tick() {
        //movement
        mPos = mPos + cTickLength.secsf * mVel;
        mVel = mVel* (1.0f - 0.6f*cTickLength.secsf); //dampening
        //collision
        if (mPos.x < 0) {
            mPos.x = -mPos.x;
            mVel.x = -mVel.x;
        }
        if (mPos.y < 0) {
            mPos.y = -mPos.y;
            mVel.y = -mVel.y;
        }
        if (mPos.x > mPhys.worldSize.x) {
            mPos.x = 2*mPhys.worldSize.x - mPos.x;
            mVel.x = -mVel.x;
        }
        if (mPos.y > mPhys.worldSize.y) {
            mPos.y = 2*mPhys.worldSize.y - mPos.y;
            mVel.y = -mVel.y;
        }
        //acceleration
        mVel += mAccel*cTickLength.secsf;
    }
}

//Game-object representation of physical object (with input handling)
//State: mDirKeys (input state)
class GameTestDot {
    //connection to physics
    GameTestParticle mParticle;
    //input state
    float[4] mDirKeys = 0;
    //backlink to game engine
    GameTestGame mGame;

    //creates a dot and its physical object
    this(GameTestGame parent) {
        mGame = parent;
        mParticle = mGame.phys.createParticle();
        mParticle.setPos(Vector2f(0));
    }

    void setPos(Vector2f p) {
        mParticle.setPos(p);
    }
    Vector2f pos() {
        return mParticle.pos;
    }

    //handle a key event
    void keypress(int dir, bool up) {
        mDirKeys[dir] = up?0:1.0f;
        mParticle.setAccel(120.0f*Vector2f(mDirKeys[1] - mDirKeys[0], mDirKeys[3] - mDirKeys[2]));
    }

    void tick() {
    }
}

//Game engine, manages game time (ticks)
class GameTestGame {
    GameTestPhysics mPhys;
    GameTestDot[] mDots;
    int mTick;

    //create and initialize game world
    this(Vector2f worldSize) {
        mPhys = new GameTestPhysics(worldSize);
    }

    //connect a client
    //control is directly attached to a game object (each client controls
    //  exactly one dot)
    GameTestDot connect() {
        mDots ~= new GameTestDot(this);
        mDots[$-1].setPos(worldSize/2);
        return mDots[$-1];
    }

    //advance game time by one tick (fixed duration)
    void tick() {
        mTick++;
        mPhys.tick();
        foreach (d; mDots) {
            d.tick();
        }
    }

    int currentTick() {
        return mTick;
    }

    //array of all game objects (no protection implemented)
    GameTestDot[] dots() {
        return mDots;
    }

    GameTestPhysics phys() {
        return mPhys;
    }

    Vector2f worldSize() {
        return mPhys.worldSize;
    }
}

//GUI display of game state
class GameTestDisplay : Widget {
    GameTestGame mGame;
    GameTestDot mMyDot;

    this(GameTestGame game) {
        mGame = game;
        mMyDot = mGame.connect();
    }

    override void onDraw(Canvas c) {
        foreach (d; mGame.dots) {
            auto p = toVector2i(d.pos);
            if (d is mMyDot)
                c.drawFilledCircle(p, 3, gColors["red"]);
            else
                c.drawFilledCircle(p, 3, gColors["black"]);
        }
    }

    override protected Vector2i layoutSizeRequest() {
        return toVector2i(mGame.worldSize);
    }

    bool canHaveFocus() {
        return true;
    }

    override protected void onKeyEvent(KeyInfo info) {
        if (info.type == KeyEventType.Down || info.type == KeyEventType.Up)
        {
            int dir;
            switch (info.code) {
                case Keycode.LEFT:
                    dir = 0;
                    break;
                case Keycode.RIGHT:
                    dir = 1;
                    break;
                case Keycode.UP:
                    dir = 2;
                    break;
                case Keycode.DOWN:
                    dir = 3;
                    break;
                default:
                    return;
            }
            //send keypress to engine
            mMyDot.keypress(dir, info.type == KeyEventType.Up);
        }
    }
}

class GameTest : Task {
    GameTestGame mGame;
    GameTestDisplay mDisplay1, mDisplay2;
    Time t;

    this(TaskManager tm, char[] args = "") {
        super(tm);
        //create engine
        mGame = new GameTestGame(Vector2f(400, 400));
        //connect clients
        mDisplay1 = new GameTestDisplay(mGame);
        mDisplay2 = new GameTestDisplay(mGame);
        t = timeCurrentTime();

        gWindowManager.createWindow(this, mDisplay1, "Testgame Client#1");
        gWindowManager.createWindow(this, mDisplay2, "Testgame Client#2");
    }
    override protected void onFrame() {
        //advance game time for engine
        Time t2 = timeCurrentTime();
        while (t2 - t > cTickLength) {
            mGame.tick();
            t += cTickLength;
        }
    }
    static this() {
        TaskFactory.register!(typeof(this))("testgame");
    }
}
