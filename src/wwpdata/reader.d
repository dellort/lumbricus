module wwpdata.reader;

import stdx.stream;

alias void function(Stream st, char[] outputDir, char[] fnBase) WWPReader;

WWPReader[char[]] registeredReaders;
