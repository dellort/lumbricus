module game.hud.gameframe;

import common.common;
import common.lua;
import common.scene;
import common.task;
import common.toplevel;
import framework.framework;
import framework.event;
import framework.i18n;
import framework.lua;
import framework.sound;
import gui.container;
import gui.label;
import gui.lua;
import gui.tablecontainer;
import gui.widget;
import gui.mousescroller;
import gui.boxcontainer;
import gui.window;
import game.controller;
import game.core;
import game.game;
import game.hud.camera;
import game.hud.gameteams;
import game.hud.gametimer;
import game.hud.gameview;
import game.hud.windmeter;
import game.hud.teaminfo;
import game.hud.preparedisplay;
import game.hud.weaponsel;
import game.hud.messageviewer;
import game.hud.powerups;
import game.hud.replaytimer;
import game.hud.network;
import game.hud.register;
import game.hud.chatbox;
import game.hud.weapondisplay;
import game.lua.base;
import game.weapon.weapon;
import game.weapon.weaponset;
import game.weapon.types;
//import levelgen.level;
import utils.interpolate;
import utils.time;
import utils.misc;
import utils.mybox;
import utils.output;
import utils.vector2;
import utils.log;

//remove it if you hate it
import game.gui.levelpaint;

import tango.math.Math;


//like LuaInterpreter, but sends commands via GameInfo.control.executeCommand()
//also, will not output the version message
//xxx still dangerous, as it relies on ConsoleUtils.autocomplete not having
//    any side-effects (else pressing <Tab> could locally change the gamestate)
class GameLuaInterpreter : LuaInterpreter {
    private GameInfo mGame;

    this(void delegate(char[]) a_sink, GameInfo game) {
        super(a_sink, game.engine.scripting, true);
        mGame = game;
    }

    override void runLuaCode(char[] code) {
        //sending the command directly to the Lua state would bypass
        //  networking/replay logging
        mGame.control.execCommand("exec " ~ code);
    }
}

class GameFrame : SimpleContainer {
    GameInfo game;
    GameView gameView;

    private {
        MouseScroller mScroller;
        SimpleContainer mGui;

        WeaponDisplay mWeaponDisplay;
        WeaponSelWindow mWeaponSel;
        //movement of mWeaponSel for blending in/out
        //InterpolateLinear!(float) mWeaponInterp;
        InterpolateExp!(float) mWeaponInterp;

        TeamWindow mTeamWindow;
        Label mPauseLabel;
        BoxContainer mSideBar;

        Widget[] mHudWidgets;

        enum ConsoleMode {
            Chat,
            Script,
        }

        Chatbox mConsoleBox;
        ConsoleMode mConsoleMode;
        LuaInterpreter mScriptInterpreter;

        Time mLastFrameTime;
        bool mFirstFrame = true;
        Vector2i mScrollToAtStart;

        //if non-null, this dialog is modal and blocks other game input
        Widget mModalDialog;

        Source mMusic;

        bool mCameraPauseHack;
    }

    private void updateWeapons(WeaponSet bla) {
        TeamMember t = game.control.getControlledMember();
        //don't change anything if another team's weapon set was changed
        if (t && t.team.weapons !is bla)
            return;
        mWeaponSel.update(t ? t.team.weapons : null);
    }

    private void teamChanged() {
        TeamMember t = game.control.getControlledMember();
        mWeaponSel.update(t ? t.team.weapons : null);
        if (!t && isWeaponWindowVisible())
            mWeaponInterp.revert();
    }

    private void selectWeapon(WeaponClass c) {
        //xxx not really correct, the "weapon" call could fail in the engine
        //    better: callback onWeaponSelect
        //when a point weapon is selected, hide the weapon window
        mWeaponInterp.setParams(0, 1.0f);
        game.control.execCommand("weapon "~c.name);
    }

    private void selectCategory(char[] category) {
        auto m = game.control.getControlledMember();
        mWeaponSel.checkNextWeaponInCategoryShortcut(category,
            m?m.control.currentWeapon():null);
    }

    //scroll to level center
    void setPosition(Vector2i pos, bool reset = true) {
        if (mFirstFrame) {
            //cannot scroll yet because gui layouting is not done
            mScrollToAtStart = pos;
        } else {
            mScroller.offset = mScroller.centeredOffset(pos);
            //this call makes sure the camera stays at the new position
            //  for some time instead of just jumping back to the locked object
            if (reset)
                gameView.resetCamera;
        }
    }
    Vector2i getPosition() {
        return mScroller.uncenteredOffset(mScroller.offset);
    }

