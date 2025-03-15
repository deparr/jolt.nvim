local M = {}

---@class static.Config
M.defaults = {
  out_dir = "build/",
  pages_dir = "pages/",
  template_dir = "templates/",
  template_main_slot = "::slot::",
  static_dir = "static/",
  default_title = "Test-Site",
  templates = {},
  root_pages = {
    "/index",
    "/404",
  },
  light_theme = "default",
  dark_theme = "default",
}

M.options = nil

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

function M.extend(opts)
  return opts and vim.tbl_deep_extend("force", M.options, opts) or M.options
end

setmetatable(M, {
  __index = function(_, k)
    if k == "options" then
      return M.defaults
    end
  end
})

return M
