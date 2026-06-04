function! s:OnSave()
  if get(g:, 'jc_autoformat_on_save', 0)
    if has('nvim-0.8.0')
      lua vim.lsp.buf.format({ async = false })
    endif
  endif
endfunction

" jc.nvim never starts jdtls itself — it only hooks into an externally
" managed jdtls client (nvim-java, nvim-jdtls, lspconfig, ...).
" The g:jc_nvim_autoload guard is kept for backward compatibility with
" configs that used it to suppress the old built-in server bootstrap.
function! jc#Autoload()
  if exists('g:jc_nvim_autoload') | return | endif
  let g:jc_nvim_autoload = v:true

  augroup onsave
    autocmd! *
    autocmd BufWrite *.java call s:OnSave()
  augroup END

  lua require('jc').ensure_setup()
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
