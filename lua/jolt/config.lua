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
  opts = opts or {}
  if opts.out_dir then
    opts.out_dir = vim.fn.isabsolutepath(opts.out_dir) and opts.out_dir
      or vim.fs.joinpath(vim.fn.getcwd(), opts.out_dir)
  end
  if opts.content_dir then
    opts.content_dir = vim.fn.isabsolutepath(opts.content_dir) and opts.content_dir
      or vim.fs.joinpath(vim.fn.getcwd(), opts.content_dir)
  end
  M.options = vim.tbl_deep_extend("force", M.defaults, opts)
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
