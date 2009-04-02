module common.task;
import utils.array : aaDup;
import utils.factory;
import utils.log;
import utils.misc;
import utils.md;

/// something which can get created, listed, and destroyed
/// when it's "running", its onFrame method is called every frame
/// (after the screen is cleared by the framework and before GUI rendering)
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
        mOnDeath = new typeof(mOnDeath);
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
        mTaskList = aaDup(mTaskList);
        mTaskList[id] = task;
        task.mManager = this;
        task.mTaskID = id;
        mLog("task created: {}", task.mTaskID);
    }

    //called by Task.kill() only
    private void killTask(Task task) {
        mTaskList = aaDup(mTaskList);
        mTaskList.remove(task.mTaskID);
        mLog("task killed: {}", task.mTaskID);
    }

    //called from TopLevel on each frame
    public void doFrame() {
        //oh, and the order how the Tasks are called is undefined anyway
        //safe iteration: before modification, mTaskList is copied, and the
        //foreach() runs over the "old" list; also the old list could contain
        //already killed Tasks, so this needs to be checked too
        foreach (Task t; mTaskList) {
            if (t.alive())
                t.doFrame();
        }
    }

    //create a task list of _living_ tasks; it's slow, but anyway
    Task[] taskList() {
        //.dup to protect the data isn't necessary I guess?
        return mTaskList.values;
    }

    void killAll() {
        foreach (t; taskList) {
            t.kill();
        }
    }
}

//and the almighty factory...
//noone is forced to register Tasks here, but you can use it to start Tasks
//from the TopLevel commandline
alias StaticFactory!("Tasks", Task, TaskManager, char[]) TaskFactory;
