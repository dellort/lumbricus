#!/usr/bin/env python

# this is just a quick&dirty compilation script
# if you need something more sophisticated, consider xfbuild:
#   http://wiki.team0xf.com/index.php?n=Tools.XfBuild

# this dmd patch is needed (to add -oq):
# http://d.puremagic.com/issues/show_bug.cgi?id=3541
#   but also see USE_OQ in this file
# fixing this bug would be fine too:
# http://d.puremagic.com/issues/show_bug.cgi?id=4095

EXE_DIR = "../bin/"

# xxx should include username
# also note that clean removes the full directory
BUILD_DIR = "/tmp/minibuild/"

# name of the DMD binary
DMD = "dmd"

# USE_OQ = False can be used to compile without the -oq patch, but it's a hack
#   and doesn't work on Windows (don't know if it could be made working)
# for one, it will execute dmd with '/' as working directory
USE_OQ = True

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
def calldmd(what, pargs, **more):
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
    p = Popen(args=args,close_fds=True,**more)
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
    calldmd("dep", [rootfile, "-o-", "-deps=" + DEP_FILE])

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
    if USE_OQ:
        dmdargs = ["-oq", "-od" + OBJ_DIR, "-c"]
        dmdargs.extend(files)
        calldmd("compile", dmdargs)
    else:
        # use some kludge to make it work with -oq -od
        # there are two issues:
        # 1. dmd will write object files to the same dir as the source file in
        #    some circumstances: using absolute paths as filename (bug 4095),
        #    or when using relative filenames with '..' in it (????)
        # 2. without -oq, dmd will write object files always to the output dir,
        #    but modules with same name / different package will make dmd use
        #    the same filename => dmd overwrites its own crap
        # solution: use relative filenames without ever using '..'; to achieve
        #    this, just change dmd's working dir to '/', and give it "relative"
        #    filenames which really are absolute paths with first '/' stripped
        # this will partially reproduce the filesystem layout in OBJ_DIR
        # Warning: only works under Unix
        afiles = [os.path.abspath(f) for f in files]
        # strip initial '/' (linux specific)
        # this is neccessary to make it a relative path; if dmd gets an absolute
        #   path, it will misbehave as noted above
        afiles = [f[1:] for f in afiles]
        dmdargs = ["-op", "-od" + OBJ_DIR, "-c"]
        dmdargs.extend(afiles)
        calldmd("compile", dmdargs, cwd="/")

    # for some unknown reasons, it's better to link separately
    # calling it with both -oq -od and -of gives wtfish behaviour (it probably
    # tries to write everything to a single object file, and it's damn slow)
    print("Linking...")
    ofiles = []
    for dirpath, dirnames, filenames in os.walk(OBJ_DIR):
        for file in filenames:
            ofiles.append(os.path.join(dirpath, file))
    dmdargs = ["-of" + EXE_FILE]
    dmdargs.extend(ofiles)
    calldmd("link", dmdargs)

build()
