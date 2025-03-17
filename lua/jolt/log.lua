local config = require("jolt.config")

local log_prefix = "jolt: "

return config.headless and function(msg)
  vim.print(log_prefix .. msg)
end or function(msg, l)
  vim.notify(log_prefix .. msg, l or vim.log.levels.INFO)
end
