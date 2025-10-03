local djot = require("djot")
local config = require("jolt.config")
local log = require("jolt.log").scoped("build")
local fs = vim.fs

local M = {}

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

--- todo this is not robust
local function ensure_dir_exists(path)
  local parent = vim.fn.fnamemodify(path, ":e") == "" and path or fs.dirname(path)
  vim.fn.mkdir(parent, "p")
end

local function write_all(paths)
  for file, content in pairs(paths) do
    ensure_dir_exists(file)
    write_file(file, content)
  end
end

---@param list table<any>
---@param new table<any>
--- appends values from `new` that aren't already in `list` to `list`
local function add_if_not_present(list, new)
  for _, v in ipairs(new) do
    if not vim.list_contains(list, v) then
      table.insert(list, v)
    end
  end
end

---@param str string
---@return boolean `true if `str` is nil or empty
local function empty_or_nil(str)
  return str == nil or str == ""
end

local ordmonth = {
  january = 1, jan = 1, february = 2, feb = 2, march = 3, mar = 3, april = 4, apr = 4,
  may = 5, june = 6, jun = 6, july = 7, jul = 7, august = 8, aug = 8,
  september = 9, sept = 9, october = 10, oct = 10, november = 11, nov = 11,
  december = 12, dec = 12,
}

local function capture_name_to_class_name(name)
  return "hl-" .. (name:gsub("%.", "-"))
end

local function html_escape(str)
  str = str:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;")
  return str
end

---@param code string|string[] code block content, either as lines or string
---@param lang string language to highlight as
---@return table<string> rendered_lines, table<string> styles
local function highlight_code(code, lang)
  local log = require("jolt.log").scoped("build.hl")
  local code_lines
  if type(code) == "table" then
    code_lines = code
    code = table.concat(code, "\n")
  else
    code_lines = vim.split(code, "\n")
  end

  local ok, parser = pcall(vim.treesitter.get_string_parser, code, lang, {})
  if not ok then
    if lang then
      log("unable to load parser for " .. lang .. ". Is it installed?", vim.log.levels.WARN)
    end
    return code_lines, {}
  end
  local root = parser:parse() or error("todo parse timed out")
  if #root > 1 then
    log("TODO wrap_and_highlight_code: parse injected languages")
  end
  root = root[1]:root()
  local queryset = vim.treesitter.query.get(lang, "highlights")

  if not queryset then
    log("no highlight queryset for lang: " .. lang, vim.log.levels.WARN)
    return code_lines, {}
  end

  local rendered = {}
  local styles = {}
  local linenr = 0
  local cursor = 0
  local hl_span_fmt = '<span class="%s">%s</span>'
  local line = {}
  local finish_line = function(diff)
    linenr = linenr + diff
    table.insert(rendered, table.concat(line, ""))
    line = {}
    cursor = 0
    for _ = 1, diff - 1 do
      table.insert(rendered, "")
    end
  end

  -- TODO: read treesitter docs, there might be an intended parsing strategy
  local function range_equal(a, b)
    return a[1] == b[1] and a[2] == b[2] and a[3] == b[3] and a[4] == b[4]
  end
  local function range_within(a, b)
    return a[1] == b[1] and a[2] >= b[2] and a[4] <= b[4]
  end
  local prev_range = { -1, -1, -1, -1 }
  for id, node in queryset:iter_captures(root, code) do
    local name = queryset.captures[id]
    local srow, scol, erow, ecol = node:range()
    local cur_range = { srow, scol, erow, ecol, name = name }

    if name == "spell" or name == "nospell" or name == "none" or name:sub(1, 1) == "_" then
      goto continue
    end

    styles["@" .. name] = true

    if srow > linenr then
      finish_line(srow - linenr)
      prev_range = { -1, -1, -1, -1 }
    end

    if scol > cursor then
      local normal = code_lines[linenr + 1]:sub(cursor + 1, scol)
      table.insert(line, html_escape(normal))
    end

    local class = capture_name_to_class_name(name)
    if srow ~= erow then
      if not range_equal(cur_range, prev_range) then
        local line_str = code_lines[linenr + 1]
        line_str = html_escape(line_str:sub(scol + 1))
        table.insert(line, hl_span_fmt:format(class, line_str))
        finish_line(1)

        while linenr < erow do
          line_str = html_escape(code_lines[linenr + 1])
          table.insert(line, hl_span_fmt:format(class, line_str))
          finish_line(1)
        end

        if ecol > 0 then
          line_str = html_escape(code_lines[linenr + 1]:sub(1, ecol))
          table.insert(line, hl_span_fmt:format(class, line_str))
        end
        cursor = ecol
        prev_range = cur_range
      end
      goto continue
    end

    local rendered_node = code_lines[linenr + 1]:sub(scol + 1, ecol)
    rendered_node = hl_span_fmt:format(class, html_escape(rendered_node))

    if range_equal(cur_range, prev_range) then
      line[#line] = rendered_node
      styles["@" .. prev_range.name] = nil
    elseif range_within(cur_range, prev_range) then
      -- todo nested captures will be harder than
      -- I thought, just remove their hls for now
      styles["@" .. cur_range.name] = nil
    else
      -- regular node
      table.insert(line, rendered_node)

      prev_range = cur_range
      cursor = ecol
    end

    ::continue::
  end

  finish_line(0)

  return rendered, vim.tbl_keys(styles)
end

---@param code string|string[] code block content
---@param lang string language to highlight as
---@return string rendered, table<string> styles
local function wrap_and_highlight_code(code, lang)
  local rendered_lines, styles = highlight_code(code, lang)
  if lang then
    rendered_lines[1] = ('<pre class="%s"><code class="%s">'):format(lang, lang) .. rendered_lines[1]
  else
    rendered_lines[1] = '<pre><code>' .. rendered_lines[1]
  end
  rendered_lines[#rendered_lines] = rendered_lines[#rendered_lines] .. "</code></pre>"

  local rendered = vim.trim(vim.iter(rendered_lines):join("\n"))

  return rendered, styles
end

---@param name string css class name to convert
---@return string vim_hl_name
local function class_name_to_hl_name(name)
  return (name:gsub("^hl-", "@"):gsub("%-", "."))
end

---@param name string vim hl_group to convert
---@return string css_class_name
local function hl_name_to_class_name(name)
  return (name:gsub("^%@", "hl-"):gsub("%.+", "-"))
end

local function hex_to_str(c)
  if type(c) == "string" and c:sub(1, 1) == "#" then
    return c
  end
  return ("#%06x"):format(c)
end

local function get_hl_defs(hl_groups)
  local used_hls = {}
  for _, group in ipairs(hl_groups) do
    used_hls[group] = vim.api.nvim_get_hl(0, { name = group, link = false })
  end
  return used_hls
end

---@param hl_groups table<string, vim.api.keyset.highlight>
--- generates css classes for the given highlight groups
local function generate_styles_for_colorscheme(hl_groups)
  local out = {}
  for name, hl in pairs(hl_groups) do
    local line = {
      hl.underline and "underline" or nil,
      hl.strikethrough and "line-through" or nil,
      hl.undercurl and "underline" or nil,
    }
    local attrs = {
      color = hl.fg and hex_to_str(hl.fg) or nil,
      ["background-color"] = hl.bg and hex_to_str(hl.bg) or nil,
      ["font-style"] = hl.italic and "italic" or nil,
      ["font-weight"] = hl.bold and "bold" or nil,
      ["text-decoration-line"] = #line > 0 and table.concat(line, " ") or nil,
      ["text-decoration-color"] = hl.sp and hex_to_str(hl.sp) or nil,
      ["text-decoration-style"] = hl.undercurl and "wavy" or nil,
    }
    local s = {}
    for attr, val in pairs(attrs) do
      table.insert(s, attr .. ": " .. val)
    end
    table.insert(out, (".%s {%s}"):format(hl_name_to_class_name(name), table.concat(s, "; ")))
  end

  return out
end

---@param opts jolt.Config
---@param hl_groups table<string> hl groups to generate styles for
---@return string css_stylesheet
local function generate_code_styles(opts, hl_groups)
  local light, dark
  if type(opts.code_style) == "function" then
    light = opts.code_style("light", hl_groups)
    dark = opts.code_style("dark", hl_groups)

    light = generate_styles_for_colorscheme(light)
    dark = generate_styles_for_colorscheme(dark)
  else
    local restore = opts.code_style.restore or "default"
    local restore_bg = vim.o.bg
    vim.cmd("hi clear")
    vim.o.bg = "light"
    vim.cmd.colorscheme(opts.code_style.light)
    light = generate_styles_for_colorscheme(get_hl_defs(hl_groups))
    vim.cmd("hi clear")
    vim.o.bg = "dark"
    vim.cmd.colorscheme(opts.code_style.dark)
    dark = generate_styles_for_colorscheme(get_hl_defs(hl_groups))
    if not config.headless then
      vim.o.bg = restore_bg
      vim.cmd.colorscheme(restore)
    end
  end

  return ([[%s

[data-theme="dark"] {
	%s
}]]):format(table.concat(light, "\n"), table.concat(dark, "\n\t"))
end

---@param document AST djot ast
---@param code_styles table<string> list of highlight groups used by code blocks
---@return table metadata
--- Filters a page. Highlighting code blocks, anchoring headers, and setting metadata
function M.filter(document, code_styles, opts)
  opts = config.extend(opts)
  local metadata = {}
  local filters = {
    {
      link = function(element)
        local is_internal = element.destination and element.destination:match("^([#/])")
        if is_internal then
          if
              #element.destination > 1
              and element.destination:sub(#element.destination, #element.destination) == "/"
          then
            element.destination = element.destination:sub(1, #element.destination - 1)
          end
        elseif element.destination then
          if element.destination:match("^(https?):") then
            element.attr = element.attr or djot.ast.new_attributes()
            element.attr.target = "_blank"
          end
        end
      end,
      code_block = function(element)
        element.tag = "raw_block"
        element.format = "html"
        local code, styles = wrap_and_highlight_code(vim.trim(element.text), element.lang)
        element.text = code
        add_if_not_present(code_styles, styles)
      end,
      raw_block = function(element)
        if element.format == "meta" then
          for line in element.text:gmatch("[^\n]+") do
            local key, value = line:match("([%w_]+) *=%s*(.+)$")
            metadata[key] = value
          end
        end
      end,
      section = function(element)
        element.attr.id = element.attr.id:lower()
        -- todo header anchoring?
      end,
      -- image = function(element)
      --   -- todo I want to wrap images in figures
      --   -- element.tag = "raw_block"
      --   -- element.format = "html"
      --   -- local dest = element.destination
      --   -- local alt = element.children[1].text
      --   -- element.children = nil
      --   -- element.text = ('<figure><img src="%s" alt="%s"></img></figure>'):format(dest, alt)
      -- end,
    },
  }
  djot.filter.apply_filter(document, filters)

  metadata.template = metadata.template or opts.default_template
  metadata.title = metadata.title or opts.default_title
  metadata.description = metadata.description or metadata.title

  ---@diagnostic disable
  --- lua ls doesn't like string -> string[]
  metadata.tags = vim.split(metadata.tags or "", ",", { trimempty = true })
  metadata.template = vim.split(metadata.template, ",", { trimempty = true })
  ---@diagnostic enable

  if type(metadata.slot) ~= "nil" then
    log("invalid metadata key 'slot' on page, removing...", vim.log.levels.WARN)
    metadata.slot = nil
  end

  return metadata
end

local function scan(pred, opts)
  local ret = {}
  for file, type in fs.dir(opts.content_dir, { depth = opts.depth }) do
    local ext = vim.fn.fnamemodify(file, ":e")
    if pred(file, type, ext) then
      ret[file] = true
    end
  end
  return ret
end

function M.scan_pages(opts)
  opts = config.extend(opts)
  return scan(function(_, t, e)
    return t == "file" and (e == "dj" or e == "djot")
  end, opts)
end

function M.scan_templates(opts)
  opts = config.extend(opts)
  return scan(function(_, t, e)
    return t == "file" and e == "html"
  end, opts)
end

function M.scan_static(opts)
  opts = config.extend(opts)
  return scan(function(f, t, e)
    return (
      t == "file"
      and e ~= "dj"
      and e ~= "djot"
      and e ~= "html"
      and not f:find("%.dj%.draft$")
    )
  end, opts)
end

-- Build State
local page_metadata = {}
local templates = {}
local code_styles = {}
local rendered_pages = {}
local should_generate_blog = true

---@param opts? jolt.Config
function M.build_all(opts)
  opts = opts or config.extend(opts)

  if vim.fn.isdirectory(opts.out_dir) == 1 then
    if #vim.fn.glob(fs.joinpath(opts.out_dir, "/*"), true, true) > 0 then
      -- todo maybe clean should happen before writes, can skip equal content
      M.clean()
    end
  else
    vim.fn.mkdir(opts.out_dir, "p")
  end

  local files = scan(function(_, t, _)
    return t == "file"
  end, opts)

  -- todo: rss feed gen will probably want to separate build and output writing
  M.build_changeset(files, opts)
end

--- Renders or copies the specified files to the build directory.
--- Assumes the build directory exists.
---
--- IMPORTANT: the keys of `files` are taken as the input files, their values are ignored.
---@param files table<string, any> the changeset, file paths relative to `opts.content_dir`
---@param opts? jolt.Config
function M.build_changeset(files, opts)
  opts = opts or config.extend()
  local updated_pages = {}
  local updated_templates = {}
  local static = {}
  local djot_log = function(a)
    log("djot: " .. vim.inspect(a, { newline = "" }))
  end

  for file, _ in pairs(files) do
    local ext = vim.fn.fnamemodify(file, ":e")
    local basename = vim.fn.fnamemodify(file, ":t:r")
    local path_noext = vim.fn.fnamemodify(file, ":r")
    local real_path = fs.joinpath(opts.content_dir, file)

    if ext == "dj" then
      local raw = load_file(real_path)
      local ast = djot.parse(raw, false, djot_log)
      updated_pages[path_noext] = ast
    elseif ext == "html" then
      local templ = load_file(real_path)
      updated_templates[basename] = templ
    else
      local should_copy = file:match("^.+%.dj%.draft$") == nil
      static[file] = should_copy
    end
  end

  for name, new_template in pairs(updated_templates) do
    templates[name] = new_template
  end

  local new_code_styles = {}
  for url, document in pairs(updated_pages) do
    local metadata = M.filter(document, new_code_styles, opts)
    page_metadata[url] = metadata

    local rendered = djot.render_html(document)
    rendered_pages[url] = rendered
  end

  -- build and render the blog post list page now that we
  -- know which pages are blog posts
  -- todo: this needs to be able to sort blog posts
  if opts.blog.enable and #vim.tbl_keys(updated_pages) > 0 and should_generate_blog then
    if empty_or_nil(opts.blog.page_template) or empty_or_nil(opts.blog.post_item_template) then
      log("a blog template is empty, blog output could fail or be weird", vim.log.levels.ERROR)
    end
    local post_items = {}
    local date_extract_pat = "(%w+) *(%d+).*, *(%d+)"
    local pack = function(...)
      return { n = select("#", ...), ... }
    end
    for url, metadata in pairs(page_metadata) do
      if vim.list_contains(metadata.tags, opts.blog.tag) then
        table.insert(post_items, { url = url, d = pack(metadata.date:match(date_extract_pat)) })
        local d = post_items[#post_items].d
        d[1] = ordmonth[d[1]:lower()] or 0
        d[2] = tonumber(d[2])
        d[3] = tonumber(d[3])
      end
    end

    if #post_items > 0 then
      table.sort(post_items, function(a, b)
        -- compare year > month > day
        if a.d[3] ~= b.d[3] then
          return a.d[3] > b.d[3]
        elseif a.d[1] ~= b.d[1] then
          return a.d[1] > b.d[1]
        end
        return a.d[2] > b.d[2]
      end)
      for i, post in ipairs(post_items) do
        local metadata = page_metadata[post.url]
        metadata.url = "/" .. post.url
        local post_raw = opts.blog.post_item_template:gsub("::([%w_]+)::", metadata)
        post_items[i] = post_raw
        metadata.url = nil
      end

      local post_item_raw = table.concat(post_items, "\n")
      local blog_page_raw = opts.blog.page_template:gsub("::posts::", post_item_raw)

      local blog_doc = djot.parse(blog_page_raw, false, djot_log)
      local blog_metadata = M.filter(blog_doc, new_code_styles, opts)
      local blog_html = djot.render_html(blog_doc)

      page_metadata[opts.blog.output_url] = blog_metadata
      rendered_pages[opts.blog.output_url] = blog_html
      updated_pages[opts.blog.output_url] = blog_doc

      -- only generate it on the first build
      -- todo: work out a sensible way to do partial rebuilds of this
      should_generate_blog = false
    end
  end

  local fully_rendered_pages = {}
  local substitute_templates = function(url)
    local metadata = page_metadata[url]
    local rendered = rendered_pages[url]
    for _, template in ipairs(metadata.template) do
      rendered = templates[template]:gsub("::slot::", rendered)
      rendered = rendered:gsub("::([%w_]+)::", metadata)
    end
    fully_rendered_pages[url] = rendered
  end

  for _, url in ipairs(vim.tbl_keys(updated_pages)) do
    substitute_templates(url)
  end

  local updated_template_names = vim.tbl_keys(updated_templates)
  if #updated_template_names > 0 then
    for _, url in ipairs(vim.tbl_keys(rendered_pages)) do
      if not updated_pages[url] then
        local metadata = assert(page_metadata[url], "nil metadata on a rendered page")
        for _, template_name in ipairs(updated_template_names) do
          if vim.tbl_contains(metadata.template, template_name) then
            substitute_templates(url)
            break
          end
        end
      end
    end
  end

  local out_paths = {}
  for url, rendered_html in pairs(fully_rendered_pages) do
    local out_path
    -- speical cases
    -- index -> index.html
    -- 404 -> 404.html
    local tail = fs.basename(url)
    if tail == "404" or tail == "index" then
      out_path = fs.joinpath(opts.out_dir, url .. ".html")
    else
      out_path = fs.joinpath(opts.out_dir, url, "index.html")
    end

    if out_paths[out_path] ~= nil then
      log(
        ("muilple in-files mapped to same the out-file '%s'"):format(out_path),
        vim.log.levels.WARN
      )
    end
    out_paths[out_path] = rendered_html
  end

  write_all(out_paths)

  if #new_code_styles > 0 then
    local old_style_len = #code_styles
    add_if_not_present(code_styles, new_code_styles)
    if old_style_len ~= #code_styles then
      static["css/highlight.css"] = generate_code_styles(opts, code_styles)
    end
  end

  M.write_static(static, opts)

  log(
    ("rendered %d pages, %d static files"):format(
      #vim.tbl_keys(fully_rendered_pages),
      #vim.tbl_keys(static)
    )
  )
end

function M.build_highlight_sheet(opts)
  opts = config.extend(opts)
  if #code_styles == 0 then
    return ""
  end
  local hl_sheet = generate_code_styles(opts, code_styles)
  return hl_sheet
end

---@param static table<string, string|boolean> files to copy
---@param opts? jolt.Config
function M.write_static(static, opts)
  opts = opts or config.extend()
  for file, content in pairs(static) do
    local out = fs.joinpath(opts.out_dir, file)
    if type(content) == "boolean" and content then
      local in_ = fs.joinpath(opts.content_dir, file)
      ensure_dir_exists(out)
      local _, err = vim.uv.fs_copyfile(in_, out, nil)
      if err then
        log(err)
      end
    elseif type(content) == "string" then
      ensure_dir_exists(out)
      write_file(out, content)
    end
  end
end

---@param opts? jolt.Config
--- cleans `opts.out_dir`, if it exists
function M.clean(opts)
  opts = opts or config.extend()
  -- todo research/workout a better way to make this safe
  if opts.out_dir == "~" or opts.out_dir == "/" or opts.out_dir == os.getenv("HOME") then
    log(("wont remove out dir '%s'"):format(opts.out_dir), vim.log.levels.ERROR)
    return
  end
  fs.rm(opts.out_dir, { recursive = true, force = true })

  page_metadata = {}
  templates = {}
  code_styles = {}
  rendered_pages = {}
end

return M
