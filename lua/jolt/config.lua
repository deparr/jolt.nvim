local M = {}

---@type boolean true if neovim was started in headless mode
M.headless = #vim.api.nvim_list_uis() == 0

---@class jolt.Config
M.defaults = {
  out_dir = vim.fs.joinpath(vim.fn.getcwd(), "build/"),
  content_dir = vim.fs.joinpath(vim.fn.getcwd(), "content/"),
  --- maximum depth when scanning content_dir
  depth = 10,
  template_main_slot = "::slot::",
  default_title = vim.fs.basename(vim.fn.getcwd()),
  default_template = "base",
  ---@type { light: string?, dark: string?, restore: string? } | fun(s: string, g: table<string>): table
  code_style = {
    light = "default",
    dark = "default",
    restore = "default",
  },
}

---@type jolt.Config
M.options = nil

---@param opts? jolt.Config
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

---@param opts? jolt.Config
function M.extend(opts)
  return opts and vim.tbl_deep_extend("force", M.options, opts) or M.options
end

setmetatable(M, {
  __index = function(_, k)
    if k == "options" then
      return M.defaults
    end
  end,
})

return M
