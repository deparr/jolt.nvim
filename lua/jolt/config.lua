local M = {}

M.headless = #vim.api.nvim_list_uis() == 0

---@class jolt.Config
M.defaults = {
  out_dir = "build/",
  -- pages_dir = "pages/",
  -- template_dir = "templates/",
  -- static_dir = "static/",
  content_dir = "content/",
  depth = 10,
  template_main_slot = "::slot::",
  default_title = vim.fn.fnamemodify(vim.fn.getcwd(), ":t"),
  default_template = "base",
  -- root_pages = {
  --   "/index",
  --   "/404",
  -- },
  ---@type { light: string?, dark: string?, restore: string? } | fun(s: string): table
  code_style = {
    light = "default",
    dark = "default",
    restore = "default",
  },
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
