if exists('g:loaded_jc_nvim') | finish | endif
let g:loaded_jc_nvim = v:true

let g:JavaComplete_Home = fnamemodify(expand('<sfile>'), ':p:h:h:gs?\\?'. g:FILE_SEP. '?')

autocmd FileType java autocmd BufWrite * lua vim.lsp.buf.format({ async = false })

command! JCdebugAttach lua require('jc.vimspector').debug_attach()
command! JCdebugLaunch lua require('jc.vimspector').debug_launch()
command! JCdebugWithConfig lua require('jc.vimspector').debug_choose_configuration()
command! JCdebugWithConfig lua require('jc.vimspector').debug_choose_configuration()
command! JCimportsOrganize lua require('jc.jdtls').organize_imports()
command! JCgenerateToString lua require('jc.jdtls').generate_toString()
command! JCgenerateHashCodeAndEquals lua require('jc.jdtls').generate_hashCodeAndEquals()
command! JCgenerateAccessors lua require('jc.jdtls').generate_accessors()
command! JCgenerateAccessorGetter lua require('jc.jdtls').generate_accessor('g')
command! JCgenerateAccessorSetter lua require('jc.jdtls').generate_accessor('s')
command! JCgenerateAccessorSetterGetter lua require('jc.jdtls').generate_accessor('sg')
command! JCgenerateConstructorDefault lua require('jc.jdtls').generate_constructor(nil, nil, {default = true})
command! JCgenerateConstructor lua require('jc.jdtls').generate_constructor(nil, nil, {default = false})
command! JCgenerateAbstractMethods lua require('jc.jdtls').generate_abstractMethods()
command! JCgenerateClass lua require('jc.class_generator').generate_class()
