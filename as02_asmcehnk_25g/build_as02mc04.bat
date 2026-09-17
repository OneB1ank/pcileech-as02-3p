@echo off
setlocal
pushd "%~dp0"
vivado -source vivado_build.tcl -notrace -nolog -nojournal
popd

