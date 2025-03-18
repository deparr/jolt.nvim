local config = require("jolt.config")
local log = require("jolt.log")

local M = {}

M.proc = nil

M.chan = nil

local kill_sig = vim.uv.os_uname().sysname:match("[wWindows]") and 0 or -15

local buf = -1
local win = -1

function M.start(opts)
  opts = config.extend(opts)
  local serve_cmd = { "python3", "-m", "http.server", "-d", "build/" }
  buf = vim.api.nvim_create_buf(false, false)
  M.chan = vim.api.nvim_open_term(buf, {})
  win = vim.api.nvim_open_win(buf, false, { split = "right", width = 60 })
  M.proc = vim.system(serve_cmd, {
    -- stdout = function(err, data)
    --   if not err then
    --     vim.schedule(function() vim.api.nvim_chan_send(M.chan, data) end)
    --   else
    --     log(err)
    --   end
    -- end,
    stderr = function(err, data)
      if not err or not M.proc:is_closing() then
        vim.schedule(function()
          vim.api.nvim_chan_send(M.chan, data)
        end)
      else
        log(err)
      end
    end,
    text = true,
  })

  vim.notify("serve: start: pid " .. M.proc.pid)
end

function M.stop()
  if M.proc then
    M.proc:kill(kill_sig)

    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end

    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end

    M.proc = nil
    log("serve: stopping")
  end
end

return M