    override void internalSimulate() {
        //some hack (needs to be executed before GameView's simulate() call)
        if (mFirstFrame) {
            mFirstFrame = false;
            //scroll to level center
            setPosition(mScrollToAtStart, false);
        }
        super.internalSimulate();
    }

    override protected void simulate() {
        super.simulate();

        auto curtime = game.engine.interpolateTime.current;
        if (mLastFrameTime == Time.init)
            mLastFrameTime = curtime;
        auto delta = curtime - mLastFrameTime;
        mLastFrameTime = curtime;

        bool finished = true;
        foreach (Team t; game.controller.teams) {
            foreach (TeamMember tm; t.members) {
                if (tm.currentHealth != tm.healthTarget())
                    finished = false;
            }
        }
        //only do the rest (like animated sorting) when all was counted down
        mTeamWindow.update(finished);

        mScroller.scale = Vector2f(gameView.zoomLevel, gameView.zoomLevel);

        int mode = 0;
        if (!hudNeedMouseInput()) {
            mode = 1;
            if (auto am = game.control.getControlledMember()) {
                //mouse follow when the weapon requires clicking, and
                //the weapon window is hidden
                bool shouldFollow = am.control.pointMode != PointMode.none
                    && !isWeaponWindowVisible();
                if (shouldFollow) {
                    mode = 2;
                }
            }
        }
        if (!gameView.focused())
            mode = 0;
        switch (mode) {
            case 1:
                //direct scrolling
                mScroller.mouseScrolling = true;
                break;
            case 2:
                //mouse follow (i.e. pushing the borders)
                if (!mScroller.mouseFollow) {
                    mScroller.startMouseFollow(Vector2i(150));
                }
                break;
            default:
                //no scrolling, normal mouse cursor
                mScroller.mouseScrolling = false;
                if (mScroller.mouseFollow) {
                    mScroller.stopMouseFollow();
                }
        }

        int wsel_edge = mWeaponSel.findParentBorderDistance(1, 0, false);
        mWeaponSel.setAddToPos(
            Vector2i(cast(int)(mWeaponInterp.value*wsel_edge), 0));
        mWeaponSel.visible = 1.0f-mWeaponInterp.value > float.epsilon;

        //current weapon icon is visible when weapon select window is not
        int wdis_edge = mWeaponDisplay.findParentBorderDistance(1, 0, false);
        mWeaponDisplay.setAddToPos(
            Vector2i(cast(int)((1.0f-mWeaponInterp.value)*wdis_edge), 0));

        /+ disabled for now; should work flawlessly
        //unpaused if any child has focus (normally GameView)
        game.shell.pauseBlock(!subFocused(), this);
        game.shell.pauseBlock(!gFramework.appFocused, gFramework);
        +/

        bool paused = game.shell.paused;

        mPauseLabel.visible = paused;
        if (mMusic)
            mMusic.paused = paused;

        if (paused) {
            if (!mCameraPauseHack && gameView.enableCamera) {
                gameView.enableCamera = false;
                mCameraPauseHack = true;
            }
        } else {
            if (mCameraPauseHack)
                gameView.enableCamera = true;
            mCameraPauseHack = false;
        }
    }

    void fadeoutMusic(Time t) {
        mMusic.stop(t);
    }

    void kill() {
        mMusic.stop();
    }

    override bool doesCover() {
        //assumption: gameView covers this widget completely, i.e. no borders
        //etc...; warning: assumption isn't true if level+gameView is smaller
        //than window; would need to check that
        return gameView.doesCover();
    }

    private class ModalNotice : SimpleContainer {
        this(Widget client) {
            focusable = true;
            isClickable = true;
            client.setLayout(WidgetLayout.Noexpand());
            addChild(client);
        }

        void lock() {
            claimFocus();
            if (!captureEnable(true, true, false)) {
                remove();
                return;
            }
            game.shell.pauseBlock(true, this);
        }

        override bool onKeyDown(KeyInfo info) {
            this.outer.mModalDialog = null;
            remove();
            game.shell.pauseBlock(false, this);
            return true;
        }
    }

