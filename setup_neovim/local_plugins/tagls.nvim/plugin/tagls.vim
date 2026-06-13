if exists('g:loaded_tagls')
  finish
endif
let g:loaded_tagls = 1

command! TaglsBuild lua require('tagls').build()
command! TaglsInit lua require('tagls').init()
command! Tagls lua require('tagls').open()
command! TaglsRef lua require('tagls').open_ref()
command! TaglsAt lua require('tagls').open_at()
command! TaglsStop lua require('tagls').stop()
