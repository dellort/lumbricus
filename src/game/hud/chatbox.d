module game.hud.chatbox;

import framework.framework;
import framework.font;
import framework.commandline;
import gui.widget;
import gui.container;
import gui.boxcontainer;
import gui.logwindow;
import gui.edit;
import gui.console;
import utils.misc;
import utils.vector2;

//additionally has a default size, a special style and some focus handling
class Chatbox : GuiConsole {
    //xxx this is just needed to hide the edit on return,
    //    maybe there's a better way
    class ChatEditLine : ConsoleEditLine {
        this(CommandLineInstance cmd, LogWindow logWin) {
            super(cmd, logWin);
        }
        override void onFocusChange() {
            //hide on unfocus
            if (!focused() && visible()) {
                visible = false;
            }
        }
        override protected bool handleKeyPress(KeyInfo infos) {
            if (infos.code == Keycode.RETURN) {
                //hide on return (chat behavior)
                visible = false;
            }
            return super.handleKeyPress(infos);
        }
    }

    this(CommandLine cmdline = null) {
        super(cmdline);

        mEdit.visible = false;
        styles.addClass("chatbox");
        minSize = Vector2i(400, 175);
    }

    override EditLine createEdit() {
        auto ret = new ChatEditLine(mCmdline, mLogWindow);
        ret.prompt = "> ";
        return ret;
    }

    override bool handleChildInput(InputEvent event) {
        //only take mouse events if the EditLine is visible (i.e. focused),
        //otherwise allow "clicking through"
        //xxx could disable mouse input entirely, but maybe we add selecting
        //    and copying to LogWindow at some time
        if (!mEdit.visible)
            return false;
        return super.handleChildInput(event);
    }

    void activate() {
        if (!mEdit.visible()) {
            mEdit.visible = true;
        }
        mEdit.claimFocus();
    }
}
