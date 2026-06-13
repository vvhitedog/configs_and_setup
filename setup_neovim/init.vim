"Ensure clipboard works with vimx
set clipboard=unnamed

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
    Plug 'Makaze/AnsiEsc'
    Plug 'm00qek/baleia.nvim'
    Plug 'm-pilia/vim-ccls'

endif

" These are colorschemes so okay to have in diff
Plug 'morhetz/gruvbox'
Plug 'tyrannicaltoucan/vim-quantum'
Plug 'joshdick/onedark.vim'
Plug 'bfrg/vim-cpp-modern'
Plug 'ryanoasis/vim-devicons' " installs icons for plugins to use

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

" ============================
" Integrate LeaderF with CoC
" ============================
" Enable popup preview
let g:Lf_PreviewInPopup = 1
"let g:Lf_WindowPosition = 'popup'
let g:Lf_HideHelp = 1

" Check that we are not in diff or preview window modes
if !&diff && !&pvw 

    " remap method jumps to bring you to the function name instead of brackets
    nnoremap [m [m{jf(b
    nnoremap ]m }]m{jf(b

    " Format using clang
    inoremap <F7> <Esc> :%!clang-format <CR>
    nnoremap <F7>  :%!clang-format <CR>


    " Use  CoC built-in functionality (as opposed to leaderf below)
    nmap <silent> <C-l> :TagbarClose<cr><Plug>(coc-declaration)
    nmap <silent> <C-j> :TagbarClose<cr><Plug>(coc-definition)
    "nmap <silent> <C-k> :TagbarClose<cr><Plug>(coc-references)
    nnoremap <silent> <M-m> :CocList outline<cr>
    nmap <silent> <C-n> :CocList symbols<cr>

    " Use tagls for symbols
    nmap <silent> <M-n> :Tagls<cr>
    nmap <silent> <M-i> :TaglsAt<cr>
    nmap <silent> <M-u> :TaglsRef<cr>

    " Use Leaderf for some functionality if its slicker
    " necessary due to how slow CoC is) Note, the integration is worse.
    "nmap <silent> <C-l> :TagbarClose<cr>:Leaderf! coc declarations --auto-jump <CR>
    "nmap <silent> <C-j> :TagbarClose<cr>:Leaderf! coc definitions --auto-jump<CR>
    nmap <silent> <C-k> :TagbarClose<cr>:Leaderf! coc references <CR>
    "nmap <silent> <C-t> :TagbarClose<cr>:Leaderf! coc typeDefinitions<CR>

    nnoremap <silent> <C-M-j> :TagbarClose<cr>:call CocAction('jumpImplementation')<CR>



    nn <silent> <M-l> :Leaderf line --regexMode<cr>
    nn <silent> <M-r> :Leaderf rg --regexMode<cr>


    "nmap <silent> <C-h> :CocList --interactive symbols -kind class<cr>
    nmap <silent> <C-f> :Leaderf file --no-ignore --regexMode<cr>
    nmap <silent> <C-M-f> :Leaderf! file --no-ignore --regexMode<cr>
    nmap <silent> <C-g> :Leaderf mru --regexMode<cr>

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


    " --- Git diff range plumbing -------------------------------------------
    " Parse a git range string ("A..B", "A...B", or "A") into components.
    " An empty side means "working tree" (the file on disk, editable).
    function! s:ParseDiffRange(range) abort
      let r = trim(a:range)
      if r =~# '\.\.\.'
        let parts = split(r, '\.\.\.', 1)
        return {'left': trim(get(parts, 0, '')), 'right': trim(get(parts, 1, '')),
              \ 'sep': '...', 'range': r}
      elseif r =~# '\.\.'
        let parts = split(r, '\.\.', 1)
        return {'left': trim(get(parts, 0, '')), 'right': trim(get(parts, 1, '')),
              \ 'sep': '..', 'range': r}
      else
        return {'left': r, 'right': '', 'sep': '', 'range': r}
      endif
    endfunction

    " For 3-dot ranges, the effective left side for per-file diff is the
    " merge-base of left and right.
    function! s:ResolveLeftRef(info) abort
      if a:info.sep ==# '...' && !empty(a:info.left)
        let l:other = empty(a:info.right) ? 'HEAD' : a:info.right
        let l:mb = systemlist('git merge-base ' . shellescape(a:info.left) . ' ' . shellescape(l:other))
        if v:shell_error == 0 && len(l:mb) > 0 && !empty(l:mb[0])
          return trim(l:mb[0])
        endif
      endif
      return a:info.left
    endfunction

    function! s:ShortRef(ref) abort
      if empty(a:ref) | return '<wt>' | endif
      if a:ref =~# '^[0-9a-f]\{20,\}$' | return strpart(a:ref, 0, 7) | endif
      return a:ref
    endfunction

    " Replace current window's buffer with a read-only scratch holding
    " `git show <ref>:<file>`.
    function! s:LoadRefIntoCurrentWindow(ref, filename, ft) abort
      enew
      setlocal buftype=nofile bufhidden=wipe noswapfile
      silent execute 'r!git show ' . shellescape(a:ref . ':' . a:filename)
      let &ft = a:ft
      normal! ggdd
      setlocal readonly nomodifiable
      call SetName('[' . s:ShortRef(a:ref) . '] ' . fnamemodify(a:filename, ':t'))
    endfunction

    " Per-window statusline indicating "this is the working tree (editable)".
    function! s:MarkWorkingTreeWindow() abort
      setlocal statusline=[working\ tree]\ %f\ %=%y\ %r%m
    endfunction

    " Open a TRUE 2-way diff for the current buffer's file at left_ref vs
    " right_ref. Empty ref means working tree (disk file, RW). The other
    " side is always RO.
    " Pre: current window has the disk file open (e.g. via 'wincmd gf').
    function! s:GitDiff2Way(left_ref, right_ref) abort
      if !filereadable(@%) | return | endif
      if empty(a:left_ref) && empty(a:right_ref)
        echohl WarningMsg | echo '[GitDiff] both refs empty; nothing to diff' | echohl None
        return
      endif

      let l:filename = expand('%')
      let l:thisft = &ft
      let l:left_label  = s:ShortRef(a:left_ref)
      let l:right_label = s:ShortRef(a:right_ref)

      " Right side = current window. Replace with scratch unless right is wt.
      if empty(a:right_ref)
        call s:MarkWorkingTreeWindow()
      else
        call s:LoadRefIntoCurrentWindow(a:right_ref, l:filename, l:thisft)
      endif

      " Left side = new window on the left.
      if empty(a:left_ref)
        execute 'leftabove vsplit ' . fnameescape(l:filename)
        call s:MarkWorkingTreeWindow()
      else
        leftabove vnew
        call s:LoadRefIntoCurrentWindow(a:left_ref, l:filename, l:thisft)
      endif

      windo diffthis
      redraw
      echohl ModeMsg
      echo '[GitDiff] ' . l:left_label . '  <->  ' . l:right_label . '   :  ' . fnamemodify(l:filename, ':t')
      echohl None
    endfunction

    " --- Public entry points -----------------------------------------------
    " Open file under cursor and 2-way diff it for the active range.
    " Argument is a git range string ("A..B", "A...B", "A"); empty falls back
    " to the global g:diff_range_info set by GitDiffFilesBetween / GitDiffFiles.
    function! OpenFileAndGitDiffWin(range, ...) abort
      let l:info = !empty(a:range) ? s:ParseDiffRange(a:range)
                              \ : get(g:, 'diff_range_info', {})
      if empty(l:info)
        echohl WarningMsg | echo '[GitDiff] no range set; run :call GitDiffFilesBetween("A..B") first' | echohl None
        return
      endif
      wincmd gf
      let l:left_ref = s:ResolveLeftRef(l:info)
      let l:right_ref = l:info.right
      call s:GitDiff2Way(l:left_ref, l:right_ref)
    endfunction


    function! GitDiffFiles(base)
      call GitDiffFilesBetween(a:base)
    endfunction

    " Show changed files for a git range string. Accepts:
    "   "A..B"   — git diff --name-status A..B
    "   "A...B"  — git diff --name-status A...B
    "   "A"      — git diff --name-status A   (A vs working tree)
    function! GitDiffFilesBetween(range) abort
      let l:info = s:ParseDiffRange(a:range)
      call ScratchThisTab()
      execute 'r!git diff --name-status ' . l:info.range
      set ft=git
      normal! ggdd
      let l:title = '[filelist] ' . s:ShortRef(l:info.left)
            \ . (empty(l:info.sep) ? '' : (l:info.sep . s:ShortRef(l:info.right)))
      call SetName(l:title)
      wincmd H

      let g:diff_range_info = l:info
      " Backward-compat globals (some older callers may still read these).
      let g:diff_base = empty(l:info.right) ? l:info.left : l:info.right
      if !empty(l:info.left) && !empty(l:info.right)
        let g:diff_comp_base = l:info.left
      elseif exists('g:diff_comp_base')
        unlet g:diff_comp_base
      endif
    endfunction


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

    " GitDiffWin2 — kept for backward-compat with any older callers.
    " Now performs a TRUE 2-way diff via s:GitDiff2Way (was previously 3-way).
    function! GitDiffWin2(left_ref, right_ref) abort
      call s:GitDiff2Way(a:left_ref, a:right_ref)
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


" Normal bg
hi Normal guibg=#1b2128
" helps visualize active windows
" Temporarily disabled: pane switching in tmux fires FocusLost/FocusGained
" and changing Normal.guibg makes Neovim flash/jump visually.
"autocmd FocusLost * hi Normal guibg=#0e191f
"autocmd FocusGained * hi Normal guibg=#1b2128


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

"au termopen * cnoremap <silent> q<cr> call ConfirmQuit(0)<cr>
"au termenter * cnoremap <silent> q<cr> call ConfirmQuit(0)<cr>
"au termleave * cnoremap <silent> q<cr> call ConfirmQuit(0)<cr>
"au termopen * cnoremap <silent> qa<cr> call ConfirmQuit(1)<cr>
"au termenter * cnoremap <silent> qa<cr> call ConfirmQuit(1)<cr>
"au termleave * cnoremap <silent> qa<cr> call ConfirmQuit(1)<cr>

"let g:coc_global_extensions = ['coc-json', 'coc-tsserver', 'coc-clangd', 'coc-pyright']
let g:coc_global_extensions = ['coc-json', 'coc-tsserver', 'coc-pyright']
"autocmd FileType java call CocActionAsync('runCommand', 'extension.coc-java.activate')

" =========================================================================================
" keymap-cheatsheet.nvim (descriptions without rewriting mappings)
" =========================================================================================
if !exists('g:keymap_cheatsheet_desc')
  let g:keymap_cheatsheet_desc = {}
endif

if !has_key(g:keymap_cheatsheet_desc, 'n') | let g:keymap_cheatsheet_desc.n = {} | endif
call extend(g:keymap_cheatsheet_desc.n, {
\ '<leader>y': 'Yank into register 0 (preserve last yank)',
\ '<leader>p': 'Paste from register 0 (preserve last yank)',
\ '[m': 'Jump to previous method/function name',
\ ']m': 'Jump to next method/function name',
\ '<F7>': 'Format buffer through clang-format',
\ '<C-l>': 'Go to declaration (close Tagbar first)',
\ '<C-j>': 'Go to definition (close Tagbar first)',
\ '<C-k>': 'Find references (LeaderF + CoC; close Tagbar first)',
\ '<C-M-j>': 'Jump to implementation (close Tagbar first)',
\ '<M-m>': 'Outline list (CocList outline)',
\ '<C-n>': 'Workspace symbols (CocList symbols)',
\ '<M-l>': 'Search lines in current buffer (LeaderF line)',
\ '<M-r>': 'Ripgrep project search (LeaderF rg)',
\ '<C-f>': 'Find files (LeaderF file, includes ignored)',
\ '<C-M-f>': 'Find files (LeaderF file, fullscreen, includes ignored)',
\ '<C-g>': 'Recent files (LeaderF mru)',
\ '<M-v>': 'Open current file on GitHub at cursor line (current branch)',
\ '<M-V>': 'Open current file on GitHub at cursor line (master branch)',
\ '<M-c>': 'Copy absolute path:line to clipboard',
\ 'K': 'Show hover documentation (CoC)',
\ '<leader>r': 'Rename symbol (CoC)',
\ '<leader>qf': 'Quickfix current issue (CoC)',
\ '<C-b>': 'Open 3-way git diff viewer for current file',
\ '<M-o>': 'Open Tagbar outline',
\ '<M-t>': 'Toggle Tagbar',
\ '<M-k>': 'Close Tagbar and open CoC outline',
\ '<M-f>': 'Diff current file vs default base (GitDiffWin)',
\ '<M-F>': 'Diff current file vs origin/HEAD (GitDiffWin)',
\ '<M-s>': 'Open file under cursor and 2-way diff for active range',
\ '<M-S>': 'Open file under cursor and 2-way diff vs origin/HEAD',
\ '<M-z>': 'List changed files vs HEAD (working tree)',
\ '<M-Z>': 'List changed files vs origin/HEAD (working tree)',
\ '<M-h>': 'Git blame in a scratch window',
\ '<M-1>': 'Go to tab 1',
\ '<M-2>': 'Go to tab 2',
\ '<M-3>': 'Go to tab 3',
\ '<M-4>': 'Go to tab 4',
\ '<M-5>': 'Go to tab 5',
\ '<M-6>': 'Go to tab 6',
\ '<M-7>': 'Go to tab 7',
\ '<M-8>': 'Go to tab 8',
\ '<M-9>': 'Go to tab 9',
\ '<C-s>': 'Cycle to previous tab (g<Tab>)',
\ '<C-a>': 'Escape / leave current mode',
\ '<A-j>': 'Open buffer switcher (LeaderF buffer)',
\ '<C-x><C-x>': 'Open window picker (LeaderF window)',
\ '<M-]>': 'Preview tag under cursor in preview window',
\ '<C-q>': 'Close current tab',
\ }, 'keep')

if !has_key(g:keymap_cheatsheet_desc, 'i') | let g:keymap_cheatsheet_desc.i = {} | endif
call extend(g:keymap_cheatsheet_desc.i, {
\ '<CR>': 'Confirm completion if menu visible, otherwise insert newline (CoC)',
\ '<Tab>': 'Next completion item if menu visible, otherwise Tab (CoC)',
\ '<S-Tab>': 'Previous completion item if menu visible (CoC)',
\ '<c-space>': 'Trigger completion refresh (CoC)',
\ '<F7>': 'Format buffer through clang-format',
\ '<M-1>': 'Go to tab 1',
\ '<M-2>': 'Go to tab 2',
\ '<M-3>': 'Go to tab 3',
\ '<M-4>': 'Go to tab 4',
\ '<M-5>': 'Go to tab 5',
\ '<M-6>': 'Go to tab 6',
\ '<M-7>': 'Go to tab 7',
\ '<M-8>': 'Go to tab 8',
\ '<M-9>': 'Go to tab 9',
\ '<C-s>': 'Cycle to previous tab (g<Tab>)',
\ '<C-a>': 'Escape to normal mode',
\ '<A-j>': 'Open buffer switcher (LeaderF buffer)',
\ '<C-x><C-x>': 'Open window picker (LeaderF window)',
\ }, 'keep')

if !has_key(g:keymap_cheatsheet_desc, 'v') | let g:keymap_cheatsheet_desc.v = {} | endif
call extend(g:keymap_cheatsheet_desc.v, {
\ '<leader>y': 'Yank selection into register 0 (preserve last yank)',
\ '<leader>p': 'Paste from register 0 (preserve last yank)',
\ '<M-1>': 'Go to tab 1',
\ '<M-2>': 'Go to tab 2',
\ '<M-3>': 'Go to tab 3',
\ '<M-4>': 'Go to tab 4',
\ '<M-5>': 'Go to tab 5',
\ '<M-6>': 'Go to tab 6',
\ '<M-7>': 'Go to tab 7',
\ '<M-8>': 'Go to tab 8',
\ '<M-9>': 'Go to tab 9',
\ '<C-s>': 'Cycle to previous tab (g<Tab>)',
\ '<C-a>': 'Escape / leave visual mode',
\ '<A-j>': 'Open buffer switcher (LeaderF buffer)',
\ '<C-x><C-x>': 'Open window picker (LeaderF window)',
\ }, 'keep')

if !has_key(g:keymap_cheatsheet_desc, 'o') | let g:keymap_cheatsheet_desc.o = {} | endif
call extend(g:keymap_cheatsheet_desc.o, {
\ '<leader>y': 'Yank operator into register 0 (preserve last yank)',
\ '<leader>p': 'Paste from register 0 (preserve last yank)',
\ }, 'keep')

if !has_key(g:keymap_cheatsheet_desc, 't') | let g:keymap_cheatsheet_desc.t = {} | endif
call extend(g:keymap_cheatsheet_desc.t, {
\ '<M-1>': 'Go to tab 1 (leave terminal mode first)',
\ '<M-2>': 'Go to tab 2 (leave terminal mode first)',
\ '<M-3>': 'Go to tab 3 (leave terminal mode first)',
\ '<M-4>': 'Go to tab 4 (leave terminal mode first)',
\ '<M-5>': 'Go to tab 5 (leave terminal mode first)',
\ '<M-6>': 'Go to tab 6 (leave terminal mode first)',
\ '<M-7>': 'Go to tab 7 (leave terminal mode first)',
\ '<M-8>': 'Go to tab 8 (leave terminal mode first)',
\ '<M-9>': 'Go to tab 9 (leave terminal mode first)',
\ '<C-s>': 'Cycle to previous tab (g<Tab>; leave terminal mode first)',
\ '<C-a>': 'Leave terminal mode',
\ '<A-j>': 'Open buffer switcher (LeaderF buffer)',
\ '<C-x><C-x>': 'Open window picker (LeaderF window)',
\ }, 'keep')

if !has_key(g:keymap_cheatsheet_desc, 'c') | let g:keymap_cheatsheet_desc.c = {} | endif
call extend(g:keymap_cheatsheet_desc.c, {
\ 'q<cr>': 'Confirm quit when terminals may be open',
\ 'qa<cr>': 'Confirm quit-all when terminals may be open',
\ }, 'keep')

lua << EOF
local ok, gdf = pcall(require, "gitdiffiles")
if ok then
  gdf.setup({
    log_max = 0,
    diff_mode = "pr",
    ui = { file_width = 50, open_in_tab = false },
    keys = {
      open = "<CR>",
      refresh = "r",
      quit = "q",
      set_source = "s",
      set_target = "t",
      toggle_mode = "m",
    },
  })
end


local tsxref = vim.fn.expand("~/.local/bin/tsxref")
if vim.fn.executable(tsxref) ~= 1 then
  tsxref = vim.fn.expand("~/software/tsxref/build/tsxref")
end

if vim.fn.executable(tsxref) == 1 then
  vim.api.nvim_create_autocmd("FileType", {
    pattern = { "c", "cpp" },
    callback = function(args)
      -- vim.fs.root is 0.10+; on 0.9.5 derive the root from find+dirname.
      -- The server also checks <root>/build/compile_commands.json itself.
      local found = vim.fs.find(
        { "compile_commands.json", ".git" },
        { upward = true, path = vim.api.nvim_buf_get_name(args.buf) }
      )[1]
      local root = found and vim.fs.dirname(found) or vim.fn.getcwd()
      vim.lsp.start({
        name = "tsxref",
        cmd = { tsxref, "lsp" },
        root_dir = root,
      })
    end,
  })
end

EOF

