@echo off
::OPTIONS
::diskpart script file name
set TEMPFILE=tmp.txt
::Target drive letter
set TARGET=T

::COMMANDS
::create diskpart script
echo select volume=%CD:~0,1% > %TEMPFILE%
echo assign letter=%TARGET% >> %TEMPFILE%
attrib +h %TEMPFILE%
::run diskpart
diskpart /s %CD:~0,2%\%TEMPFILE%
::script terminates here becuase drive letter change interupts it
