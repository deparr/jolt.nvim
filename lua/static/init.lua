local djot = require("djot")

local M = {}

local htmlwinnr = nil
local htmlbufnr = -1

local function dedup_list(t)
  local dedup = {}
  return vim
    .iter(t)
    :filter(function(v)
      if dedup[v] then
        return false
      end
      dedup[v] = true
      return true
    end)
    :totable()
end

local function highlight_code(code, lang)
  local tohtml = require("tohtml").tohtml
  if htmlwinnr == nil or not vim.api.nvim_win_is_valid(htmlwinnr) then
    htmlbufnr = vim.api.nvim_create_buf(true, true)
    htmlwinnr = vim.api.nvim_open_win(htmlbufnr, false, { split = "right" })
  end

  vim.api.nvim_buf_set_lines(
    htmlbufnr,
    0,
    -1,
    false,
    type(code) == "string" and vim.split(code, "\n") or code
  )
  vim.bo[htmlbufnr].filetype = lang
  local html = tohtml(htmlwinnr, {})

  local style_start = html[7]
  assert(vim.startswith(style_start, "<style>"), "bad style tag pos")
  local styles = {}

  for i = 8, #html do
    local s = html[i]
    if s == "</style>" then
      break
    end
    local match = s:find("font%-family") or s:find("^%.%-spell") or s:find("^body")
    if match == nil then
      table.insert(styles, s)
    end
  end

  local pre_start = 7 + #styles + 1
  while pre_start < #html do
    local s = html[pre_start]
    if s == "<pre>" then
      break
    end
    pre_start = pre_start + 1
  end

  local blocks = {}
  for i = pre_start + 1, #html do
    local s = html[i]
    if s == "</pre>" then
      break
    end

    table.insert(blocks, s)
  end

  if blocks[#blocks] == "" then
    blocks[#blocks] = nil
  end

  table.insert(blocks, 1, "<code>")
  table.insert(blocks, 1, "<pre>")
  table.insert(blocks, 1, '<figure class="code-block">')

  table.insert(blocks, "</code>")
  table.insert(blocks, "</pre>")
  table.insert(blocks, "</figure>")

  local rendered = vim.trim(vim
    .iter(blocks)
    :map(function(v)
      if v:match("^%<%/?code%>") or v:match("^%<%/?pre%>") or v:match("^%<%/?figure.*%>") then
        return v
      end

      return '<span class="line">' .. v .. "</span>"
    end)
    :join("\n"))

  styles = dedup_list(styles)

  return rendered, styles
end

---@class static.Config
local default_opts = {
  in_dir = ".",
  out_dir = "build/",
  pages_dir = "pages/",
  template_dir = "templates/",
  static_dir = "static/",
  ---@type table<string, string>
  templates = {},
}

function M.clean(opts)
  vim.fs.rm(opts.out_dir, { recursive = true, force = true })
end

---@param opts? static.Config
function M.build(opts)
  if not opts then
    opts = vim.tbl_extend("keep", default_opts, {})
  end

  if
    vim.fn.isdirectory(opts.out_dir) == 1
    and #vim.fn.glob(vim.fs.joinpath(opts.out_dir, "/*"), true, true) > 0
  then
    vim.print("removing old build dir...")
  end

  -- todo what to do with templates
  for f, t in vim.fs.dir(opts.template_dir) do
    if t == "file" and f:match("%.html$") then
      local file, err = io.open(vim.fs.joinpath(opts.template_dir, f))
      if not file then
        vim.print(("error: loading template '%s': %s"):format(f, err))
        return
      end
      opts.templates.base = file:read("a")
      file:close()
    end
  end

  local queue = {
    "/index",
    "/404",
  }
  local visited = { ["/"] = true }

  while #queue > 0 do
    local url_path = table.remove(queue, #queue)
    local in_path = vim.fs.joinpath(opts.pages_dir, url_path)
    if in_path:sub(#in_path, #in_path) == "/" then
      in_path = in_path:sub(1, #in_path - 1)
    end

    local file, err = io.open(in_path .. ".dj", "r")
    if not file then
      vim.print(("error: on '%s': %s"):format(in_path, err))
      return
    end

    local raw_content = file:read("a") or ""
    file:close()

    local document = djot.parse(raw_content, false, function(a)
      vim.print("in warn: ", a)
    end)

    local metadata = {}
    local code_styles = {}
    local filters = {
      {
        link = function(element)
          if element.destination and element.destination:sub(1, 1) == "/" then
            if
              #element.destination > 1
              and element.destination:sub(#element.destination, #element.destination) == "/"
            then
              element.destination = element.destination:sub(1, #element.destination - 1)
            end

            if visited[element.destination] ~= true then
              visited[element.destination] = true
              table.insert(queue, element.destination)
            end
          end
        end,
        code_block = function(element)
          element.tag = "raw_block"
          element.format = "html"
          local code, styles = highlight_code(vim.trim(element.text), element.lang)
          element.text = code
          for _, s in ipairs(styles) do
            table.insert(code_styles, s)
          end
        end,
        raw_block = function(element)
          if element.format == "meta" then
            for line in element.text:gmatch("[^\n]+") do
              local key, value = line:match("(%w+) *= *(.+)$")
              metadata[key] = value
            end
          end
        end,
      },
    }

    djot.filter.apply_filter(document, filters)
    if #code_styles > 0 then
      -- todo don't do all this duplicate work
      code_styles = dedup_list(code_styles)
      table.insert(code_styles, 1, "<style>")
      table.insert(code_styles, "</style>")
    end
    metadata.inline_style = table.concat(code_styles, "\n")

    local rendered = djot.render_html(document)
    rendered = opts.templates.base:gsub("::slot::", rendered)
    rendered = rendered:gsub("::([%w_]+)::", metadata)

    local out_name = vim.fs.joinpath(opts.out_dir, url_path .. ".html")
    vim.fn.mkdir(vim.fs.dirname(out_name), "p")
    local out = io.open(out_name, "w") or {}
    out:write(rendered)
    out:close()
  end

  if pcall(require, "plenary.path") then
    local Path = require("plenary.path")
    Path:new(opts.static_dir):copy({ destination = opts.out_dir, recursive = true })
  else
    vim.print("TODO: copy static files without plenary")
  end
end

return M
