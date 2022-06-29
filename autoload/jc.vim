function! jc#Autoload()
  if exists('g:jc_nvim_autoload') | return | endif
  let g:jc_nvim_autoload = v:true

  if has('nvim-0.8.0')->and(get(g:, 'jc_autoformat_on_save', 1))
    autocmd FileType java autocmd BufWrite <buffer> lua vim.lsp.buf.format({ async = false })
  endif

  if !exists('g:jc_default_mappings')
    let g:jc_default_mappings = v:true
  endif
endfunction
