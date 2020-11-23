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
    "Plug 'neoclide/coc.nvim'
    Plug 'vim-scripts/a.vim'
    Plug 'vvhitedog/tagbar'
    Plug 'dhruvasagar/vim-table-mode'
endif

" fzf plugin below is just a hastle:
"Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
"Plug 'junegunn/fzf.vim'

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

" Use tab for trigger completion with characters ahead and navigate.
" NOTE: Use command ':verbose imap <tab>' to make sure tab is not mapped by
" other plugin before putting this into your config.
inoremap <silent><expr> <TAB>
      \ pumvisible() ? "\<C-n>" :
      \ <SID>check_back_space() ? "\<TAB>" :
      \ coc#refresh()
inoremap <expr><S-TAB> pumvisible() ? "\<C-p>" : "\<C-h>"

function! s:check_back_space() abort
  let col = col('.') - 1
  return !col || getline('.')[col - 1]  =~# '\s'
endfunction

" Check that we are not in diff or preview window modes
if !&diff && !&pvw 

    " remap method jumps to bring you to the function name instead of brackets
    nnoremap [m [m{jf(b
    nnoremap ]m }]m{jf(b

    " Jump to first tag
    set nocscopetag

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

    nn <silent> <M-l> :execute '! xdg-open $(echo https://github.com/omnisci/omniscidb-internal/blob/$(git rev-parse --abbrev-ref HEAD)/' . @% . '\#L' . line(".") . ')'<cr>

    nn <silent> <M-c> :sil execute '! echo $(readlink -f ' . @% . '):' . line(".") . ' \| tr -d "\n" \| xsel -ib'<cr>

    " fine-graned references, callee vs caller
    " caller
    nn <silent> <M-x>c :call CocLocations('ccls','$ccls/call')<cr>
    " callee
    nn <silent> <M-x>C :call CocLocations('ccls','$ccls/call',{'callee':v:true})<cr>

    " Use <cr> to confirm completion, `<C-g>u` means break undo chain at current
    " position. Coc only does snippet and additional edit on confirm.
    if has('patch8.1.1068')
      " Use `complete_info` if your (Neo)Vim version supports it.
      inoremap <expr> <cr> complete_info()["selected"] != "-1" ? "\<C-y>" : "\<C-g>u\<CR>"
    else
      imap <expr> <cr> pumvisible() ? "\<C-y>" : "\<C-g>u\<CR>"
    endif

    function! HelpWithFocus()
      call CocAction('doHover')
      call coc#util#float_jump()
    endfunction
    nn <silent> K :call HelpWithFocus()<cr>

    nnoremap <expr><down> coc#util#has_float() ? coc#util#float_scroll(1) : "\<down>"
    nnoremap <expr><up> coc#util#has_float() ? coc#util#float_scroll(0) : "\<up>"

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
         w! /tmp/nvim-git-diff.tmp
       endif
    endfunction

    function GitDiffWin(base)
       if filereadable(@%)
         wincmd n
         execute 'r!git show ' . trim(a:base) . ':' . trim(bufname(winbufnr(winnr('#'))))
         set ft=cpp
         normal ggdd
         w! /tmp/nvim-git-show.tmp
         wincmd H
         execute 'windo diffthis'
       endif
    endfunction

    nmap <M-g> :call GitDiff("")<cr>
    nmap <M-G> :call GitDiff("origin/HEAD")<cr>

    nmap <M-f> :call GitDiffWin("")<cr>
    nmap <M-F> :call GitDiffWin("origin/HEAD")<cr>

    nmap <C-q> :bd<cr>:bd<cr>

    function GitBlame()
       if filereadable(@%)
         wincmd n
         r!git blame #
         set ft=cpp
         normal ggdd
         w! /tmp/nvim-git-blame.tmp
       endif
    endfunction

    nmap <M-h> :call GitBlame()<cr>

    function FifoMake()
      call system('echo make > /tmp/fifo')
    endfunction

    nmap <M-k> :call FifoMake()<cr>

    let &gp="rg -n $* /dev/null"

endif

"filetype plugin indent on

" In the quickfix window, <CR> is used to jump to the error under the
" cursor, so undefine the mapping there.
autocmd BufReadPost quickfix nnoremap <buffer> <CR> <CR>

set previewheight=60
au BufEnter ?* call PreviewHeightWorkAround()
func PreviewHeightWorkAround()
    if &previewwindow
        exec 'setlocal winheight='.&previewheight
    else
        exec 'setlocal winheight=1'
    endif
endfunc

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"" COLORS AND DISPLAY:
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
set termguicolors
colorscheme onedark

set statusline=%t[%{strlen(&fenc)?&fenc:'none'},%{&ff}]%h%m%r%y%=%c,%l/%L\ %P

hi TagbarVisibilityProtected guifg=orange 
hi StatusLine guifg=#282c34 guibg=#abb2bf
hi StatusLineNC guifg=#abb2bf guibg=#4b5263


"If the Pmenu is messed up try setting colors manually:
"highlight PMenuSel cterm=bold ctermbg=Green ctermfg=None
