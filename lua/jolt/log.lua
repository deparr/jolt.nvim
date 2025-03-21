local config = require("jolt.config")

local M = {}

local default_prefix = "jolt: "

function M.scoped(scope)
  local prefix = (scope and #scope > 0) and ("jolt(%s): "):format(scope) or default_prefix
  return config.headless and function(msg)
    vim.print(prefix .. msg)
  end or function(msg, l)
    vim.notify(prefix .. msg, l or vim.log.levels.INFO)
  end
end

M.default = M.scoped()

return M
