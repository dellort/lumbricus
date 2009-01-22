License
-------------

This directory contains code from Phobos. Various additions and changes might
have been made. License see the original files in the src/phobos/ directory of
this file:

http://ftp.digitalmars.com/dmd.1.037.zip

Note: Changes were not marked! Just use diff or so.

General information about this code
-------------

This is some Phobos modules converted to Tango. I made this because Tangobos
doesn't seem to work too well with LDC. (At least it was like this when I wrote
this. Maybe it was ported to LDC later.) No Tangobos code was used.

This code should work both with Phobos and Tango. It's a bit pointless with
Phobos, though (code is duplicated, executable will only be larger).

"version(Tango)" is used to tell whether it works under Phobos or Tango.

Notable changes:
- std.format: derive FormatError from Exception, not Error
- std.file: rewritten to use Phobos or Tango, some functions/fields removed
- std.utf: added encode_inplace()
- std.stdio: sorry no FILE anymore (all removed)
  readln() + StdioException removed
- std.math: in the tango version, simply import some tango modules
- std.conv: the two exceptions are now derived from Exception and ConvErrorBase,
  not Error
- std.string: changes to isNumeric() because LDC barfed at va_arg
- std.format: similar to std.string
