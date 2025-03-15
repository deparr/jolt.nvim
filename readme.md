# static.nvim
(ab)**using nvim for static site generation**

## why
- I want static site with code highlighting
- djot has a lua implementation
- nvim has `:TOhtml` and treesitter
- -> why shouldn't I use my editor to build my site?

> [!CAUTION]
> This is janky software I made for myself. Use carefully.

## workflow
run something like:
```sh
nvim --headless "+SomeConfigCommand | StaticBuild"
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
    - [ ] dark and light code colorschemes
- components ??
- templates
- [ ] TOhtml renders multiline comments on a single line ( might be from
  the .line wrapping I do) you can't just split on line, dang
    - can you just throw a []u8 at treesitter and get a parse tree
      back ???
- [x] user command

