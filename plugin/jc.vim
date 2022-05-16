if exists('g:loaded_jc_nvim') | finish | endif
let g:loaded_jc_nvim = v:true


command! JCdebugAttach lua require('jc.vimspector').debug_attach()
command! JCdebugLaunch lua require('jc.vimspector').debug_launch()
