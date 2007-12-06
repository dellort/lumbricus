module wwpdata.reader;

import std.stream;

alias void function(Stream st, char[] outputDir, char[] fnBase) WWPReader;

WWPReader[char[]] registeredReaders;
