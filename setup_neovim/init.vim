"Ensure clipboard works with vimx
set clipboard=unnamed

"Search for tags files all the way back to /
"Tags are a way of indexing code - useful for multifile projects
set tags=tags;/

"Turn on filetype plugins and indentation
filetype indent plugin on

"Turn syntax highlighting on by default
syntax on

"Turn on file numbers
set number

"Turn on folding based on markers
set fdm=marker

"Indenting
set cindent
"set smartindent " apparently this is deprecated
set autoindent

"Tabbing
set tabstop=2           " set tab to 2 spaces
set expandtab
set shiftwidth=2
set smarttab

"Use 4 spaces in python
autocmd FileType python setlocal shiftwidth=4 softtabstop=4 expandtab

set noswapfile

"Colouring
set background=dark

"Do not yank when putting in visual mode
:map <leader>y "0y
:map <leader>p "0p

"Ignore case on searches
set ic

"Move the vim local dir around intuitively
function LcdIfPossible()
   if filereadable(@%)
      lcd %:h
   endif
endfunction
"if !&diff
"    augroup Lcd
"        autocmd!
"        autocmd BufWinEnter * call LcdIfPossible()
"    augroup END
"endif

"Force standard backspace behaviour
set backspace=2

"Force bash-like tab completion
set completeopt=longest,menuone,preview

"Support IDL, Matlab and Python files
set suffixesadd+=.pro
set suffixesadd+=.idl
set suffixesadd+=.m
set suffixesadd+=.py

"Add current directory to path
set path+=.

"Add cuda headers to cpp highlighting
augroup cuda_ft
    autocmd!
    au BufNewFile,BufRead *.cuh set filetype=cuda
augroup END

" This apparently fixes the bug when compiling C or CPP code where it jumps to 
" header file that doesnt exist and line :0 
set errorformat^=%-GIn\ file\ included\ from\ %f:%l:%c:,%-GIn\ file
            \\ included\ from\ %f:%l:%c\\,,%-GIn\ file\ included\ from\ %f
            \:%l:%c,%-GIn\ file\ included\ from\ %f:%l

" ==================================================================================================================================================
" VIM-PLUG SPECIFIC
" ==================================================================================================================================================

filetype off                  " required

" Specify a directory for plugins
" - For Neovim: stdpath('data') . '/plugged'
" - Avoid using standard Vim directory names like 'plugin'
call plug#begin(stdpath('data') . '/plugged')

if !&diff
    Plug 'heavenshell/vim-pydocstring'
    Plug 'vim-scripts/DoxygenToolkit.vim'
    Plug 'neoclide/coc.nvim', { 'branch': 'release' }
    "Plug 'neoclide/coc.nvim', { 'tag' : 'v0.0.76' }
    "Plug 'neoclide/coc.nvim'
    Plug 'vim-scripts/a.vim'
    Plug 'vvhitedog/tagbar'
    Plug 'dhruvasagar/vim-table-mode'
    Plug 'davidhalter/jedi-vim'
    Plug 'jremmen/vim-ripgrep'
    Plug 'github/copilot.vim', { 'branch' : 'release' }
    Plug 'sjl/vitality.vim'
endif

" These are colorschemes so okay to have in diff
Plug 'morhetz/gruvbox'
Plug 'tyrannicaltoucan/vim-quantum'
Plug 'joshdick/onedark.vim'
Plug 'bfrg/vim-cpp-modern'
"Plug 'rafi/awesome-vim-colorschemes'

" Initialize plugin system
call plug#end()

" ==================================================================================================================================================
" Specifc to plugins and filetypes
" ==================================================================================================================================================

" Having longer updatetime (default is 4000 ms = 4 s) leads to noticeable
" delays and poor user experience.
set updatetime=300

" Don't pass messages to |ins-completion-menu|.
set shortmess+=c

" Always show the signcolumn, otherwise it would shift the text each time
" diagnostics appear/become resolved.
set signcolumn=yes

inoremap <expr> <cr> coc#pum#visible() ? coc#pum#confirm() : "\<CR>"

" use <tab> to trigger completion and navigate to the next complete item
function! CheckBackspace() abort
  let col = col('.') - 1
  return !col || getline('.')[col - 1]  =~# '\s'
