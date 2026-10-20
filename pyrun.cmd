@echo off
rem  Run a Python script through the wrapper so Si can see the errors.
rem  Usage:  pyrun.cmd your_script.py [args...]
node "%~dp0core\pyrun.js" %*
