# static.nvim
(ab)**using nvim for static site generation**

## why
- I want static site with code highlighting
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
- use more nvim features
    - [ ] bufwritepost autocmd for watch mode
        - [ ] granular rebuilding depending on what changed
        - [ ] how would this interact with tohtml ??
    - [ ] ability to build main css file from colorscheme
    - [ ] use something to serve the files over local server
- components ??
- templates
- [x] user command

