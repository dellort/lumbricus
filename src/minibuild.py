#!/usr/bin/env python

# this is just a quick&dirty compilation script
# if you need something more sophisticated, consider xfbuild:
#   http://wiki.team0xf.com/index.php?n=Tools.XfBuild

# this dmd patch is needed (to add -oq):
# http://d.puremagic.com/issues/show_bug.cgi?id=3541

EXE_DIR = "../bin/"

# xxx should include username
# also note that clean removes the full directory
BUILD_DIR = "/tmp/minibuild/"

# name of the DMD binary
DMD = "dmd"

STD_ARGS = ["-gc", "-L-lz", "-L-ldl"]
OPT = False
if not OPT:
    STD_ARGS.extend(["-unittest", "-debug"])
else:
    STD_ARGS.extend(["-inline", "-release", "-O"])
#if multiple symbols linker errors happen: add -L-z -Lmuldefs

USE_RSP = True

import sys
import re
import os
import os.path
from subprocess import Popen
#from optparse import OptionParser

# don't compile std packages/modules
IGNORE_MODULES = ["object", "tango.", "std.", "core."]

def compare_module_name(name, pattern):
    if name == pattern: return True
    if pattern.endswith(".") and name.startswith(pattern): return True
    return False

def module_is_ignored(name):
    for i in IGNORE_MODULES:
        if compare_module_name(name, i): return True
    #if len(options.include) > 0:
    #    for i in options.include:
    #        if not compare_module_name(name, i): return True
    return False

# remove everything in directory path
# if remove_self is true, remove path itself as well
def remove_recursive(path, remove_self):
    if remove_self and not os.path.exists(path):
        return
    for root, dirs, files in os.walk(path, topdown=False):
        for name in files:
            os.remove(os.path.join(root, name))
        for name in dirs:
            os.rmdir(os.path.join(root, name))
    if remove_self:
        os.rmdir(path)

def usage():
    print("Usage:")
    print("./minibuild.py rootfile.d")
    print("./minibuild.py clean")
    sys.exit(1)

if len(sys.argv) != 2:
    usage()
rootfile = sys.argv[1]
if rootfile == "clean":
    remove_recursive(BUILD_DIR, True)
    sys.exit(0)
prefix, ext = os.path.splitext(rootfile)
if ext != ".d":
    usage()
sdir, name = os.path.split(prefix)

DEST_DIR = os.path.join(BUILD_DIR, name)
DEP_FILE = os.path.join(DEST_DIR, "depfile.txt")
OBJ_DIR = os.path.join(DEST_DIR, "obj")
EXE_FILE = os.path.join(EXE_DIR, name)

# what = name of the phase (used for naming reponse files and error messages)
def calldmd(what, pargs):
    args = [DMD]
    nargs = []
    nargs.extend(STD_ARGS)
    nargs.extend(pargs)
    if USE_RSP:
        rspname = os.path.join(DEST_DIR, what+".rsp")
        rsp = open(rspname, "w")
        #wtf, writelines adds no line terminators?
        #rsp.writelines(nargs)
        rsp.writelines([x+"\n" for x in nargs])
        rsp.close()
        args.append("@" + rspname)
    else:
        args.extend(nargs)
    p = Popen(args=args,close_fds=True)
    p.wait()
    if p.returncode != 0:
        print("dmd failed (%s)." % what)
        sys.exit(1)


print("Working directory: '%s'" % DEST_DIR)
try:
    os.makedirs(OBJ_DIR)
except OSError:
    pass # exists as directory, exists as some other file, or access denied

def createdepfile():
    print("Getting dependencies...")
    calldmd("dep", [rootfile, "-oq", "-od" + OBJ_DIR, "-o-", "-deps=" + DEP_FILE])

# return list of included files; with IGNORE_MODULES filtered out
def read_and_parse_depfile():
    # get all the imported modules & filenames
    # may fail with "strange" filenames (but you couldn't use them in D anyway)
    rex = re.compile(".* : .* : ([A-Za-z0-9._]+) \((.+?)\).*")
    # include rootfile to be sure
    flist = [rootfile]
    # use a separate AA to filter double filenames; but keep the flist array so
    #   that the order isn't messed up (more determinism against shaky dmd)
    doubles = {rootfile: True}
    stat_files, stat_ifiles, stat_deps = 0, 0, 0
    try:
        file = open(DEP_FILE, "r")
    except IOError:
        return None
    for line in file:
        module, file = rex.match(line).groups()
        stat_deps = stat_deps + 1
        # xxx may want to filter out .di files as well?
        if file not in doubles:
            doubles[file] = True
            # .di files never get compiled
            # this is persistent with dmd, dsss, xfbuild, ...
            is_inc = os.path.splitext(file)[1] == '.di'
            is_ign = module_is_ignored(module)
            if not is_ign and not is_inc:
                flist.append(file)
                stat_files = stat_files + 1
            else:
                stat_ifiles = stat_ifiles + 1
    if False:
        print("%s files to compile, %s files import only, %s import lines."
            % (stat_files, stat_ifiles, stat_deps))
    return flist

def build():
    files = read_and_parse_depfile()
    # don't do anything if the exe seems to be up-to-date
    # this is all one can do to reduce "build times" without resorting to
    #   incremental compilation
    if files:
        def ftime(path):
            try:
                return os.stat(path).st_mtime
            except OSError:
                return -1
        deptime = ftime(DEP_FILE)
        # first see if the corresponding source files are not newer than before
        uptodate = True
        for f in files:
            if ftime(f) > deptime:
                uptodate = False
                break
        if ftime(EXE_FILE) < deptime: #previous unsuccessful build attempt
            uptodate = False
        if deptime > 0 and uptodate:
            print("Everything seems to be up-to-date, not compiling.")
            return

    remove_recursive(OBJ_DIR, False)

    createdepfile()

    files = read_and_parse_depfile()
    if not files:
        print("dmd failed to create depfile?")
        sys.exit(1)

    print("Compiling...")
    dmdargs = ["-oq", "-od" + OBJ_DIR, "-c"]
    dmdargs.extend(files)
    calldmd("compile", dmdargs)

    # for some unknown reasons, it's better to link separately
    # calling it with both -oq -od and -of gives wtfish behaviour
    print("Linking...")
    ofiles = []
    for dirpath, dirnames, filenames in os.walk(OBJ_DIR):
        for file in filenames:
            ofiles.append(os.path.join(dirpath, file))
    dmdargs = ["-of" + EXE_FILE]
    dmdargs.extend(ofiles)
    calldmd("link", dmdargs)

build()
