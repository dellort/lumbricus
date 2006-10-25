module framework.commandLine;

import framework.console;
import framework.framework;

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
        return false;
    }

    public bool keyPress(KeyInfo infos) {
        return false;
    }

    private void executeCommand() {

    }
}
