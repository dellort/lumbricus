module framework.driver_base;

import framework.globalsettings;
import utils.list2;
import utils.misc;

import tango.core.WeakRef;

import str = utils.string;
import math = tango.math.Math;
import cstdlib = tango.stdc.stdlib;

/+
//periodic cleanups (gets actually called each frame)
void delegate()[] gPeriodicCleanups;
+/

enum CacheRelease {
    Soft,   //don't release in-use resources (such as playing sounds)
    Unused, //only release resources that haven't been in use for a long time
    Hard,   //force release of all resources
}

//release caches on special occations
int delegate(CacheRelease)[] gCacheReleasers;

private {
    Setting[char[]] gDrivers;
    Object function()[char[]] gDriverFactory;
}

//add a driver type; def is the default driver for that type
//e.g. driver_kind="draw", def="opengl"
void addDriverType(char[] driver_kind, char[] def) {
    gDrivers[driver_kind] = addSetting!(char[])("driver." ~ driver_kind, def,
        SettingType.Choice);
}

//the driver name is expected to be in the form "driverkind_name"
//e.g. base sdl driver is "base_sdl" and base sdl draw driver is "draw_sdl"
void registerFrameworkDriver(T)(char[] name) {
    char[] orgname = name;
    foreach (char[] kind, Setting st; gDrivers) {
        if (str.eatStart(name, kind ~ "_")) {
            assert(!(orgname in gDriverFactory), "double entry? "~orgname);
            gDriverFactory[orgname] = function Object() { return new T(); };
            st.choices ~= name;
            return;
        }
    }
    assert(false, "driver type not found for driver "~name);
}

//doesn't belong here, may want to move to the files as noted in the comments
static this() {
    addDriverType("base", "sdl");       //main.d
    addDriverType("draw", "opengl");    //surface.d or drawing.d
    addDriverType("sound", "none");     //sound.d
    addDriverType("font", "freetype");  //font.d
}

//get what's returned
//return what's get
//(what?)
//driver name for a driver kind, e.g. type=="draw" => return "draw_opengl"
char[] getSelectedDriver(char[] type) {
    Setting st = gDrivers[type];
    //reassemble what was parsed in registerFrameworkDriver()
    return type ~ "_" ~ st.value;
}

//name is the full name for the framework driver, e.g. "draw_opengl"
T createDriver(T)(char[] name) {
    auto pctor = name in gDriverFactory;
    if (!pctor)
        throwError("framework driver not found: {}", name);
    return castStrict!(T)((*pctor)());
}

//all these types are just helpers (drivers don't need to use them)

abstract class Driver {
    //called each frame
    void tick() {}

    //return number of released objects
    int releaseCaches(CacheRelease cr) { return 0; }

    //for statistics
    int usedObjects() { return 0; }

    //end the driver (shouldn't call anything on it after this)
    void destroy() {}
}

//for use with DriverResource
//e.g. Surface is derived from this
//only purpose: storing a possibly allocated driver object
abstract class Resource {
    private {
        DriverResource mDriverResource;
    }

    //this is only called from DriverResource
    private void setDriverResource(DriverResource s) {
        mDriverResource = s;
    }

    //returns null if no driver object created yet
    final DriverResource driverResource() {
        return mDriverResource;
    }

    final void unload() {
        if (driverResource) {
            driverResource.destroy();
            //the driver is supposed to actually release the DriverResource
            assert(!driverResource());
        }
    }
}

//shitty helper with exact DriverResource type
abstract class ResourceT(DriverResourceT) : Resource {
    static assert(is(DriverResourceT : DriverResource));

    final DriverResourceT driverResource() {
        return castStrict!(DriverResourceT)(super.driverResource());
    }
}

abstract class DriverResource {
    private {
        //reference to the real object
        WeakReference!(Resource) mRef;
        bool mValid; //was not destroyed
        ResDriver mDriver;
    }

    ObjListNode!(typeof(this)) mListNode;

