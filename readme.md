# djot.nvim

## why
- want static site with code highlighting
- djot has a lua implementation
- nvim has `:TOhtml` and/or treesitter
- -> why shouldn't I use my editor to build my site?

## workflow
run something like:
```sh
nvim -l build.lua
```
eventually I want
```sh
nvim --headless "+SomeConfigCommand | BuildSite"
```
which would allow for setting build opts like in/out dirs, colorschemes, formatting, etc.

## todo
- figure out a way to do code highlights
    - either from treesitter or require("tohtml").tohtml()
- specify in dir
- specify out dir
- user commands
