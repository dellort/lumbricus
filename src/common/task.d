module common.task;

alias void function(char[]) CreateTaskFn;
alias bool delegate() OnFrameFn;

private {
    CreateTaskFn[char[]] gTaskFactory;
    OnFrameFn[] gActiveTasks;
}

void registerTask(char[] name, CreateTaskFn create_fn) {
    assert(!(name in gTaskFactory), "already registered: "~name);
    gTaskFactory[name] = create_fn;
}

//mainly for compatibility with old stuff
//when spawnTask() is called, T is instantiated as new T() or new T(args)
//you have to call your onFrame function manually, though
void registerTaskClass(T)(char[] name) {
    //first try with args, then without
    CreateTaskFn fn;
    char[] s;
    static if (is(typeof({ new T(s); }))) {
        fn = function(char[] args) { new T(args); };
    } else {
        fn = function(char[] args) { new T(); };
    }
    registerTask(name, fn);
}

//spawnable tasks (for auto-completion)
char[][] taskList() {
    return gTaskFactory.keys;
}

//return success
bool spawnTask(char[] name, char[] args = "") {
    auto spawner = name in gTaskFactory;
    if (!spawner)
        return false;
    (*spawner)(args);
    return true;
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
        gActiveTasks = gActiveTasks[0..x] ~ gActiveTasks[x+1..$];
    }
}

