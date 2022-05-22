if exists('g:loaded_jc_nvim') | finish | endif
let g:loaded_jc_nvim = v:true


command! JCdebugAttach lua require('jc.vimspector').debug_attach()
command! JCdebugLaunch lua require('jc.vimspector').debug_launch()
command! JCdebugWithConfig lua require('jc.vimspector').debug_choose_configuration()
command! JCdebugWithConfig lua require('jc.vimspector').debug_choose_configuration()
command! JCimportsOrganize lua require('jc.jdtls').organize_imports()
command! JCgenerateToString lua require('jc.jdtls').generate_toString()
