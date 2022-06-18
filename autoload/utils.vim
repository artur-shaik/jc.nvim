if has('macunix')
  let utils#OS = 'mac'
elseif has('win32')
  let utils#OS = 'win'
else
  let utils#OS = system('uname')->substitute('\n', '', '')->tolower()
endif

let utils#FILE_SEP = fnamemodify(getcwd(), ':p')->substitute('.*\(.\)$', '\1', '')

function! utils#trim(str)
  let str = substitute(a:str, '^\s*', '', '')
  return substitute(str, '\s*$', '', '')
endfunction
