@echo off
setlocal

set "GODOT_EXE=C:\Godot_v4.8\Godot_v4.8-dev4_win64_console.exe"
if exist "%GODOT_EXE%" goto run_godot

set "GODOT_EXE=D:\Program Files\Godot\Godot_v4.8\Godot_v4.8-dev4_mono_win64_console.exe"
if exist "%GODOT_EXE%" goto run_godot

where godot >nul 2>nul
if not errorlevel 1 (
	set "GODOT_EXE=godot"
	goto run_godot
)

echo Godot 4.8 dev4 not found in the known paths or PATH. 1>&2
exit /b 1

:run_godot
"%GODOT_EXE%" %*
exit /b %ERRORLEVEL%
