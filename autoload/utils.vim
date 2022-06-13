function! utils#trim(str)
  let str = substitute(a:str, '^\s*', '', '')
  return substitute(str, '\s*$', '', '')
endfunction
