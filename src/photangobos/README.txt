License
-------------

This directory contains code from Phobos. Various additions and changes might
have been made. License see the original files in the src/phobos/ directory of
this file:

http://ftp.digitalmars.com/dmd.1.037.zip

Note: Changes were not marked! Just use diff or so.

General information about this code
-------------

We used this to simplify porting our code from Phobos -> Tango.
- stdx.stream: wraps Tango I/O, actual porting doesn't seem it worth
- stdx.string: too trivial and too heavily used to port (also Tango API sucks)
- stdx.utf: sorry, Tango makes it too complicated
- stdx.demangle: no Tango equivalent (yet?)