endfunction

inoremap <silent><expr> <Tab>
      \ coc#pum#visible() ? coc#pum#next(1) :
      \ CheckBackspace() ? "\<Tab>" :
      \ coc#refresh()

inoremap <expr> <Tab> coc#pum#visible() ? coc#pum#next(1) : "\<Tab>"
inoremap <expr> <S-Tab> coc#pum#visible() ? coc#pum#prev(1) : "\<S-Tab>"

" python related
let g:jedi#goto_command = "<C-j>"

" Check that we are not in diff or preview window modes
if !&diff && !&pvw 

    " remap method jumps to bring you to the function name instead of brackets
    nnoremap [m [m{jf(b
    nnoremap ]m }]m{jf(b

    " Jump to first tag
    "set nocscopetag

    " F5: Find usages/occurrences using rg (r-grep)
    inoremap <expr> <F5>  "<Esc> :sil grep ".expand('<cword>')." .<CR>:botr cw<CR>"
    nnoremap <expr> <F5> ":sil grep ".expand('<cword>')." . <CR>:botr cw<CR>"

    " F4: Find usages/occurrences in current file using vim-grep
    inoremap <expr> <F4>  "<Esc> :lv /".expand('<cword>')."/j % \| :lwindow<CR>"
    nnoremap <expr> <F4> ":lv /".expand('<cword>')."/j % \| :lwindow<CR>"
    " Format using clang
    inoremap <F7> <Esc> :%!clang-format <CR>
    nnoremap <F7>  :%!clang-format <CR>

    nmap <silent> <C-l> :TagbarClose<cr><Plug>(coc-declaration)
    nmap <silent> <C-j> :TagbarClose<cr><Plug>(coc-definition)
    nmap <silent> <C-k> :TagbarClose<cr><Plug>(coc-references)

    nnoremap <silent> <M-m> :CocList outline<cr>
    nmap <silent> <C-n> :CocList symbols<cr>
    nmap <silent> <C-h> :CocList --interactive symbols -kind class<cr>
    nmap <silent> <C-f> :CocList files<cr>

    " follow inheritance
    " basese
    nn <silent> <M-b> :call CocLocations('ccls','$ccls/inheritance')<cr>
    " bases of up to 3 levels
    nn <silent> <M-B> :call CocLocations('ccls','$ccls/inheritance',{'levels':3})<cr>
    " derived
    nn <silent> <M-d> :call CocLocations('ccls','$ccls/inheritance',{'derived':v:true})<cr>
    " derived of up to 3 levels
    nn <silent> <M-D> :call CocLocations('ccls','$ccls/inheritance',{'derived':v:true,'levels':3,'qualified':v:false})<cr>

    nn <silent> <M-e> :call CocLocations('ccls','$ccls/inheritance',{'hierarchy':v:true})<cr>

    " nn <silent> <M-l> :execute '! xdg-open "$(echo https://github.com/omnisci/omniscidb-internal/blob/$(git rev-parse --abbrev-ref HEAD)/' . @% . '\#L' . line(".") . ')"'<cr>
    " nn <silent> <M-L> :execute '! xdg-open "$(echo https://github.com/omnisci/omniscidb-internal/blob/master/' . @% . '\#L' . line(".") . ')"'<cr>

    nn <silent> <M-l> :call jobstart('xdg-open "$(echo https://github.com/omnisci/omniscidb-internal/blob/$(git rev-parse --abbrev-ref HEAD)/' . @% . '\#L' . line(".") . ')"')<cr>
    nn <silent> <M-L> :call jobstart('xdg-open "$(echo https://github.com/omnisci/omniscidb-internal/blob/master/' . @% . '\#L' . line(".") . ')"')<cr>

    nn <silent> <M-c> :sil execute '! echo $(readlink -f ' . @% . '):' . line(".") . ' \| tr -d "\n" \| xsel -ib'<cr>

    " fine-graned references, callee vs caller
    " caller
    nn <silent> <M-x>c :call CocLocations('ccls','$ccls/call')<cr>
    " callee
    nn <silent> <M-x>C :call CocLocations('ccls','$ccls/call',{'callee':v:true})<cr>

    " Use <cr> to confirm completion, `<C-g>u` means break undo chain at current
    " position. Coc only does snippet and additional edit on confirm.
    "if has('patch8.1.1068')
    "  " Use `complete_info` if your (Neo)Vim version supports it.
    "  inoremap <expr> <cr> complete_info()["selected"] != "-1" ? "\<C-y>" : "\<C-g>u\<CR>"
    "else
    "  imap <expr> <cr> pumvisible() ? "\<C-y>" : "\<C-g>u\<CR>"
    "endif

    function! HelpWithFocus()
      call CocAction('doHover')
    endfunction
    nn <silent> K :call HelpWithFocus()<cr>

    inoremap <silent><expr> <c-space> coc#refresh()

    " Symbol renaming.
    nmap <leader>r <Plug>(coc-rename)

    " coc rename is rather broken, use clang-rename.py instead:
    noremap <leader>cr :pyf ~/.local/bin/clang-rename.py<cr>

    " help with view diffs 
    nmap <C-b> :pyf ~/.local/bin/git-diff3-view.py<cr>

    " Open outline tagbar (note vista is horrible for keeping jump-lists
    " sane.)
    nmap <M-o> :TagbarOpen j<cr>:TagbarOpen j<cr>
    nmap <M-t> :TagbarToggle<cr>
    
    let g:tagbar_ctags_bin = '/home/mgara/.local/bin/ctags'

    function GitDiff(base)
       if filereadable(@%)
         wincmd n
         execute 'r!git diff ' a:base ' #'
         set ft=diff
         normal ggdd
         execute 'w! ' . tempname()
       endif
    endfunction

    function GitDiffWin(base)
       if filereadable(@%)
         wincmd n
         execute 'r!git show ' . trim(a:base) . ':' . trim(bufname(winbufnr(winnr('#'))))
         set ft=cpp
         normal ggdd
         execute 'w! ' . tempname()
         wincmd H
         execute 'windo diffthis'
       endif
    endfunction

    function GenTags()
       execute '!ctags -R --exclude="*build*" --exclude="*Test/FsiDataFiles*" --exclude=".ccls-cache" --exclude="docker" --exclude="FsiDataFiles" .'
    endfunction

    command! -nargs=0 GenTags call GenTags()

    function Terminal(name)
       execute 'terminal'
       execute 'file ' . trim(a:name)
    endfunction

    command! -nargs=1 Term call Terminal(<f-args>)

    function TabTerminal(name)
       execute 'tabe'
       execute 'terminal'
       execute 'file ' . trim(a:name)
    endfunction

    command! -nargs=1 TTerm call TabTerminal(<f-args>)

    function RipgrepDefault(arg) 
      execute 'Rg -i -g "!tags" -g "!compile_commands.json" -g "!build*" "'  . a:arg . '"'
    endfunction

    command! -nargs=1 R call RipgrepDefault(<f-args>)

    function RipgrepLocalDefault(arg) 
      execute 'Rg -i -g "!tags" -g "!compile_commands.json" -g "!build*" "' . a:arg . '" %'
    endfunction

    command! -nargs=1 Rh call RipgrepLocalDefault(<f-args>)

    function GitDiffWin2(base1,base2)
       if filereadable(@%)

         wincmd n
         execute 'r!git show ' . trim(a:base1) . ':' . trim(bufname(winbufnr(winnr('#'))))
         set ft=cpp
         normal ggdd
         w! /tmp/nvim-git-show-1.tmp
         wincmd H
         wincmd w

         wincmd n
         execute 'r!git show ' . trim(a:base2) . ':' . trim(bufname(winbufnr(winnr('#'))))
         set ft=cpp
         normal ggdd
         w! /tmp/nvim-git-show-2.tmp
         wincmd H
         wincmd w

         execute 'windo diffthis'
       endif
    endfunction

    nmap <leader>qf <Plug>(coc-fix-current)

    nmap <M-g> :call GitDiff("")<cr>
    nmap <M-G> :call GitDiff("origin/HEAD")<cr>

    nmap <M-f> :call GitDiffWin("")<cr>
    nmap <M-F> :call GitDiffWin("origin/HEAD")<cr>

    nmap <C-q> :bd<cr>:bd<cr>

    function GitBlame()
       if filereadable(@%)
         let lineno = line('.')
         wincmd n
         r!git blame #
         set ft=cpp
         normal ggdd
         execute 'w! ' . tempname()
         execute 'normal ' . lineno . 'G'
       endif
    endfunction

    nmap <M-h> :call GitBlame()<cr>

    function FifoMake()
      call system('echo make > /tmp/fifo')
    endfunction

    nmap <M-k> :call FifoMake()<cr>

    let &gp="rg -n $* /dev/null"

    nmap <M-1> 1gt
    nmap <M-2> 2gt
    nmap <M-3> 3gt
    nmap <M-4> 4gt
    nmap <M-5> 5gt
    nmap <M-6> 6gt
    nmap <M-7> 7gt
    nmap <M-8> 8gt
    nmap <M-9> 9gt

    imap <M-1> <ESC>1gt
    imap <M-2> <ESC>2gt
    imap <M-3> <ESC>3gt
    imap <M-4> <ESC>4gt
    imap <M-5> <ESC>5gt
    imap <M-6> <ESC>6gt
    imap <M-7> <ESC>7gt
    imap <M-8> <ESC>8gt
    imap <M-9> <ESC>9gt

    vmap <M-1> <ESC>1gt
    vmap <M-2> <ESC>2gt
    vmap <M-3> <ESC>3gt
    vmap <M-4> <ESC>4gt
    vmap <M-5> <ESC>5gt
    vmap <M-6> <ESC>6gt
    vmap <M-7> <ESC>7gt
    vmap <M-8> <ESC>8gt
    vmap <M-9> <ESC>9gt

    tmap <M-1> <C-\><C-n>1gt
    tmap <M-2> <C-\><C-n>2gt
    tmap <M-3> <C-\><C-n>3gt
    tmap <M-4> <C-\><C-n>4gt
    tmap <M-5> <C-\><C-n>5gt
    tmap <M-6> <C-\><C-n>6gt
    tmap <M-7> <C-\><C-n>7gt
    tmap <M-8> <C-\><C-n>8gt
    tmap <M-9> <C-\><C-n>9gt

    nmap <C-s> g<TAB>
    imap <C-s> <ESC>g<TAB>
    vmap <C-s> <ESC>g<TAB>
    tmap <C-s> <C-\><C-n>g<TAB>

    nmap <C-a> <ESC>
    imap <C-a> <ESC>
    vmap <C-a> <ESC>
    tmap <C-a> <C-\><C-n>

    nmap <A-j> :CocList buffers<cr>
    imap <A-j> <ESC>:CocList buffers<cr>
    vmap <A-j> <ESC>:CocList buffers<cr>
    tmap <A-j> <C-\><C-n>:CocList buffers<cr>

    nmap <C-x><C-x> :CocList windows<cr>
    imap <C-x><C-x> <ESC>:CocList windows<cr>
    vmap <C-x><C-x> <ESC>:CocList windows<cr>
    tmap <C-x><C-x> <C-\><C-n>:CocList windows<cr>

endif

"filetype plugin indent on

" In the quickfix window, <CR> is used to jump to the error under the
" cursor, so undefine the mapping there.
autocmd BufReadPost quickfix nnoremap <buffer> <CR> <CR>

set previewheight=25
nmap <M-]> <C-w>}<C-w><C-w>

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"" COLORS AND DISPLAY:
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
set termguicolors
colorscheme onedark

set statusline=%f[%{strlen(&fenc)?&fenc:'none'},%{&ff}]%h%m%r%y%=%c,%l/%L\ %P

hi TagbarVisibilityProtected guifg=orange 
hi StatusLine guifg=#282c34 guibg=#abb2bf
hi StatusLineNC guifg=#abb2bf guibg=#4b5263
hi TabLine guifg=#14161a guibg=#676b73
hi TabLineSel guifg=#282c34 guibg=#abb2bf
hi TabLineFill guifg=#14161a guibg=#676b73
hi Title guibg=#282c34 guifg=#abb2bf
hi TabLineNC guibg=#dae2f2 guifg=#74a0f7

hi Normal guibg=#1D282E

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"" FIX TABLLINE TO SHOW NUMBERS:
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Rename tabs to show tab number.
" (Based on http://stackoverflow.com/questions/5927952/whats-implementation-of-vims-default-tabline-function)
" taken from https://superuser.com/a/477221/734404
if exists("+showtabline")
    function! MyTabLine()
        let s = ''
        let wn = ''
        let t = tabpagenr()
        let i = 1
        while i <= tabpagenr('$')
            let buflist = tabpagebuflist(i)
            let winnr = tabpagewinnr(i)
            let s .= '%' . i . 'T'
            let s .= (i == t ? '%1*' : '%2*')
            "let s .= ' '
            let wn = tabpagewinnr(i,'$')

            let s .= '%#TabNum#'
            "let s .= '%#TabLineSel#'
            let s .= '|'
            let s .= i
            let s .= '|'
            "let s .= '%*'
            let s .= (i == t ? '%#TabLineSel#' : '%#TabLine#')
            let bufnr = buflist[winnr - 1]
            let file = bufname(bufnr)
            let buftype = getbufvar(bufnr, 'buftype')
            if buftype == 'nofile'
                if file =~ '\/.'
                    let file = substitute(file, '.*\/\ze.', '', '')
                endif
            else
                let file = fnamemodify(file, ':p:t')
            endif
            if file == ''
                let file = '[No Name]'
            endif
            let s .= ' ' . file . ' '
            let i = i + 1
        endwhile
        let s .= '%T%#TabLineFill#%='
        "let s .= (tabpagenr('$') > 1 ? '%999XX' : 'X')
        return s
    endfunction
    set stal=2
    set tabline=%!MyTabLine()
    set showtabline=1
    highlight link TabNum Special
endif

"If the Pmenu is messed up try setting colors manually:
"highlight PMenuSel cterm=bold ctermbg=Green ctermfg=None

" setup doq
let g:pydocstring_doq_path = '~/.local/bin/doq'
let g:pydocstring_formatter = 'numpy'

" colorcolumn
set colorcolumn=80
:let g:python_recommended_style = 0

" wtf?
if has('nvim-0.4.3') || has('patch-8.2.0750')
          nnoremap <nowait><expr> <C-y> coc#float#has_scroll() ? coc#float#scroll(1) : "\<C-f>"
          nnoremap <nowait><expr> <C-e> coc#float#has_scroll() ? coc#float#scroll(0) : "\<C-b>"
          inoremap <nowait><expr> <C-y> coc#float#has_scroll() ? "\<c-r>=coc#float#scroll(1)\<cr>" : "\<Right>"
          inoremap <nowait><expr> <C-e> coc#float#has_scroll() ? "\<c-r>=coc#float#scroll(0)\<cr>" : "\<Left>"
endif


"From help :
"To map <Esc> to exit terminal-mode: >vim
":tnoremap <Esc> <C-\><C-n>
" Currently disabled due to prefering to use ALT+N to switch to normal mode,
" this also allows the use of VIM or NEOVIM within the terminals

set cursorline

"autocmd FocusLost * hi Normal guibg=#0a2333
autocmd FocusLost * hi Normal guibg=#0e191f
autocmd FocusGained * hi Normal guibg=#1D282E

function! ConfirmQuit(all)
    let l:confirmed = confirm("Terminal(s) may be open, do you really want to quit?", "&Yes\n&No", 2)
    if l:confirmed == 1
      if (a:all)
        quitall
      else
        quit
      endif
    endif
endfu

au termopen * cnoremap <silent> q<cr> call ConfirmQuit(0)<cr>
au termenter * cnoremap <silent> q<cr> call ConfirmQuit(0)<cr>
au termleave * cnoremap <silent> q<cr> call ConfirmQuit(0)<cr>
au termopen * cnoremap <silent> qa<cr> call ConfirmQuit(1)<cr>
au termenter * cnoremap <silent> qa<cr> call ConfirmQuit(1)<cr>
au termleave * cnoremap <silent> qa<cr> call ConfirmQuit(1)<cr>
