@echo off
rem Runs the app: the local build if there is one, otherwise from source.
chcp 65001 >nul
if exist "%~dp0build\app\死ねアップル\死ねアップル.exe" (
  start "" "%~dp0build\app\死ねアップル\死ねアップル.exe"
) else (
  start "" "%~dp0.venv\Scripts\pythonw.exe" -m gamdl_gui
)