    //you know what? fuck real ctors
    //derived classes should call this at the end of their ctor
    //Resource is e.g. Surface
    void ctor(ResDriver owner, Resource real_object) {
        assert(!!owner);
        assert(!!real_object);
        assert(!mValid);
        mValid = true;
        mDriver = owner;
        mRef = new typeof(mRef)(real_object);
        real_object.setDriverResource(this);
        //try to add only if construction was successful, or something
        mDriver.mRefList.add(this);
    }

    //return if in immediate use, such as a sound playing
    //resources that can be recreated without trouble can always return false
    bool isInUse() {
        return false;
    }

    final Resource getResource() {
        return mRef.get();
    }

    //possibly free the resource
    bool pollRelease() {
        if (mRef.get() || !mValid)
            return false;
        //never called; something is wrong; maybe nothing here makes sense
        //Trace.formatln("free due to poll release!");
        destroy();
        return true;
    }

    //deallocate - override this
    void destroy() {
        assert(mValid);
        if (auto r = getResource()) {
            r.setDriverResource(null);
        }
        mValid = false;
        mDriver.mRefList.remove(this);
        mRef.clear();
        delete mRef;
    }
}

//xxx resource managment is copy&pasted from LuaRef handling; should unify
abstract class ResDriver : Driver {
    private {
        ObjectList!(DriverResource, "mListNode") mRefList; //created resources
        int mRefListWatermark; //pseudo-GC
    }

    this() {
        mRefList = new typeof(mRefList)();
    }

    abstract protected DriverResource createDriverResource(Resource res);

    //get or create driver resource (null on failure)
    final DriverResource requireDriverResource(Resource res) {
        DriverResource dr = res.driverResource;
        if (!dr) {
            //NOTE: may return null
            dr = createDriverResource(res);
            assert(res.driverResource is dr);
        }
        return dr;
    }

    //release GC'ed resources
    override void tick() {
        //this watermark stuff is just an attempt to reduce unnecessary work
        if (mRefList.count <= mRefListWatermark)
            return;
        foreach (DriverResource r; mRefList) {
            //r might remove itself from mRefList
            r.pollRelease();
        }
        mRefListWatermark = mRefList.count;
        return;
    }

    override int releaseCaches(CacheRelease cr) {
        int n = 0;
        foreach (DriverResource r; mRefList) {
            if (r.isInUse() && cr != CacheRelease.Hard)
                continue;
            r.destroy();
            n++;
        }
        return n;
    }

    override int usedObjects() {
        return mRefList.count();
    }

    //can be overridden; should call this to release internal resource list
    override void destroy() {
        while (!mRefList.empty) {
            auto r = mRefList.head();
            r.destroy();
        }
        mRefList = null;
    }
}

//for FontManager and SoundManager
class ResourceManager {
    int releaseCaches(CacheRelease cr) { return 0; }
    abstract void unloadDriver();
    abstract void loadDriver(char[] driver_name);
    void tick() {}
    int usedObjects() { return 0; }
    //name passed to registerDriverType()
    abstract char[] getDriverType();
}

//resource manager for a specific driver type
//this class is a singleton (there'd be no inheritance if it weren't an object)
//basically, this is just bloaty boiler plate code shared across all drivers
abstract class ResourceManagerT(DriverT) : ResourceManager {
    static assert(is(DriverT : ResDriver));
    private {
        DriverT mDriver;
        typeof(this) gSingleton;
        char[] mDriverType;
    }

    this(char[] driver_type_name) {
        mDriverType = driver_type_name;
        assert(!gSingleton);
        gSingleton = this;
    }

    override char[] getDriverType() {
        return mDriverType;
    }

    final DriverT driver() {
        return mDriver;
    }

    override void loadDriver(char[] name) {
        if (mDriver)
            assert(false, "driver already loaded");
        mDriver = createDriver!(DriverT)(name);
    }

    override void unloadDriver() {
        if (!mDriver)
            return;
        mDriver.destroy();
        mDriver = null;
    }

    override int releaseCaches(CacheRelease cr) {
        return mDriver ? mDriver.releaseCaches(cr) : 0;
    }

    override int usedObjects() {
        return mDriver ? mDriver.usedObjects() : 0;
    }

    override void tick() {
        if (driver)
            driver.tick();
    }
}
