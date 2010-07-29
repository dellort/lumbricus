:: Update all project files
:: needs projgen.exe and DMD in path
:: xxx Windows script; but then, the projects are only used on Windows

@echo off

set DMD=dmd -debug -c -o- -deps=depfile -I..\src ..\src\

%DMD%lumbricus.d
projgen Lumbricus.cbp -I..\share\lumbricus\data\*.lua < depfile
projgen Lumbricus.visualdproj < depfile
%DMD%lumbricus_server.d
projgen server.cbp < depfile
%DMD%extractdata.d
projgen extractdata.cbp < depfile
%DMD%unworms.d
projgen unworms.cbp < depfile
%DMD%luatest.d
projgen luatest.cbp < depfile
del depfile
