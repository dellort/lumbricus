//the network server as commandline program
//Note: lumbricus network support is very experimental and only useful on LAN
module lumbricus_server;

import common.init;
import net.cmdserver;

int main(char[][] args) {
    return wrapMain(args, &lmain);
}

void lmain(char[][] args) {
    init(args[1..$]);
    runCmdServer();
}
