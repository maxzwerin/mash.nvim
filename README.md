shoutout flash.nvim <3

in init.lua file:

```lua
vim.pack.add({ src = https://github.com/maxzwerin/mash.nvim })

local mash = require("mash")
mash.setup()
map({ "n" }, "<leader>/", mash.jump)
```

enjoy mashing!
