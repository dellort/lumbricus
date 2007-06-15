module game.baseengine;

import game.gobject;
import game.physic;
import utils.mylist;
import utils.time;

//maybe keep in sync with game.Scene.cMaxZOrder
enum GameZOrder {
    Invisible = 0,
    Background,
    BackLayer,
    BackWater,
    BackWaterWaves1,   //water behind the level
    BackWaterWaves2,
    Level,
    FrontLowerWater,  //water before the level
    Objects,
    Names, //controller.d/WormNameDrawer
    FrontUpperWater,
    FrontWaterWaves1,
    FrontWaterWaves2,
    FrontWaterWaves3,
}

//base class for game engine
//engines have a physicworld, manage game objects and do time-based simulation
class BaseGameEngine : GameObjectHandler {
    PhysicWorld mPhysicWorld;
    package List!(GameObject) mObjects;
    Time lastTime;
    Time currentTime;

    this() {
        mPhysicWorld = new PhysicWorld();

        mObjects = new List!(GameObject)(GameObject.node.getListNodeOffset());
    }

    void activate(GameObject obj) {
        mObjects.insert_tail(obj);
    }

    void deactivate(GameObject obj) {
        mObjects.remove(obj);
    }

    PhysicWorld physicworld() {
        return mPhysicWorld;
    }

    protected void simulate(float deltaT) {
    }

    void doFrame(Time gametime) {
        currentTime = gametime;
        float deltaT = (currentTime - lastTime).msecs/1000.0f;
        simulate(deltaT);
        mPhysicWorld.simulate(currentTime);
        //update game objects
        //NOTE: objects might be inserted/removed while iterating
        //      maybe one should implement a safe iterator...
        GameObject cur = mObjects.head;
        while (cur) {
            auto o = cur;
            cur = mObjects.next(cur);
            o.simulate(deltaT);
        }
        lastTime = currentTime;
    }

    //remove all objects etc. from the scene
    void kill() {
        //must iterate savely
        GameObject cur = mObjects.head;
        while (cur) {
            auto o = cur;
            cur = mObjects.next(cur);
            o.kill();
        }
    }
}
