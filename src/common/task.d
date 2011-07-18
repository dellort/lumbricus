module common.task;

import utils.misc;

alias Object delegate(string) CreateTaskDg;
alias bool delegate() OnFrameFn;

private {
    CreateTaskDg[string] gTaskFactory;
    OnFrameFn[] gActiveTasks;
}

//the idea is to have no monolithic (useless) Task class, but instead make such
//  an object optional, and let it have optional traits via interfaces
//I know I know, Menger said the leading "I" in interface names is MS bullshit
interface IKillable {
    void kill();
}

void registerTask(string name, CreateTaskDg create_dg) {
    assert(!(name in gTaskFactory), "already registered: "~name);
    gTaskFactory[name] = create_dg;
}

//mainly for compatibility with old stuff
//when spawnTask() is called, T is instantiated as new T() or new T(args)
//you have to add your onFrame function manually, though (eith addTask())
void registerTaskClass(T)(string name) {
    //first try with args, then without
    CreateTaskDg fn;
    string s;
    static if (is(typeof({ new T(s); }))) {
        fn = delegate(string args) { Object o = new T(args); return o; };
    } else {
        fn = delegate(string args) { Object o = new T(); return o; };
    }
    registerTask(name, fn);
}

//spawnable tasks (for auto-completion)
string[] taskList() {
    return gTaskFactory.keys;
}

//raises exception on failure
//return handle to new task (can be null)
Object spawnTask(string name, string args = "") {
    auto spawner = name in gTaskFactory;
    if (!spawner)
        throwError("unknown task: '%s'", name);
    return (*spawner)(args);
}

//add a function that will be called every frame; if that function returns
//  false, it won't be called anymore
void addTask(OnFrameFn fn) {
    gActiveTasks ~= fn;
}

void runTasks() {
    //robust enough to deal with additions/removals during iterating
    int[] removeList;
    foreach (int idx, cb; gActiveTasks) {
        if (!cb())
            removeList ~= idx;
    }
    //works even after modifications because the only possible change is adding
    //  new callbacks with addTask()
    foreach_reverse (x; removeList) {
        auto old = gActiveTasks;
        gActiveTasks = gActiveTasks[0..x] ~ gActiveTasks[x+1..$];
        //get rid of the old fragment; it's only garbage that may block the GC
        assert(gActiveTasks.ptr !is old.ptr);
        delete old;
    }
}

