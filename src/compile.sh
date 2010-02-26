#!/bin/sh

# xfbuild is an alternative to dsss & rebuild (which suck very hard)
# http://wiki.team0xf.com/index.php?n=Tools.XfBuild

# will kill this dumb and retarded script with all my might as soon as there's a dsss like frontend for xfbuild

# the +q option for xfbuild needs this dmd patch:
# http://d.puremagic.com/issues/show_bug.cgi?id=3541

# replace with ldmd if you want to use ldc
COMPILER=dmd
#COMPILER=ldmd

BINDIR=../bin/
TMPDIR=/tmp/build/

if [ ! -d $TMPDIR ]; then
    mkdir $TMPDIR
fi

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
    $CMD xfbuild +c$COMPILER $1.d +noop +xtango -unittest -debug -g -L-lz -L-ldl +o$BINDIR$1 +D$TMPDIR.deps_$1 +O$TMPDIR.objs_$1 $DMD_IS_BROKEN $FUCK_D +q
}

TARGETS="lumbricus extractdata test unworms animutil sdlimginfo luatest"
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
            $CMD rm -f $TMPDIR.deps_$x
            $CMD rm -rf $TMPDIR.objs_$x
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
