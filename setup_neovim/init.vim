"Ensure clipboard works with vimx
set clipboard=unnamed

"Only use base dir tags
set tags=./tags;
function! FindNearestTagsFile()
  let l:dir = expand('%:p:h')
  let l:pwd = getcwd()
  while 1
    if filereadable(l:dir . '/tags')
      return l:dir . '/tags'
    endif
    if l:dir ==# l:pwd || l:dir ==# '/'
      break
    endif
    let l:dir = fnamemodify(l:dir, ':h')
  endwhile
  " fallback: use tags in current working dir if found
  if filereadable(l:pwd . '/tags')
    return l:pwd . '/tags'
  endif
  return ''
endfunction

autocmd BufEnter * let &tags = FindNearestTagsFile()

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
    Plug 'neoclide/coc.nvim', { 'branch': 'release' }
    Plug 'vim-scripts/a.vim'
    Plug 'vvhitedog/tagbar'
    Plug 'jremmen/vim-ripgrep'
    Plug 'sjl/vitality.vim'
    Plug 'Yggdroot/LeaderF', { 'do': ':LeaderfInstallCExtension' }
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

" Check that we are not in diff or preview window modes
if !&diff && !&pvw 

    " remap method jumps to bring you to the function name instead of brackets
    nnoremap [m [m{jf(b
    nnoremap ]m }]m{jf(b

    " Format using clang
    inoremap <F7> <Esc> :%!clang-format <CR>
    nnoremap <F7>  :%!clang-format <CR>

    nmap <silent> <C-l> :TagbarClose<cr><Plug>(coc-declaration)
    nmap <silent> <C-j> :TagbarClose<cr><Plug>(coc-definition)
    nmap <silent> <C-k> :TagbarClose<cr><Plug>(coc-references)
    nnoremap <silent> <C-M-j> :TagbarClose<cr>:call CocAction('jumpImplementation')<CR>

    nnoremap <silent> <M-m> :CocList outline<cr>


    nn <silent> <M-l> :Leaderf line --fuzzy<cr>
    nn <silent> <M-r> :Leaderf rg --fuzzy<cr>


    nmap <silent> <M-n> :LfTagIncremental<cr>
    nmap <silent> <C-n> :CocList symbols<cr>
    nmap <silent> <C-h> :CocList --interactive symbols -kind class<cr>
    nmap <silent> <C-f> :Leaderf file --no-ignore --fuzzy<cr>
    nmap <silent> <C-M-f> :Leaderf! file --no-ignore --fuzzy<cr>
    nmap <silent> <C-g> :Leaderf mru --fuzzy<cr>

    function! OpenGithubUrl(branch)
      " Get repo remote URL
      let l:remote = system('git remote get-url origin')
      let l:remote = substitute(l:remote, '\n', '', 'g')
      let l:url = l:remote

      " handle git@github.com:org/repo.git
      let l:url = substitute(l:url, '^git@github.com:', 'https://github.com/', '')
      " handle https://github.com/org/repo.git
      let l:url = substitute(l:url, '\.git$', '', '')

      " Repo root and relative file path
      let l:root = substitute(system('git rev-parse --show-toplevel'), '\n', '', 'g')
      let l:file = expand('%:p')
      let l:file = substitute(l:file, l:root . '/', '', '')

      " Line number
      let l:line = line('.')

      " Use given branch or fallback to current branch
      if a:branch == ''
        let l:branch = substitute(system('git rev-parse --abbrev-ref HEAD'), '\n', '', 'g')
      else
        let l:branch = a:branch
      endif

      " Build final URL
      let l:ghurl = l:url . '/blob/' . l:branch . '/' . l:file . '#L' . l:line

      " Open in browser
      call jobstart(['xdg-open', l:ghurl])
    endfunction

    " Map Meta-v to current branch
    nnoremap <silent> <M-v> :call OpenGithubUrl('')<CR>

    " Map Meta-V to master branch
    nnoremap <silent> <M-V> :call OpenGithubUrl('master')<CR>

    nn <silent> <M-c> :sil execute '! echo $(readlink -f ' . @% . '):' . line(".") . ' \| tr -d "\n" \| xsel -ib'<cr>

    function! HelpWithFocus()
      call CocAction('doHover')
    endfunction
    nn <silent> K :call HelpWithFocus()<cr>

    inoremap <silent><expr> <c-space> coc#refresh()

    " Symbol renaming.
    nmap <leader>r <Plug>(coc-rename)

    " help with view diffs 
    nmap <C-b> :pyf ~/.local/bin/git-diff3-view.py<cr>

    " Open outline tagbar
    nmap <M-o> :TagbarOpen j<cr>:TagbarOpen j<cr>
    nmap <M-t> :TagbarToggle<cr>
    nmap <M-k> :TagbarClose <cr>:CocOutline<cr>
    
    let g:tagbar_ctags_bin = expand('~/.local/bin/ctags')

    function! Scratch()
        wincmd n
        noswapfile hide enew
        setlocal buftype=nofile
        setlocal bufhidden=hide
    endfunction

    function! SetName(bufname)
      let bnr = bufnr(a:bufname)
      if bnr > 0
        execute 'silent! bd ' . bnr
      endif
      execute 'file ' . a:bufname
    endfunction


    function! ScratchNewTab()
        call Scratch()
        wincmd T
    endfunction

    function! ScratchThisTab()
        call Scratch()
        wincmd o
    endfunction


    function! GitDiffWin(base)
      if !filereadable(@%)
        return
      endif

      let l:bufname = expand('%')
      let l:thisft = &ft

      " Get name-status diff
      let l:ns_output = systemlist('git diff --name-status '.shellescape(a:base))

      let l:oldname = ''
      let l:is_added = v:false

      " Try to find original name or detect added files
      for line in l:ns_output
        let l:fields = split(line, '\t')
        if len(l:fields) == 2
          if l:fields[0] ==# 'M' && l:fields[1] ==# l:bufname
            let l:oldname = l:bufname
            break
          elseif l:fields[0] ==# 'A' && l:fields[1] ==# l:bufname
            let l:is_added = v:true
            break
          endif
        elseif len(l:fields) == 3 && l:fields[2] ==# l:bufname && l:fields[0] =~# '^R\d\+'
          let l:oldname = l:fields[1]
          break
        endif
      endfor

      " If the file was newly added, just show message and exit
      if l:is_added
        echohl WarningMsg
        echo '[GitDiffWin] File "' . l:bufname . '" was added; no diff available for '.a:base
        echohl None
        return
      endif

      " Fallback to current name if unchanged
      if l:oldname ==# ''
        let l:oldname = l:bufname
      endif

      " Open scratch and show old file content
      call Scratch()
      execute 'r!git show ' . trim(a:base) . ':' . fnameescape(l:oldname)
      let &ft = l:thisft
      normal! ggdd
      call SetName('[diffwin] ' . trim(a:base) . ':' . l:oldname)
      wincmd H
      execute 'windo diffthis'
    endfunction


    function! OpenFileAndGitDiffWin(base, ...) abort
      " Use provided base, or fall back to global
      let l:base = a:base !=# '' ? a:base : get(g:, 'diff_base', 'origin/HEAD')

      " Use provided comp_base if present, otherwise fall back to global
      let l:comp_base = (a:0 >= 1 && !empty(a:1)) ? a:1 : get(g:, 'diff_comp_base', '')

      wincmd gf

      if empty(l:comp_base)
        call GitDiffWin(l:base)
      else
        call GitDiffWin2(l:base, l:comp_base)
      endif
    endfunction


    function! GitDiffFiles(base)
      call ScratchThisTab()
      execute 'r!git diff --name-status ' . trim(a:base)
      set ft=git
      normal! ggdd
      call SetName('[filelist] ' . trim(a:base))
      wincmd H
      " Use global variable so other tabs/windows can access it
      let g:diff_base = a:base
      if exists('g:diff_comp_base')
        unlet g:diff_comp_base
      endif
    endfunction

    function! GitDiffFilesBetween(base, ...) abort
      let l:base = trim(a:base)
      let l:comp_base = (a:0 >= 1 && !empty(a:1)) ? trim(a:1) : l:base . '~1'

      call ScratchThisTab()
      let l:cmd = 'git diff --name-status ' . l:comp_base . '..' . l:base
      execute 'r!' . l:cmd
      set ft=git
      normal! ggdd
      call SetName('[filelist] ' . l:comp_base . '..' . l:base)
      wincmd H

      let g:diff_base = l:base
      let g:diff_comp_base = l:comp_base
    endfunction


    function! GenTags()
      execute '!ctags -R --append=yes --exclude=.git --exclude="*build*" --exclude="*frontend*" --exclude="*Test/FsiDataFiles*" --exclude=".ccls-cache" --exclude="docker" --exclude="FsiDataFiles" .'

      " Pretty success message with green color and checkmark
      echohl Question
      echon "✔ Tags updated successfully\n"
      echohl None
    endfunction


function! GenerateTagsIncrementally()
python3 << EOF
import os

print("🔍 Incremental tag generation...")

TAGS_FILE = 'tags'
LIST_FILE = 'list'
EXCLUDE_DIRS = ['.git', 'build', 'node_modules', '.ccls-cache', 'dist', '__pycache__', 'docker', 'FsiDataFiles', 'frontend', 'tag.ignore']

try:
    tags_mtime = os.stat(TAGS_FILE).st_mtime
except FileNotFoundError:
    tags_mtime = 0

with open(LIST_FILE, 'w') as fp:
    for dirpath, dirnames, filenames in os.walk(os.getcwd()):
        # Exclude directories that partially match any pattern
        dirnames[:] = [d for d in dirnames if not any(x in d for x in EXCLUDE_DIRS)]
        for filename in filenames:
            full_path = os.path.join(dirpath, filename)
            try:
                if os.stat(full_path).st_mtime > tags_mtime:
                    fp.write(full_path + '\n')
            except FileNotFoundError:
                continue

exit_code = os.system(
    'ctags --recurse --append --fields=+aimS --extras=+q '
    '--c-kinds=+p --c++-kinds=+p -L ' + LIST_FILE
)

os.remove(LIST_FILE)

if exit_code == 0:
    print("✔ Tags updated incrementally.")
else:
    print("✘ ctags failed.")

EOF
endfunction

command! GenerateTagsIncrementally call GenerateTagsIncrementally()

command! LfTagIncremental call GenerateTagsIncrementally() | Leaderf tag

    let g:Lf_AutoUpdateTags = v:true


    function! LeaderfTagWithOptionalUpdate()
      if get(g:, 'Lf_AutoUpdateTags', v:false)
        call GenTags()
      endif
      Leaderf! tag
    endfunction

    command! ToggleAutoTagUpdate let g:Lf_AutoUpdateTags = !get(g:, 'Lf_AutoUpdateTags', v:false) | echo "Auto tag update: " . (g:Lf_AutoUpdateTags ? "ON ✔" : "OFF ✘")

    command! LfTag call LeaderfTagWithOptionalUpdate()

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

    function RipgrepDefaultIgnore(...) 
      let s:to_exec='Rg -i -g "!tags" -g "!compile_commands.json" -g "!build*"'
      let s:regex = a:000[0]
      for i in range(a:0)
        if i > 0
          let s:to_exec= s:to_exec . ' -g "' . a:000[i]  . '"'
        endif
      endfor
      let s:to_exec = s:to_exec . ' "' . s:regex .  '"'
      " useful to echo for debugging
      echo s:to_exec 
      execute s:to_exec
    endfunction

    command! -nargs=* Ri call RipgrepDefaultIgnore(<f-args>)

    function RipgrepDefault(arg) 
      execute 'Rg -i -g "!tags" -g "!compile_commands.json" -g "!build*" "'  . a:arg . '"'
    endfunction

    command! -nargs=1 R call RipgrepDefault(<f-args>)

    function RipgrepLocalDefault(arg) 
      execute 'Rg -i -g "!tags" -g "!compile_commands.json" -g "!build*" "' . a:arg . '" %'
    endfunction

    command! -nargs=1 Rh call RipgrepLocalDefault(<f-args>)

    function! GitDiffWin2(base1, base2) abort
      if !filereadable(@%)
        return
      endif

      let l:old_more = &more
      set nomore

      try
        let l:bufname = expand('%')
        let l:thisft = &ft
        let l:oldname1 = ''
        let l:oldname2 = ''
        let l:is_added2 = v:false

        let l:ns_output = systemlist('git diff --name-status ' . shellescape(a:base1 . '..' . a:base2))

        for line in l:ns_output
          let l:fields = split(line, '\t')
          if len(l:fields) == 2
            if l:fields[0] ==# 'M' && l:fields[1] ==# l:bufname
              let l:oldname1 = l:bufname
              let l:oldname2 = l:bufname
              break
            elseif l:fields[0] ==# 'A' && l:fields[1] ==# l:bufname
              let l:is_added2 = v:true
              break
            endif
          elseif len(l:fields) == 3 && l:fields[2] ==# l:bufname && l:fields[0] =~# '^R\d\+'
            let l:oldname1 = l:fields[1]
            let l:oldname2 = l:bufname
            break
          endif
        endfor

        if l:is_added2
          echohl WarningMsg
          echo '[GitDiffWin2] File "' . l:bufname . '" was added in ' . a:base2 . '; no diff available in ' . a:base1
          echohl None
          return
        endif

        if l:oldname1 ==# ''
          let l:oldname1 = l:bufname
          let l:oldname2 = l:bufname
        endif

        call Scratch()
        silent execute 'r!git show ' . shellescape(a:base1 . ':' . l:oldname1)
        let &ft = l:thisft
        normal! ggdd
        call SetName('[diffwin2] ' . a:base1 . ':' . l:oldname1)
        wincmd H
        wincmd w

        call Scratch()
        silent execute 'r!git show ' . shellescape(a:base2 . ':' . l:oldname2)
        let &ft = l:thisft
        normal! ggdd
        call SetName('[diffwin2] ' . a:base2 . ':' . l:oldname2)
        wincmd H
        wincmd w

        execute 'windo diffthis'
      finally
        let &more = l:old_more
      endtry
    endfunction

    nmap <leader>qf <Plug>(coc-fix-current)

    nmap <M-f> :call GitDiffWin("")<cr>
    nmap <M-F> :call GitDiffWin("origin/HEAD")<cr>

    nmap <M-s> :call OpenFileAndGitDiffWin("")<cr>
    nmap <M-S> :call OpenFileAndGitDiffWin("origin/HEAD")<cr>

    nmap <M-z> :call GitDiffFiles("HEAD")<cr>
    nmap <M-Z> :call GitDiffFiles("origin/HEAD")<cr>

    nmap <C-q> :tabclose<cr>

    function GitBlame()
       if filereadable(@%)
         let thisft = &ft
         let lineno = line('.')
         call Scratch()
         r!git blame #
         let &ft=thisft
         normal ggdd
         call SetName('[blame] ' . trim(bufname(winbufnr(winnr('#')))))
         execute 'normal ' . lineno . 'G'
       endif
    endfunction

    nmap <M-h> :call GitBlame()<cr>

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

    nmap <A-j> :Leaderf buffer<cr>
    imap <A-j> <ESC>:Leaderf buffer<cr>
    vmap <A-j> <ESC>:Leaderf buffer<cr>
    tmap <A-j> <C-\><C-n>:Leaderf buffer<cr>

    nmap <C-x><C-x> :Leaderf window<cr>
    imap <C-x><C-x> <ESC>:Leaderf window<cr>
    vmap <C-x><C-x> <ESC>:Leaderf window<cr>
    tmap <C-x><C-x> <C-\><C-n>:Leaderf window<cr>

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
                "let file = fnamemodify(file, ':p:t')
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

" colorcolumn
set colorcolumn=80
:let g:python_recommended_style = 0

set cursorline

" helps visualize active windows
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

let g:coc_global_extensions = ['coc-json', 'coc-tsserver', 'coc-clangd', 'coc-pyright']
autocmd FileType java call CocActionAsync('runCommand', 'extension.coc-java.activate')
