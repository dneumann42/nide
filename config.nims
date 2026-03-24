# begin Nimble config (version 2)
--noNimblePath
when withDir(thisDir(), system.fileExists("nimble.paths")):
  include "nimble.paths"
# end Nimble config

switch("path", thisDir() & "/src")

--mm:orc
--debugger:native
--app:gui
--stackTrace:on
--lineTrace:on
--panics:on
--d:ssl