    //show current (game) key bindings
    private void keyHelp() {
        auto dlg = new ModalNotice(gameView.createKeybindingsHelp());
        add(dlg);
        mModalDialog = dlg;
        //mScroller.mouseScrolling = false; //protect against random fuckup
        dlg.lock();
    }

    bool scrollOverride;

    private void toggleWeaponWindow() {
        if (game.control.getControlledMember()) {
            scrollOverride = false;
            mWeaponInterp.revert();
        } else {
            //if right click wouldn't do anything
            toggleScroll();
        }
    }
    private void toggleScroll() {
        scrollOverride = !scrollOverride;
    }
    private bool isWeaponWindowVisible() {
        return mWeaponInterp.target == 0;
    }
    //return true if any hud element (other than the game) requires clicking
    private bool hudNeedMouseInput() {
        //currently just the weapon window; maybe others will be added later
        //  (e.g. pause window)
        return isWeaponWindowVisible() || scrollOverride
            || gTopLevel.consoleVisible()
            || (game.shell.paused() && !mPauseLabel.visible());
    }

    //hud elements requested by gamemode
    private void onHudAdd(Object link) {
        argcheck(link);
        mHudWidgets ~= instantiateHud(mGui, game, link);
    }

    private void onHudRemove(Object link) {
        foreach (int idx, h; mHudWidgets) {
            if (h is link) {
                mHudWidgets = mHudWidgets[0..idx] ~ mHudWidgets[idx+1..$];
                h.remove();
                break;
            }
        }
    }

    private void showLogEntry(LogEntry e) {
        writeColoredLogEntry(e, false, &mConsoleBox.output.writefln);
    }

    private bool mLogAdded;
    override void onLinkChange() {
        if (!mLogAdded && isLinked()) {
            Widget cur = this;
            while (cur) {
                if (auto w = cast(WindowWidget)cur) {
                    mLogAdded = true;
                    w.guiLogSink = &showLogEntry;
                    return;
                }
                cur = cur.parent;
            }
        }
    }

    void scriptAddHudWidget(LuaGuiAdapter gui, char[] where = "sidebar") {
        argcheck(gui);
        Widget w = gui.widget();
        if (where == "sidebar") {
            mSideBar.add(w, WidgetLayout.Aligned(-1,-1, Vector2i(0,20)));
        } else if (where == "fullscreen") {
            mGui.add(w, WidgetLayout());
        } else if (where == "gameview") {
            w.setLayout(WidgetLayout());
            gameView.addSubWidget(w);
        } else if (where == "window") {
            gWindowFrame.createWindow(w, "script", Vector2i(300, 500));
        } else {
            argcheck(false, "invalid 'where' parameter: '"~where~"'");
        }
    }
    void scriptRemoveHudWidget(LuaGuiAdapter gui) {
        gui.widget.remove();
    }

    private void initSound() {
        auto mus = game.engine.resources.get!(Sample)("game");
        mMusic = mus.createSource();
        mMusic.looping = true;
        mMusic.play();
    }

    //chatbox or whatever it is

    private void cmdExecConsole(MyBox[] args, Output output) {
        char[] text = args[0].unbox!(char[])();
        if (mConsoleMode == ConsoleMode.Script) {
            mScriptInterpreter.exec(text);
        } else if (mConsoleMode == ConsoleMode.Chat) {
            mConsoleBox.output.writefln("chat not implemented, lol, but you "
                "wanted to say: {}", text);
        }
    }

    private void tabComplete(char[] line, int cursor1, int cursor2,
        void delegate(int, int, char[]) edit)
    {
        //chat mode could have completion for nicks or common words
        if (mConsoleMode == ConsoleMode.Script) {
            mScriptInterpreter.tabcomplete(line, cursor1, cursor2, edit);
        }
    }

    private void toggleChat() {
        setConsoleMode(ConsoleMode.Chat, true);
    }
    private void toggleScript() {
        setConsoleMode(ConsoleMode.Script, true);
    }

    private void setConsoleMode(ConsoleMode mode, bool activate) {
        if (mode != mConsoleMode) {
            mConsoleMode = mode;
            char[] name = "unknown";
            if (mode == ConsoleMode.Chat) {
                name = "chat";
            } else if (mode == ConsoleMode.Script) {
                name = "scripting";
            }
            mConsoleBox.output.writefln("Chat box set to {} mode.", name);
        }
        if (activate)
            mConsoleBox.activate();
    }

