local djot = require("djot")

local handle = io.open(("./%s.dj"):format(arg[1]), "r") or {}
local input = handle:read("*a")
handle:close()
local ast = djot.parse(input, false, vim.print)
local rendered = djot.render_html(ast)
vim.print(rendered)
handle = io.open(("./%s.html"):format(arg[1]), "w") or {}
handle:write(rendered)
handle:close()
