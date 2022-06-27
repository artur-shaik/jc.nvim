if exists('g:loaded_jc_nvim') | finish | endif

let g:loaded_jc_nvim = v:true

let g:JavaComplete_Home = fnamemodify(expand('<sfile>'), ':p:h:h:gs?\\?'. g:utils#FILE_SEP. '?')

if has('nvim-0.8.0')->and(get(g:, 'jc_autoformat_on_save', 1))
  autocmd FileType java autocmd BufWrite <buffer> lua vim.lsp.buf.format({ async = false })
endif

command! JCdebugAttach lua require('jc.vimspector').debug_attach()
command! JCdebugLaunch lua require('jc.vimspector').debug_launch()
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

if !exists('g:jc_default_mappings')
  let g:jc_default_mappings = v:true
endif