    //this is just some sort of joke/easteregg/test/doingitbecauseican
    private void levelPaintHack() {
        gWindowFrame.createWindow(new PainterWidget(
            (cast(GameEngine)game.engine).gameLandscapes[0].landscape), "hi");
    }

    this(GameInfo g) {
        game = g;

        doClipping = true;

        mGui = new SimpleContainer();

        //xxx ehrm, lol... config file?
        mGui.add(new WindMeter(game),
            WidgetLayout.Aligned(1, 1, Vector2i(5, 5)));
        mGui.add(new PowerupDisplay(game),
            WidgetLayout.Aligned(1, -1, Vector2i(5, 20)));
        mWeaponDisplay = new WeaponDisplay(game);
        mGui.add(mWeaponDisplay, WidgetLayout.Aligned(1, 1, Vector2i(5, 40)));
        auto lay = WidgetLayout.Aligned(0, -1, Vector2i(0, 5));
        lay.border = Vector2i(5, 1);
        mGui.add(new MessageViewer(game), lay);
        mGui.add(new ReplayTimer(game),
            WidgetLayout.Aligned(-1, -1, Vector2i(10, 0)));
        mConsoleBox = new Chatbox();
        mScriptInterpreter = new GameLuaInterpreter(
            &mConsoleBox.output.writeString, g);
        mConsoleBox.cmdline.commands.addSub(globals.cmdLine);
        mConsoleBox.cmdline.commands.registerCommand("input", &cmdExecConsole,
            "text goes here", ["text..."]);
        mConsoleBox.cmdline.setPrefix("/", "input");
        mConsoleBox.setTabCompletion(&tabComplete);
        mGui.add(mConsoleBox, WidgetLayout.Aligned(-1, -1, Vector2i(5, 5)));

        mTeamWindow = new TeamWindow(game);
        mGui.add(mTeamWindow);

        gameView = new GameView(game);
        gameView.onTeamChange = &teamChanged;
        gameView.onSelectCategory = &selectCategory;
        gameView.onKeyHelp = &keyHelp;
        gameView.onToggleWeaponWindow = &toggleWeaponWindow;
        gameView.onToggleScroll = &toggleScroll;
        gameView.onToggleChat = &toggleChat;
        gameView.onToggleScript = &toggleScript;

        mScroller = new MouseScroller();
        //changed after r845, was WidgetLayout.Aligned(0, -1)
        mScroller.add(gameView, WidgetLayout());
        mScroller.zorder = -1; //don't hide the game GUI
        add(mScroller);
        add(mGui);
        if (game.connection) {
            auto n = new NetworkHud(game);
            //network error screen covers all hud elements
            n.zorder = 10;
            add(n);
        }

        gameView.camera.control = mScroller;

        mWeaponSel = new WeaponSelWindow();
        mWeaponSel.onSelectWeapon = &selectWeapon;

        mWeaponSel.selectionBindings = gameView.bindings;

        add(mWeaponSel, WidgetLayout.Aligned(1, 1, Vector2i(5, 40)));

        mWeaponSel.init(game.engine);

        mWeaponInterp.init_done(timeSecs(0.4), 0, 1);

        mPauseLabel = new Label;
        mPauseLabel.textMarkup = "\\t(gamehud.paused)";
        mPauseLabel.centerX = true;
        mPauseLabel.styles.addClass("gamepauselabel");
        mPauseLabel.visible = false;
        add(mPauseLabel, WidgetLayout.Aligned(0, -0.5));

        mSideBar = new VBoxContainer();
        add(mSideBar, WidgetLayout.Aligned(-1, -1, Vector2i(30, 50)));

        setPosition(game.engine.level.worldCenter);

        OnWeaponSetChanged.handler(game.engine.events, &updateWeapons);
        OnHudAdd.handler(game.engine.events, &onHudAdd);

        foreach (Object obj; game.engine.allHudRequests) {
            onHudAdd(obj);
        }

        //this is very violent; but I don't even know yet how game specific
        //  scripts would link into the client gui
        LuaState state = game.engine.scripting;
        LuaRegistry reg = new LuaRegistry();
        reg.method!(GameFrame, "scriptAddHudWidget")("addHudWidget");
        reg.method!(GameFrame, "scriptRemoveHudWidget")("removeHudWidget");
        reg.methods!(GameFrame, "levelPaintHack");
        state.register(reg);
        state.addSingleton!(GameFrame)(this);

        initSound();
    }
}
