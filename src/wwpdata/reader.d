module wwpdata.reader;

import utils.stream;

alias void function(Stream st, char[] outputDir, char[] fnBase) WWPReader;

WWPReader[char[]] registeredReaders;
