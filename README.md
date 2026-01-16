inspired by: https://github.com/folke/flash.nvim

to install mash in your init.lua file using nvim nightly:
```lua
vim.pack.add({ src = "https://github.com/maxzwerin/mash.nvim" })

local mash = require("mash")
mash.setup()
map({ "n" }, "<leader>/", mash.jump)
```

enjoy mashing!
