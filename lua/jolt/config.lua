local M = {}

---@type boolean true if neovim was started in headless mode
M.headless = #vim.api.nvim_list_uis() == 0

---@class jolt.Config
M.defaults = {
  out_dir = vim.fs.joinpath(vim.fn.getcwd(), "build"),
  content_dir = vim.fs.joinpath(vim.fn.getcwd(), "content"),
  --- maximum depth when scanning content_dir
  depth = 10,
  default_title = vim.fs.basename(vim.fn.getcwd()),
  default_template = "base",
  ---@type { light: string?, dark: string?, restore: string? } | fun(s: string, g: table<string>): table
  code_style = {
    light = "default",
    dark = "default",
    restore = "default",
  },
  blog = {
    --- enabled/disable blog generation
    enable = false,
    --- documents with this tag will be added to the post list
    tag = "blog-post",
    --- *djot* template string that has a `::posts::` template specifier
    blog_page_template = "",
    --- *djot* template string subbed against each post's metadata
    post_item_template = "",
    --- the intermediate segments between `/` and `<post-url>`.
    --- defaults to `"blog"`, which will output final html at `/blog/index.html`
    ---
    --- **NOTE: currently does not move tagged posts under this segment.**
    --- **blog posts should include this as part of their own path**
    output_url = "blog",
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
