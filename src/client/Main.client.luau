-- Named Main (not init) so it syncs as an ordinary LocalScript child of
-- StarterPlayerScripts, sibling to the UI folder -- avoids any ambiguity
-- around Rojo's init-file convention when $path targets a fixed-class service.

local MainUI = require(script.Parent.UI:WaitForChild("MainUI"))
MainUI.Init()
