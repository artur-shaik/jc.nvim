let g:JavaComplete_Templates = {}
let g:JavaComplete_Generators = {}

function! generators#GenerateClass(options, ...)
  let template = a:0 > 0 && !empty(a:1) ? '_'. a:1 : ''
  let classCommand = {'template': 'class'. template, 'options': a:options, 'position_type' : 1}
  call <SID>generateByTemplate(classCommand)
endfunction

function! generators#GenerateHashCodeAndEquals(fields)
    let commands = [
                \ {'key': '1', 'desc': 'generate `hashCode and equals`', 'call': '<SID>generate', 'command': 'lua require("jc.jdtls").generate_hashCodeAndEquals'},
                \ ]
    call s:FieldsListBuffer(commands, a:fields)
endfunction

function! generators#GenerateToString(fields)
    let commands = [
                \ {'key': '1', 'desc': 'generate `toString`', 'call': '<SID>generate', 'command': 'lua require("jc.jdtls").generate_toString', 'params': {'code_style' : 'STRING_CONCATENATION'}},
                \ {'key': '2', 'desc': 'generate `toString`', 'call': '<SID>generate', 'command': 'lua require("jc.jdtls").generate_toString', 'params': {'code_style': 'STRING_BUILDER'}},
                \ {'key': '3', 'desc': 'generate `toString`', 'call': '<SID>generate', 'command': 'lua require("jc.jdtls").generate_toString', 'params': {'code_style': 'STRING_BUILDER_CHAINED'}},
                \ {'key': '4', 'desc': 'generate `toString`', 'call': '<SID>generate', 'command': 'lua require("jc.jdtls").generate_toString', 'params': {'code_style': 'STRING_FORMAT'}},
                \ ]
    call s:FieldsListBuffer(commands, a:fields)
endfunction

function! generators#GenerateAccessors(fields)
    let commands = [{'key': 's', 'desc': 'generate accessors', 'call': '<SID>generateAccessors', 'command': 'lua require("jc.jdtls").generate_accessors'}]
    let contentLine = s:CreateBuffer("__AccessorsBuffer__", "remove unnecessary accessors", commands)

    let b:currentFileVars = a:fields

    let lines = ""
    let idx = 0
    while idx < len(b:currentFileVars)
        let var = b:currentFileVars[idx]
        let varName = toupper(var.fieldName[0]). var.fieldName[1:]
        let lines = lines. "\n". "g". idx. " --> ". " get". varName . "()"
        if var.generateSetter
            let lines = lines. "\n". "s". idx. " --> ". "set". varName . "(". var.fieldName. ")"
        endif
        let lines = lines. "\n"

        let idx += 1
    endwhile
    silent put = lines

    call cursor(contentLine + 1, 0)

endfunction

function! generators#GenerateAccessor(symbols, accessor)
    call <SID>generateAccessors({'command': 'lua require("jc.jdtls").generate_accessors'}, {'symbols': a:symbols, 'accessor': a:accessor})
endfunction

function! generators#GenerateConstructor(fields, constructors, options)
    let defaultConstructor = {
                \ 'key': '1', 'desc': 'generate default constructor',
                \ 'call': '<SID>generate',
                \ 'command': 'lua require("jc.jdtls").generate_constructor',
                \ 'params': {
                    \ 'default_constructor': v:true, 
                    \'constructors': a:constructors}}
    if a:options.default == v:false
        let commands = [
                    \ defaultConstructor,
                    \ {
                        \ 'key': '2',
                        \ 'desc': 'generate constructor',
                        \ 'call': '<SID>generate',
                        \ 'command': 'lua require("jc.jdtls").generate_constructor',
                        \ 'params': {
                            \ 'default_constructor': v:false,
                            \ 'constructors': a:constructors}}
                    \ ]
        call s:FieldsListBuffer(commands, a:fields)
    else
        execute(defaultConstructor.command . '({}, vim.api.nvim_eval("'. string(defaultConstructor.params). '"))')
    endif
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
        let params = get(command, 'params', {})
        put = '\" '. command.key . '                      - '. command.desc. ' '. get(params, 'code_style', '')
        if has_key(command, 'call')
            exec "nnoremap <buffer> <silent> ". command.key . " :call ". command.call . "(". string(command). ", ". string(params). ")<CR>"
        endif
    endfor
    put = '\"-----------------------------------------------------'

    return line(".") + 1
endfunction

function! <SID>generate(command, params)
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

    execute(command.command . '(vim.api.nvim_eval("'. string(command['fields']). '"), vim.api.nvim_eval("'. string(a:params). '"))')
endfunction

