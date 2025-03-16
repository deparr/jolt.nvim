local jolt = require("jolt")
local config = require("jolt.config")

vim.api.nvim_create_user_command("JoltBuild", function(args)
  local a = vim.split(args.args, "%s+")
  if a[1] == "static" then
    jolt.copy_static()
  else
    jolt.build()
  end
end, { bar = true, nargs = "*" })

-- todo put this into the 'server'
vim.api.nvim_create_user_command("JoltWatch", function(args)
  if vim.g.jolt_watching then
    jolt.log("already watching!")
    return
  end
  vim.g.jolt_watching = true
  if config.options == nil then
    config.setup()
  end

  local opts = config.extend()
  -- register autocmds ??
  -- do initial build
  -- start server
  -- need a way to cancel

  local augroup = vim.api.nvim_create_augroup("JoltWatchGroup", {})
  -- todo a little jank
  vim.api.nvim_create_user_command("JoltWatchStop", function(args)
    vim.api.nvim_del_augroup_by_id(augroup)
    vim.g.jolt_watching = false
    vim.api.nvim_del_user_command("JoltWatchStop")
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
      jolt.log(event.file .. " changed!")
    end,
    group = augroup,
    desc = "JoltWatchBufWritePost",
  })

  jolt.watch()
end, {})
