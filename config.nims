# begin Nimble config (version 2)
--noNimblePath
when withDir(thisDir(), system.fileExists("nimble.paths")):
  include "nimble.paths"
# end Nimble config

switch("path", thisDir() & "/src")
switch("path", thisDir() & "/src/nide")

# Add Nim root to path so compiler/* modules are importable
import std/os
let nimExe = findExe("nim")
if nimExe.len > 0:
  switch("path", parentDir(parentDir(nimExe)))

--mm:orc
--debugger:native
--app:gui
--stackTrace:on
--lineTrace:on
--panics:on
--d:ssl