function! <SID>generateAccessors(command, params)
    let command = a:command
    if !has_key(command, 'fields')
        let command['fields'] = []
    endif

    let result = []
    let locationMap = []
    if bufname('%') == "__AccessorsBuffer__"

        func! UnsetCmds(_, val)
            let a:val.generateSetter = v:false
            let a:val.generateGetter = v:false
            return a:val
        endfunc
        call map(b:currentFileVars, function('UnsetCmds'))

        let currentBuf = getline(1,'$')
        for line in currentBuf
            if line =~ '^\(g\|s\)[0-9]\+.*'
                let idx = line[1:stridx(line, ' ')-1]
                let var = b:currentFileVars[idx]
                if line[0] == 'g'
                    let var.generateGetter = v:true
                elseif line[0] == 's'
                    let var.generateSetter = v:true
                endif
                call filter(command['fields'], 'v:val.fieldName !~ var.fieldName')
                call add(command['fields'], var)
            endif
        endfor

        execute "bwipeout!"
    else
        if or(mode() == 'n', mode() == 'i')
            let currentLines = [line('.') - 1]
        elseif mode() == 'v'
            let [lnum1, col1] = getpos("'<")[1:2]
            let [lnum2, col2] = getpos("'>")[1:2]
            let currentLines = range(lnum1 - 1, lnum2 - 1)
        else
            let currentLines = []
        endif
        for d in get(a:params, 'symbols', [])
            if get(d, 'kind', '') == 8
                let line = d.range.start.line
                let endline = d.range.end.line
                for l in currentLines
                    if l >= line && l <= endline
                        let cmd = get(a:params, 'accessor', 'sg')
                        let field = { 'fieldName': d.name }
                        if stridx(cmd, 's') >= 0
                            let field.generateSetter = v:true
                        end
                        if stridx(cmd, 'g') >= 0
                            let field.generateGetter = v:true
                        end
                        call add(command['fields'], field)
                    endif
                endfor
            endif
        endfor
        unlet a:params.symbols
        unlet a:params.accessor

    endif

    execute(command.command . '(vim.api.nvim_eval("'. string(command['fields']). '"), vim.api.nvim_eval("'. string(a:params). '"))')
endfunction

function! generators#GenerateByTemplate(command)
  call <SID>generateByTemplate(a:command)
endfunction

" a:1 - method declaration to replace
function! <SID>generateByTemplate(command)
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
        let var = b:currentFileVars[idx]
        call add(command['fields'], var)
      endif
    endfor

    execute "bwipeout!"
  endif

  let result = []
  let templates = type(command.template) != type([]) ? [command.template] : command.template
  let class = {}
  if has_key(s:, 'ti')
    let class['name'] = s:ti.name
  endif
  let class['fields'] = command['fields']
  for template in templates
    call s:CheckAndLoadTemplate(template)
    if has_key(g:JavaComplete_Generators, template)
      execute g:JavaComplete_Generators[template]['data']

      let arguments = [class]
      if has_key(command, 'options')
        call add(arguments, command.options)
      endif
      let TemplateFunction = function('s:__'. template)
      for line in split(call(TemplateFunction, arguments), '\n')
        call add(result, line)
      endfor
      call add(result, '')
    endif
  endfor

  if len(result) > 0
    if has_key(command, 'replace')
      let toReplace = []
      if command.replace.type == 'same'
        let defs = s:GetNewMethodsDefinitions(result)
        for def in defs
          call add(toReplace, def.d)
        endfor
      elseif command.replace.type == 'similar'
        let defs = s:GetNewMethodsDefinitions(result)
        for def in defs
          let m = s:FindMethod(s:ti.methods, def)
          if !empty(m)
            call add(toReplace, m.d)
          endif
        endfor
      endif

      let idx = 0
      while idx < len(s:ti.defs)
        let def = s:ti.defs[idx]
        if get(def, 'tag', '') == 'METHODDEF' 
          \ && index(toReplace, get(def, 'd', '')) > -1
          \ && has_key(def, 'body') && has_key(def.body, 'endpos')

          let startline = java_parser#DecodePos(def.pos).line
          if !empty(getline(startline))
            let startline += 1
          endif
          let endline = java_parser#DecodePos(def.body.endpos).line + 1
          silent! execute startline.','.endline. 'delete _'

          call setpos('.', s:savedCursorPosition)
          let s:ti = javacomplete#collector#DoGetClassInfo('this')
          let idx = 0
        else
          let idx += 1
        endif
      endwhile
    endif
    if has_key(command, 'position_type')
      call s:InsertResults(result, command['position_type'])
    else
      call s:InsertResults(result)
    endif
    if has_key(s:, 'savedCursorPosition')
      call setpos('.', s:savedCursorPosition)
    endif
  endif
endfunction

function! s:CheckAndLoadTemplate(template)
  let filenames = []
  if exists('g:JavaComplete_CustomTemplateDirectory')
    if isdirectory(g:JavaComplete_CustomTemplateDirectory)
      call add(filenames, expand(g:JavaComplete_CustomTemplateDirectory). '/gen__'. a:template. '.tpl')
    endif
  endif
  call add(filenames, g:JavaComplete_Home. '/plugin/res/gen__'. a:template. '.tpl')
  for filename in filenames
    if filereadable(filename)
      if has_key(g:JavaComplete_Generators, a:template)
        if getftime(filename) > g:JavaComplete_Generators[a:template]['file_time']
          let g:JavaComplete_Generators[a:template]['data'] = join(readfile(filename), "\n")
          let g:JavaComplete_Generators[a:template]['file_time'] = getftime(filename)
        endif
      else
        let g:JavaComplete_Generators[a:template] = {}
        let g:JavaComplete_Generators[a:template]['data'] = join(readfile(filename), "\n")
        let g:JavaComplete_Generators[a:template]['file_time'] = getftime(filename)
      endif
      break
    endif
  endfor
endfunction

function! s:InsertResults(result, ...)
  if len(a:result) > 0
    call append(0, a:result)
    silent execute "normal! dd"
    silent execute "normal! =G"
  endif
endfunction
