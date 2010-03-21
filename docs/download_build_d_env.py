#!/usr/bin/env python
# written in python 2.5; other versions may or may not work

# this script downloads and compiles a basic D environment
# it is rather violent and may fail randomly

# required programs: wget, unzip, patch, g++, svn
# + some standard shell utilities

# a shell script would probably be better for this task, but I dislike *sh

# WARNING: wipes out DEST_DIR (see end of this file)

import os
import os.path
import sys
from subprocess import Popen

DEST_DIR = "d_env"
DOWNLOAD_DIR = "downloads"
HERE = os.path.dirname(os.path.abspath(sys.argv[0]))

mp = os.path.join

# all these use fixed versions because the D world loves random regressions
def dostuff():
    d_include_dir = mp(DEST_DIR, "include", "d")

    # get, patch, compile, and install dmd
    dmd_zip = mp(DOWNLOAD_DIR, "dmd.zip")
    http_get("http://ftp.digitalmars.com/dmd.1.057.zip", dmd_zip)
    # destdir will be removed first
    dmd = mp(DOWNLOAD_DIR, "dmd")
    unzip(dmd_zip, dmd)
    dmd_src_dir = mp(dmd, "dmd", "src", "dmd")
    patch(dmd_src_dir, mp(HERE, "dmd-1057-lumbricus-linux.patch"))
    rootprefix = mp('%@P%', "..")
    compile_install_dmd(dmd_src_dir, mp(DEST_DIR, "bin"),
        [mp(rootprefix, "include", "d"),
         mp(rootprefix, "include", "d", "tango"),
         mp(rootprefix, "include", "d", "tango", "core", "vendor")],
        [mp(rootprefix, "lib")])

    # get, compile and install tango
    tangodir = mp(DOWNLOAD_DIR, "tango")
    svn_get("http://svn.dsource.org/projects/tango/trunk", "5396", tangodir)
    compile_install_tango(tangodir, d_include_dir, mp(DEST_DIR, "lib"))

    # derelict, don't compile them as lib as that's easier
    derdir = mp(DOWNLOAD_DIR, "derelict")
    svn_get("http://svn.dsource.org/projects/derelict/trunk", "441", derdir)
    # actually needed (and going to be installed) derelict wrappers
    subdirs = ["DerelictUtil", "DerelictFT", "DerelictGL", "DerelictGLU",
               "DerelictSDL", "DerelictSDLImage", "DerelictAL"]
    # derelict svn is stupidly irregular for some reason
    for i in subdirs:
        install_headers(mp(derdir, i), d_include_dir, False)


def fail(msg):
    print("script failed: " + msg)
    sys.exit(1)

# make sure the directory exists
def ensuredir(d):
    try:
        os.makedirs(d)
    except OSError:
        pass

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

env = os.environ

def binexec(what, args, **opts):
    cwd = None
    if "cwd" in opts:
        cwd = opts["cwd"]
    p = Popen(args=args,close_fds=True,cwd=cwd)
    p.wait()
    if p.returncode != 0:
        fail(what)

def copyfile(a_from, to):
    binexec("copy", ["cp", a_from, to])

def http_get(url, destfile):
    binexec("http download", ["wget", "-c", url, "-O", destfile])

def unzip(zipfile, dest):
    remove_recursive(dest, True)
    binexec("unzip", ["unzip", zipfile, "-d", dest])

def patch(destdir, patchfile):
    patchfile = os.path.abspath(patchfile)
    binexec("patch", ["patch", "-p1", "-i", patchfile], cwd=destdir)

def svn_get(url, revision, destdir):
    if os.path.exists(destdir):
        print("skip svn export for '%s'" % destdir)
        return
    binexec("svn", ["svn", "export", "-r" + revision, url, destdir])

def compile_install_dmd(dmddir, destdir, includes, libs):
    dmdexe = mp(dmddir, "dmd")
    binexec("compile dmd", ["make", "-f", "linux.mak"], cwd=dmddir)
    ensuredir(destdir)
    copyfile(dmdexe, mp(destdir, ""))
    conf = open(mp(destdir, "dmd.conf"), "w")
    conf.write("[Environment]\n")
    conf.write("DFLAGS=")
    for i in includes:
        conf.write(" -I")
        conf.write(i)
    for l in libs:
        conf.write(" -L-L")
        conf.write(l)
    conf.write(" -version=Tango -defaultlib=tango -debuglib=tango")
    conf.write("\n")
    conf.close()
    # add dmd to the environment variables, so that the tango build script later
    #   will use it
    env["PATH"] = os.path.abspath(destdir) + ":" + env["PATH"]

# copy and rename d/di files
def install_headers(from_dir, to_dir, di=True):
    ensuredir(to_dir)
    for file in os.listdir(from_dir):
        from_file = mp(from_dir, file)
        to_file = mp(to_dir, file)
        if os.path.isdir(from_file) and not file.startswith("."):
            install_headers(from_file, to_file, di)
        elif os.path.isfile(from_file):
            name, ext = os.path.splitext(file)
            if ext in [".d", ".di"]:
                if di:
                    file = name + ".di"
                copyfile(from_file, mp(to_dir, file))

def compile_install_tango(tangodir, include, lib):
    bdir = mp(tangodir, "build-temp")
    ensuredir(bdir)
    remove_recursive(bdir, False)
    arch = "linux32"
    comp = "dmd"
    bobexe = mp("build", "bin", arch, "bob")
    binexec("compile tango", [mp("..", bobexe), "-vu", "-r="+comp,
        "-c="+comp, "-l=tango", ".."], cwd=bdir)
    ensuredir(lib)
    copyfile(mp(bdir, "tango.a"), mp(lib, "libtango.a"))
    ensuredir(include)
    copyfile(mp(tangodir, "object.di"), mp(include, ""))
    install_headers(mp(tangodir, "tango"), mp(include, "tango"))

# huhuhu

ensuredir(DOWNLOAD_DIR)
ensuredir(DEST_DIR)
remove_recursive(DEST_DIR, False)

dostuff()
