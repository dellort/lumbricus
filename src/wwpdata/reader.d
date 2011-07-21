module wwpdata.reader;

import utils.stream;

alias void function(Stream st, string outputDir, string fnBase) WWPReader;

WWPReader[string] registeredReaders;
