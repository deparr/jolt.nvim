local static = require("static")
local config = require("static.config")

vim.api.nvim_create_user_command("StaticBuild", function(args)
  local a = vim.split(args.args, "%s+")
  if a[1] == "static" then
    static.copy_static()
  else
    static.build()
  end
end, { bar = true, nargs = "*" })

-- todo put this into the 'server'
vim.api.nvim_create_user_command("StaticWatch", function(args)
  if vim.g.static_watching then
    vim.notify("already watching!")
    return
  end
  vim.g.static_watching = true
  if config.options == nil then
    config.setup()
  end

  local opts = config.extend()
  -- register autocmds ??
  -- do initial build
  -- start server
  -- need a way to cancel

  local augroup = vim.api.nvim_create_augroup("StaticWatchGroup", {})
  -- todo a little jank
  vim.api.nvim_create_user_command("StaticWatchStop", function(args)
    vim.api.nvim_del_augroup_by_id(augroup)
    vim.g.static_watching = false
    vim.api.nvim_del_user_command("StaticWatchStop")
    -- send kill message
  end, {})

  local cwd = vim.fn.getcwd()
  local watch_dirs = {
    vim.fs.joinpath(cwd, opts.pages_dir, "*.dj"),
    vim.fs.joinpath(cwd, opts.template_dir, "*.html"),
    vim.fs.joinpath(cwd, opts.static_dir, "*"),
  }
  vim.api.nvim_create_autocmd({ "BufWritePost" }, {
    pattern = watch_dirs,
    callback = function(event)
      -- this should send a message to the 'server'
      -- should be relatively short
      vim.notify(event.file .. " changed!")
    end,
    group = augroup,
    desc = "StaticWatchBufWritePost",
  })

  static.watch()
end, {})
