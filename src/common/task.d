module common.task;
import utils.factory;
import utils.log;

//maybe should replaced by a more complete signals & slots implementation
//or use the quite strange one from Phobos
//takes argument types as tuple; return value is fixed to void
struct MulticastDelegate(DelegateArgs...) {
    alias void delegate(DelegateArgs) DelegateType;

    private DelegateType[] mDelegates;

    void call(DelegateArgs a) {
        foreach (d; mDelegates) {
            d(a);
        }
    }

    void clear() {
        mDelegates = null;
    }

    void opCatAssign(DelegateType dg) {
        mDelegates ~= dg;
    }
}

/// something which can get created, listed, and destroyed
/// it can add commands and GUI elements to the program
/// it doesn't have anything to do with real processes or threads
class Task {
    private {
        TaskManager mManager;
        int mTaskID;
        bool mAlive;
        bool mKilled;
        MulticastDelegate!(Task) mOnDeath;
    }

    /// registered delegates are invoked when the reallydead() property
    /// becomes true
    void registerOnDeath(mOnDeath.DelegateType callback) {
        mOnDeath ~= callback;
    }

    final TaskManager manager() {
        return mManager;
    }

    final int taskID() {
        return mTaskID;
    }

    /// if the task is perfectly alive
    final bool alive() {
        return mAlive;
    }

    /// if the task did fully execute its onKill()
    /// (there's a time window where ((!alive) && (!reallydead)) == true)
    bool reallydead() {
        return mKilled;
    }

    this(TaskManager tc) {
        //fortunately D enforce use of this constructor
        assert(tc !is null);
        tc.registerTask(this);
        mAlive = true;
    }

    ///forced kill
    final void kill() {
        if (!mAlive)
            return;
        mAlive = false;
        mManager.killTask(this);
        onKill();
        mKilled = true;
        mOnDeath.call(this);
        mOnDeath.clear();
    }

    ///ask a task to kill itself
    void terminate() {
        //default: okay
        kill();
    }

    //called by TaskManager
    private void doFrame() {
        onFrame();
    }

    /// guaranteed to be called on each frame (before GUI is rendered)
    protected void onFrame() {
    }

    /// destructor
    protected void onKill() {
    }
}

/// a singleton which manages Task creation and destruction
/// also provides access to the GUI
class TaskManager {
    private {
        //id -> Task (task creation and destruction is considered to be seldom)
        Task[int] mTaskList;
        int mTaskIDAlloc;
        Log mLog;
    }

    this() {
        mLog = registerLog("taskmanager");
    }

    //called by Task constructor only
    private void registerTask(Task task) {
        assert(!task.mManager);
        int id = ++mTaskIDAlloc;
        mTaskList[id] = task;
        task.mManager = this;
        task.mTaskID = id;
        mLog("task created: %s", task.mTaskID);
    }

    //called by Task.kill() only
    private void killTask(Task task) {
        mTaskList.remove(task.mTaskID);
        mLog("task killed: %s", task.mTaskID);
    }

    //called from TopLevel on each frame
    public void doFrame() {
        //oh, and the order how the Tasks are called is undefined anyway
        foreach (Task t; mTaskList) {
            t.doFrame();
        }
    }

    //create a task list of _living_ tasks; it's slow, but anyway
    Task[] taskList() {
        //.dup to protect the data isn't necessary I guess?
        return mTaskList.values;
    }
}

//and the almighty factory...
//noone is forced to register Tasks here, but you can use it to start Tasks
//from the TopLevel commandline
static class TaskFactory : StaticFactory!(Task, TaskManager) {
}
