# jolt.nvim
(ab)**using nvim for static site generation**

## why
- I want a simple, static site with code highlighting
- djot has a lua implementation
- nvim has `:TOhtml` and treesitter
- -> why shouldn't I use my editor to build my site?

> [!CAUTION]
> This is janky software I made for myself. There might be hardcoding
> and assumptions. Commands might not even be wired up to anything.
> There are no tests. Read before use and use carefully.

## workflow
run something like:
```sh
nvim --headless "+Jolt build"
```
and boom! a static site is now available at `build/`

## todo / planned / ideas
> loosely ordered by priority
- [ ] headless ux should be equivalent to interactive
- [x] code block highlighting based on neovim colorscheme
    - [ ] works, but relying on `:TOhtml` is pretty janky (would need to be
      properly parsed). look into
      generating the html myself with treesitter.
        - can you just throw a []u8 at treesitter and get a parse tree
          back ???
        - this would also make the html a little cleaner
- [x] feature-full user commands
    - [ ] command line parsing is a little jank, should revisit
- [ ] templates: current templates are hardcoded
    - should be able to nest templates
    - templates should be able to be scanned in any order
        - components
- [ ] watch mode
    - use libuv to watch the uses content dir for changes
    - should be granular if possible, only rebuild what changed
    - should be able to serve at the same time
- [ ] serve mode
    - run a user supplied system command to serve the build directory
      locally
    - headless: pass-through cmd output to terminal
    - interactive: display cmd output in a split or tab
- [ ] vim docs
- [x] allow sub-dirs to have an index. i.e. `/blog/blog.dj` and/or
  `/blog/index.dj` becomes `/blog/index.html`
- [ ] config options
    - [ ] tree-walk build mode: starting from root pages, build the
      reachable link tree
    - [ ] which "url mode": i.e. whether `/blog/some-post.dj` should
      become `/blog/some-post.html` or `/blog/some-post/index.html`

