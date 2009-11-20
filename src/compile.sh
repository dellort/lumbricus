#!/bin/sh

# xfbuild is an alternative to dsss & rebuild (which suck very hard)
# http://wiki.team0xf.com/index.php?n=Tools.XfBuild
# note: as of dmd 1.046, you still need to patch the dmd source code, because the Walter (or was it h3) messed up the -deps patch (will most likely be fixed on 1.047)

# will kill this dumb and retarded script with all my might as soon as there's a dsss like frontend for xfbuild

# replace with ldmd if you want to use ldc
COMPILER=dmd
#COMPILER=ldmd

BINDIR=../bin/

# for simple dry run mode
CMD=
#CMD=echo

function invoke_compiler
{
    DMD_IS_BROKEN=+full
    # seriously
    #FUCK_D="-L-z -Lmuldefs"
    # just joking, D is nice (as long as it works)
    FUCK_D=""
    # libreadline and MDReadline is just for mdcl
    $CMD xfbuild +c$COMPILER $1.d +noop +xtango -unittest -debug -g -L-lz -L-ldl +o$BINDIR$1 +D.deps_$1 +O.objs_$1 $DMD_IS_BROKEN $FUCK_D -version=MDReadline -L-lreadline
}

TARGETS="lumbricus extractdata test mdcl unworms animutil sdlimginfo"
DEF_TARGET=lumbricus


if [ $1 ]; then
    if [ $1 = "-n" ]; then
        CMD=echo
        echo "dry run mode (output commands only)"
        shift
    fi
fi

if [ $1 ]; then
    for x in $TARGETS ; do
        if [ $x = $1 ]; then
            TARGET=$1
            break
        fi
    done
fi

if [ $TARGET ]; then
    invoke_compiler $TARGET
    exit
fi

case $1 in
    all)
        for x in $TARGETS ; do
            echo "Build:" $x
            invoke_compiler $x
        done
        ;;
    clean)
        #$CMD rm -rf .objs .deps
        for x in $TARGETS ; do
            $CMD rm -f .deps_$x
            $CMD rm -rf .objs_$x
            $CMD rm -f $BINDIR$x
        done
        ;;
    # in memorial of old non-GNU versions of make
    love)
        echo "I don't know how to make love."
        ;;
    "")
        invoke_compiler $DEF_TARGET
        ;;
    *)
        echo "Targets:"
        echo "  all: make all"
        echo "  clean: remove stuff for all targets"
        echo "further targets:" $TARGETS
        echo "no target: compile '$DEF_TARGET'"
        ;;
esac
