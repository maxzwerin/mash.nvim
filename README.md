shoutout flash.nvim <3

in init.lua file:

```lua
local mash = require("mash")
mash.setup()
map({ "n" }, "<leader>/", mash.jump)
```

enjoy mashing!
