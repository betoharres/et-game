@echo off
setlocal

set "GODOT_EXE=%~dp0..\..\Godot_v4.7.1-stable_mono_win64_console.exe"
if exist "%GODOT_EXE%" goto run_godot

set "GODOT_EXE=C:\Godot_v4.7.1\Godot_v4.7.1-stable_win64_console.exe"
if exist "%GODOT_EXE%" goto run_godot

set "GODOT_EXE=D:\Program Files\Godot\Godot_v4.8\Godot_v4.8-dev3_mono_win64_console.exe"
if exist "%GODOT_EXE%" goto run_godot

where godot >nul 2>nul
if not errorlevel 1 (
	set "GODOT_EXE=godot"
	goto run_godot
)

echo Godot not found in the known 4.7/4.8 paths or PATH. 1>&2
exit /b 1

:run_godot
"%GODOT_EXE%" %*
exit /b %ERRORLEVEL%
