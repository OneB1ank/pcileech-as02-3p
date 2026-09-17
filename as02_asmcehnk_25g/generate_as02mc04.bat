@echo off
setlocal
pushd "%~dp0"
vivado -source vivado_generate_project.tcl -notrace -nolog -nojournal
popd

