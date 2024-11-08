function! s:OnSave()
  if get(g:, 'jc_autoformat_on_save', 0)
    if has('nvim-0.8.0')
      lua vim.lsp.buf.format({ async = false })
    endif
  endif
endfunction

function! jc#Autoload()
  if exists('g:jc_nvim_autoload') | return | endif
  let g:jc_nvim_autoload = v:true

  augroup onsave
    autocmd! *
    autocmd BufWrite *.java call s:OnSave()
  augroup END

  if !exists('g:jc_default_mappings')
    let g:jc_default_mappings = v:true
  endif

  lua require('jc').run_setup()
endfunction

function! jc#toggleAutoformat()
  if get(g:, 'jc_autoformat_on_save', 1)
    let g:jc_autoformat_on_save = 0
    echom "autoformat on save disabled"
  else 
    let g:jc_autoformat_on_save = 1
    echom "autoformat on save enabled"
  endif
endfunction
