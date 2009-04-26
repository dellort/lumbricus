:: This script packs all the files needed to play into an archive file
:: Requires a WinRAR installation that is associated with .rar files

@echo off & setlocal EnableDelayedExpansion

:: Change this to produce a ZIP archive
SET DEST=Lumbricus.rar
rem SET DEST=Lumbricus.zip

:: From 0 (store) to 5 (best compression)
SET COMPLEVEL=5

del %DEST%

:: Determine path to WinRAR installation
for /F "usebackq tokens=1 skip=4 delims=" %%i in (`reg query HKCR\WinRAR\shell\open\command /ve`) do set WRTMP=%%i
set WRTMP2=!WRTMP:"=|!
for /F "tokens=2 delims=|" %%i in ("!WRTMP2!") do set WRAR=%%i

:: Pack bin/ and share/lumbricus/, no .svn stuff
"!WRAR!" a -s -mspng -m%COMPLEVEL% -r -x*\.svn -x*\.svn\* %DEST% bin\*.dll bin\lumbricus.exe share\lumbricus\*

endlocal