module framework.commandline;

import framework.console;
import framework.framework;
import framework.keysyms;

public class CommandLine {
    private Console mConsole;

    this(Console cons) {
        mConsole = cons;
    }

    public int registerCommand(char[] name, dchar[] helpText,
        void delegate(CommandLine cmdLine, int cmdId) cmdProc)
    {
        return 0;
    }

    public bool keyDown(KeyInfo infos) {

        if (infos.code == Keycode.RIGHT) {

            return true;
        }
        if (infos.code == Keycode.LEFT) {

            return true;
        }
        return false;
    }

    public bool keyPress(KeyInfo infos) {
        if (infos.code == Keycode.PAGEUP) {
            mConsole.scrollBack(1);
            return true;
        }
        if (infos.code == Keycode.PAGEDOWN) {
            mConsole.scrollBack(-1);
            return true;
        }
        if (infos.code == Keycode.BACKSPACE) {

            return true;
        }
        if (infos.code == Keycode.DELETE) {

            return true;
        }
        return false;
    }

    private void executeCommand() {

    }
}
