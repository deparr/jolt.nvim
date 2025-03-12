# static.nvim
(ab)**using nvim for static site generation**

## why
- want static site with code highlighting
- djot has a lua implementation
- nvim has `:TOhtml` and treesitter
- -> why shouldn't I use my editor to build my site?

## workflow
run something like:
```sh
nvim --headless "+SomeConfigCommand | BuildSite"
```
and boom! a static site is now available at `build/`

## todo
- figure out a way to do code highlights
    - either from treesitter or require("tohtml").tohtml()
      - [x] currently abusing tohtml to the fullest
        - [ ] normalize hl class names
        - [x] spell hls ???
- config
    - specify in dir
    - specify out dir
- templates
- [x] user command

