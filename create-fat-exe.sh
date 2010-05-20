#!/bin/bash

# this creates bin/lumbricus-full from bin/lumbricus by appending the tar-ed
#   contents of the data directory, share/lumbricus/
# the executable is then supposed to be able to be started without additional
#   files (except DLLs); init.d is supposed to read the "attached" tar
# (although one _could_ embed DLLs here, because most of them are dynamically
#   loaded by derelict. but you had to unpack them to the filesystem, and it's
#   a stupid idea anyway)

set -e

# create tar with data files in it

find share/lumbricus -not -path '*/.*' -and -not -type d | xargs tar -c -f Lumbricus.tar --transform='s/^share\/lumbricus\///'

# attach it to the exe

TARGET=bin/lumbricus-full

cp -f bin/lumbricus $TARGET
cat Lumbricus.tar >> $TARGET

# file header (or rather footer) to be read by lumbricus
# too lazy to write a D program
# consists of binary encoded file size in 32 bits, followed by the string 'LUMB'

echo "dd " `stat --printf='%s' Lumbricus.tar` " , 'LUMB'" > header.tmp
nasm -o bin-header.tmp -f bin header.tmp

cat bin-header.tmp >> $TARGET

rm -f bin-header.tmp header.tmp
