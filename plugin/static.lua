vim.api.nvim_create_user_command("StaticBuild", function(args)
  require("static").build()
end, { bar = true })
