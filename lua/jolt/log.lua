local config = require("jolt.config")

local M = {}

local default_prefix = "jolt: "

---@param scope? string
---@return fun(msg: string, lvl?: integer) logger
--- Creates a logger that is prefixed with `scope` with format: `"jolt($scope): "`.
--- Omitting scope results in a `"jolt: "` prefix
function M.scoped(scope)
  local prefix = (scope and #scope > 0) and ("jolt(%s): "):format(scope) or default_prefix
  return config.headless and function(msg)
    -- vim.print(prefix .. msg)
    io.write(prefix, msg, "\n")
  end or function(msg, l)
    vim.notify(prefix .. msg, l or vim.log.levels.INFO)
  end

end

--- The default, top-level logger.
--- With prefix: `"jolt: "`
M.default = M.scoped()

return M
