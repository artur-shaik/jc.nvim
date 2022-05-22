
function! generators#GenerateToString(fields)
  let commands = [
        \ {'key': '1', 'desc': 'generate `toString`', 'call': '<SID>generate', 'command': 'lua require("jc.jdtls").generate_toString', 'code_style': 'STRING_CONCATENATION'},
        \ {'key': '2', 'desc': 'generate `toString`', 'call': '<SID>generate', 'command': 'lua require("jc.jdtls").generate_toString', 'code_style': 'STRING_BUILDER'},
        \ {'key': '3', 'desc': 'generate `toString`', 'call': '<SID>generate', 'command': 'lua require("jc.jdtls").generate_toString', 'code_style': 'STRING_BUILDER_CHAINED'},
        \ {'key': '4', 'desc': 'generate `toString`', 'call': '<SID>generate', 'command': 'lua require("jc.jdtls").generate_toString', 'code_style': 'STRING_FORMAT'},
        \ ]
  call s:FieldsListBuffer(commands, a:fields)
endfunction

function! s:FieldsListBuffer(commands, fields)
  let s:savedCursorPosition = getpos('.')
  let contentLine = s:CreateBuffer("__FieldsListBuffer__", "remove unnecessary fields", a:commands)

  let b:fields = a:fields

  let lines = ""
  let idx = 0
  while idx < len(b:fields)
    let field = b:fields[idx]
    let lines = lines. "\n". "f". idx. " --> ". field.type . " ". field.name
    let idx += 1
  endwhile
  silent put = lines

  call cursor(contentLine + 1, 0)
endfunction

function! s:CreateBuffer(name, title, commands)
  let n = bufwinnr(a:name)
  if n != -1
      execute "bwipeout!"
  endif
  exec 'silent! split '. a:name

  " Mark the buffer as scratch
  setlocal buftype=nofile
  setlocal bufhidden=wipe
  setlocal noswapfile
  setlocal nowrap
  setlocal nobuflisted

  nnoremap <buffer> <silent> q :bwipeout!<CR>

  syn match Comment "^\".*"
  put = '\"-----------------------------------------------------'
  put = '\" '. a:title
  put = '\" '
  put = '\" q                      - close this window'
  for command in a:commands
    put = '\" '. command.key . '                      - '. command.desc. ' ('. command.code_style. ')'
    if has_key(command, 'call')
      exec "nnoremap <buffer> <silent> ". command.key . " :call ". command.call . "(". string(command). ", '". command.code_style. "')<CR>"
    endif
  endfor
  put = '\"-----------------------------------------------------'

  return line(".") + 1
endfunction

function! <SID>generate(command, code_style)
  let command = a:command
  if !has_key(command, 'fields')
    let command['fields'] = []
  endif

  if bufname('%') == "__FieldsListBuffer__"
    let currentBuf = getline(1,'$')
    for line in currentBuf
      if line =~ '^f[0-9]\+.*'
        let cmd = line[0]
        let idx = line[1:stridx(line, ' ')-1]
        let var = b:fields[idx]
        call add(command['fields'], var)
      endif
    endfor

    execute "bwipeout!"
  endif

  execute(command.command . '(vim.api.nvim_eval("'. string(command['fields']). '"), "'. a:code_style. '")')
endfunction
