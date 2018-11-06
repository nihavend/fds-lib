@echo off

set COMPILER_PATH=D:\dev\royale-emulation-works\apache-royale-0.9.4-bin-js-swf\royale-asjs\js\bin

set SRCPATH=D:\dev\royale-emulation-works\github\fds-lib\

set GITREPO=D:\dev\royale-emulation-works\github\royale-asjs\frameworks\projects
set MX_SWC=%GITREPO%\MXRoyale\target\MXRoyale-0.9.5-SNAPSHOT-swf.swc
set MX_JS=%GITREPO%\MXRoyale\target\MXRoyale-0.9.5-SNAPSHOT-js.swc
set include_sources=%SRCPATH%\src\*

@echo on

%COMPILER_PATH%\compc -external-library-path+=%MX_SWC% -js-external-library-path+=%MX_JS% -compiler.source-path+=%SRCPATH%\src -include-sources %include_sources% -o fiber-lib.swc


