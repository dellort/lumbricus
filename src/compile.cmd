:: %1 = Target
:: %2 = Extra include path (%INCLUDE_PREFIX% from dsss.conf) or "clean"
:: %3 = Extra lib path (%LIB_PREFIX% from dsss.conf)

@echo off
set DEBUG=-g -unittest -debug
::@set DEBUG=-release -O
set BINDIR=..\bin\
set LIBS=DerelictSDL.lib DerelictSDLImage.lib DerelictGL.lib DerelictGLU.lib zlib.lib DerelictUtil.lib DerelictFT.lib DerelictAL.lib
set FLAGS=-I%2 -L+%3\
set TMPDIR=%TEMP%\build\.objs_%1

::set DMD_IS_BROKEN=+full

::set FLAGS=-IC:\Programme\D\dsss\include\d -L+C:\Programme\D\dsss\lib\

if "%2"=="clean" goto clean

:build
mkdir %TMPDIR% 2>NUL
xfbuild %1.d +q +xtango +o%BINDIR% +O%TMPDIR% %DMD_IS_BROKEN% %DEBUG% %FLAGS% %LIBS%
goto end

:clean
del /S /Q %TMPDIR% >NUL 2>NUL
goto end

:end
