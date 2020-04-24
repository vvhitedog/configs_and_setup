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
    Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
    Plug 'junegunn/fzf.vim'
    Plug 'vim-scripts/a.vim'
endif

" These are colorschemes so okay to have in diff
Plug 'morhetz/gruvbox'
Plug 'tyrannicaltoucan/vim-quantum'
Plug 'joshdick/onedark.vim'
Plug 'bfrg/vim-cpp-modern'

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


function! FloatScroll(forward) abort
  let float = coc#util#get_float()
  if !float | return '' | endif
  let buf = nvim_win_get_buf(float)
  let buf_height = nvim_buf_line_count(buf)
  let win_height = nvim_win_get_height(float)
  if buf_height < win_height | return '' | endif
  let pos = nvim_win_get_cursor(float)
  if a:forward
    if pos[0] == 1
      let pos[0] += 3 * win_height / 4
    elseif pos[0] + win_height / 2 + 1 < buf_height
      let pos[0] += win_height / 2 + 1
    else
      let pos[0] = buf_height
    endif
  else
    if pos[0] == buf_height
      let pos[0] -= 3 * win_height / 4
    elseif pos[0] - win_height / 2 + 1  > 1
      let pos[0] -= win_height / 2 + 1
    else
      let pos[0] = 1
    endif
  endif
  call nvim_win_set_cursor(float, pos)
  return ''
endfunction

fun! ShowFuncName()
  return getline(search("^[^ \t#/]\\{2}.*[^:]\s*$", 'bWn'))
endfun

"fun! ShowFuncName()
"  let lnum = line(".")
"  let col = col(".")
"  echohl ModeMsg
"  echo getline(search("^[^ \t#/]\\{2}.*[^:]\s*$", 'bW'))
"  echohl None
"  call search("\\%" . lnum . "l" . "\\%" . col . "c")
"endfun

" Check that we are not in diff or preview window modes
if !&diff && !&pvw 

    " Jump to first tag
    set nocscopetag

    " F5: Find usages/occurrences using rg (r-grep)
    inoremap <expr> <F5>  "<Esc> :Rg ".expand('<cword>')."<CR>"
    nnoremap <expr> <F5> ":Rg ".expand('<cword>')."<CR>"

    " F4: Find usages/occurrences in current file using vim-grep
    inoremap <expr> <F4>  "<Esc> :lv /".expand('<cword>')."/j % \| :lwindow<CR>"
    nnoremap <expr> <F4> ":lv /".expand('<cword>')."/j % \| :lwindow<CR>"
    " Format using clang
    inoremap <F7> <Esc> :%!clang-format <CR>
    nnoremap <F7>  :%!clang-format <CR>

    nmap <silent> <C-l> <Plug>(coc-declaration)
    nmap <silent> <C-j> <Plug>(coc-definition)
    nmap <silent> <C-k> <Plug>(coc-references)
    nn <silent> K :call CocActionAsync('doHover')<cr>

    nmap <silent> <C-n> :CocList symbols<cr>
    nnoremap <silent> <C-m> :CocList outline<cr>
    nmap <silent> <C-h> :CocList --interactive symbols -kind class<cr>
    nmap <silent> <C-f> :CocList files<cr>

    " Use <cr> to confirm completion, `<C-g>u` means break undo chain at current
    " position. Coc only does snippet and additional edit on confirm.
    if has('patch8.1.1068')
      " Use `complete_info` if your (Neo)Vim version supports it.
      inoremap <expr> <cr> complete_info()["selected"] != "-1" ? "\<C-y>" : "\<C-g>u\<CR>"
    else
      imap <expr> <cr> pumvisible() ? "\<C-y>" : "\<C-g>u\<CR>"
    endif

		function! FloatScroll(forward) abort
			let float = coc#util#get_float()
			if !float | return '' | endif
			let buf = nvim_win_get_buf(float)
			let buf_height = nvim_buf_line_count(buf)
			let win_height = nvim_win_get_height(float)
			if buf_height < win_height | return '' | endif
			let pos = nvim_win_get_cursor(float)
			if a:forward
				if pos[0] == 1
					let pos[0] += 3 * win_height / 4
				elseif pos[0] + win_height / 2 + 1 < buf_height
					let pos[0] += win_height / 2 + 1
				else
					let pos[0] = buf_height
				endif
			else
				if pos[0] == buf_height
					let pos[0] -= 3 * win_height / 4
				elseif pos[0] - win_height / 2 + 1  > 1
					let pos[0] -= win_height / 2 + 1
				else
					let pos[0] = 1
				endif
			endif
			call nvim_win_set_cursor(float, pos)
			return ''
		endfunction

		inoremap <silent><expr> <down> coc#util#has_float() ? FloatScroll(1) : "\<down>"
		inoremap <silent><expr>  <up>  coc#util#has_float() ? FloatScroll(0) :  "\<up>"

    nnoremap <expr><down> coc#util#has_float() ? coc#util#float_scroll(1) : "\<down>"
    nnoremap <expr><up> coc#util#has_float() ? coc#util#float_scroll(0) : "\<up>"

    inoremap <silent><expr> <c-space> coc#refresh()

    " Symbol renaming.
    nmap <leader>r <Plug>(coc-rename)

    " coc rename is rather broken, use clang-rename.py instead:
    "noremap <leader>cr :pyf ~/.local/bin/clang-rename.py<cr>

endif

"inoremap <F8> <Esc> :setlocal winheight=60 <CR>
"nnoremap <F8>  :setlocal winheight=60 <CR>

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

autocmd FileType cpp :setlocal statusline=%t[%{strlen(&fenc)?&fenc:'none'},%{&ff}]%h%m%r%y[%{ShowFuncName()}]%=%c,%l/%L\ %P

set statusline=%t[%{strlen(&fenc)?&fenc:'none'},%{&ff}]%h%m%r%y%=%c,%l/%L\ %P
"set statusline+=%{ShowFuncName()}
"if &filetype == 'cpp'
"  set statusline+=%=%{ShowFuncName()}
"endif
"set statusline+=%t[%{strlen(&fenc)?&fenc:'none'},%{&ff}]%h%m%r%y%=%c,%l/%L\ %P
"set statusline+=%=%c,%l/%L\ %P
set statusline+=%c,%l/%L\ %P
hi StatusLine guifg=#282c34 guibg=#abb2bf
hi StatusLineNC guifg=#abb2bf guibg=#4b5263

"If the Pmenu is messed up try setting colors manually:
"highlight PMenuSel cterm=bold ctermbg=Green ctermfg=None
