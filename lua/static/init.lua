local djot = require("djot")
local config = require("static.config")

local M = {}

M.setup = config.setup

function M.watch() end

local htmlwinnr = -1
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

local function load_file(path)
  local f, err = io.open(path, "r")
  if not f then
    error(("load_file: '%s': %s"):format(path, err))
  end

  local c = f:read("a")
  f:close()
  return c
end

local function write_file(path, content)
  local f, err = io.open(path, "w")
  if not f then
    error(("write_file: '%s': %s"):format(path, err))
  end

  f:write(content)
  f:close()
end

local function highlight_code(code, lang)
  local tohtml = require("tohtml").tohtml
  if htmlwinnr == -1 or not vim.api.nvim_win_is_valid(htmlwinnr) then
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

  for i, v in ipairs(blocks) do
    blocks[i] = ('<span class="line">%s</span>'):format(v)
  end

  table.insert(blocks, 1, "<code>")
  table.insert(blocks, 1, "<pre>")
  table.insert(blocks, 1, '<figure class="code-block">')

  table.insert(blocks, "</code>")
  table.insert(blocks, "</pre>")
  table.insert(blocks, "</figure>")

  local rendered = vim.trim(vim.iter(blocks):join("\n"))

  styles = dedup_list(styles)

  return rendered, styles
end

function M.clean(opts)
  vim.fs.rm(opts.out_dir, { recursive = true, force = true })
end

---@param opts? static.Config
function M.build(opts)
  opts = config.extend(opts)

  -- todo this assumes the build dir already exists
  if
    vim.fn.isdirectory(opts.out_dir) == 1
    and #vim.fn.glob(vim.fs.joinpath(opts.out_dir, "/*"), true, true) > 0
  then
    -- todo not actually removing files so no disk thrashing
    vim.print("removing old build dir...")
  end

  -- todo how to deal with to do with templates
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

  ---@type table<string>
  local queue = {}
  for _, v in ipairs(opts.root_pages) do
    table.insert(queue, v)
  end
  local visited = { ["/"] = true }

  while #queue > 0 do
    local url_path = table.remove(queue, #queue)

    local raw_content = load_file(vim.fs.joinpath(opts.pages_dir, url_path .. ".dj"))

    local document = djot.parse(raw_content, false, function(a)
      vim.print("in warn: ", a)
    end)

    local metadata = {}
    local code_styles = {}
    local filters = {
      {
        link = function(element)
          local is_internal = element.destination and element.destination:match("^([#/])")
          if is_internal then
            -- internal links
            if
              #element.destination > 1
              and element.destination:sub(#element.destination, #element.destination) == "/"
            then
              element.destination = element.destination:sub(1, #element.destination - 1)
            end

            if is_internal == "/" and visited[element.destination] ~= true then
              visited[element.destination] = true
              table.insert(queue, element.destination)
            end
          elseif element.destination then
            -- external links
            element.attr = element.attr or djot.ast.new_attributes()
            element.attr.target = "_blank"
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
        section = function(element)
          element.attr.id = element.attr.id:lower()
          -- todo header anchoring?
        end
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
    metadata.title = metadata.title or opts.default_title

    local rendered = djot.render_html(document)
    rendered = opts.templates.base:gsub(opts.template_main_slot, rendered)
    rendered = rendered:gsub("::([%w_]+)::", metadata)

    local out_dir = vim.fs.joinpath(opts.out_dir, url_path)
    local out_path
    if vim.fs.dirname(url_path) ~= "/" or not vim.tbl_contains(opts.root_pages, url_path) then
      vim.fn.mkdir(out_dir, "p")
      out_path = vim.fs.joinpath(out_dir, "index.html")
    else
      out_path = out_dir .. ".html"
    end

    write_file(out_path, rendered)
  end

  if pcall(require, "plenary.path") then
    local Path = require("plenary.path")
    Path:new(opts.static_dir):copy({ destination = opts.out_dir, recursive = true })
  else
    vim.print("TODO: copy static files without plenary")
  end

  if htmlwinnr > 0 then
    vim.api.nvim_win_close(htmlwinnr, true)
  end

  vim.notify("built:\n" .. vim.inspect(vim.tbl_keys(visited)))
end

return M
