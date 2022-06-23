let g:project_root#patterns = get(g:, 'project_root#patterns',  ['mvnw', 'gradlew', 'pom.xml', 'build.gradle', 'build.xml'])

function! s:find_root_pattern(p)
  let root_files = findfile(a:p, escape(expand('%:p'), '*[]?{}, ').';', -1)->map('fnamemodify(v:val, ":p")')
  let shortest = 999999
  let root_file = ''
  for f in root_files
    if len(f) < shortest
      let root_file = f
      let shortest = len(f)
    endif
  endfor
  return root_file
endfunction

function! project_root#get_basedir(extra)
    let dir = get(g:, 'jc_basedir', expand('~'. g:utils#FILE_SEP. '.local'. g:utils#FILE_SEP. 'share')). g:utils#FILE_SEP. 'jc.nvim'. g:utils#FILE_SEP. a:extra. g:utils#FILE_SEP
    call mkdir(dir, "p")
    return dir
endfunction

function! project_root#get_name()
    let project_root = project_root#find()
    return substitute(project_root, '[\\/:;.]', '_', 'g')
endfunction

function! project_root#get_project_name()
    return fnamemodify(project_root#find(), ':p:h:t')
endfunction

function! project_root#find()
    if !get(g:, 'JavaComplete_MavenRepositoryDisabled', 0)
        let rootfile = s:find_root_pattern('pom.xml')
        if rootfile != ""
           let g:JavaComplete_PomPath = rootfile
           return rootfile
        endif
    endif

    if !get(g:, 'JavaComplete_GradleRepositoryDisabled', 0)
        let rootfile = s:find_root_pattern("build.gradle")
        if rootfile != ""
          let g:JavaComplete_GradlePath = rootfile
          return rootfile
        endif
    endif

    if !get(g:, 'JavaComplete_AntRepositoryDisabled', 0)
        let rootfile = s:find_root_pattern('build.xml')
        if rootfile != ""
          let g:JavaComplete_AntPath = rootfile
          return rootfile
        endif
    endif

    for p in g:project_root#patterns
      let rootfile = s:find_root_pattern(p)
      if rootfile != ''
        return rootfile
      endif
    endfor

    return getcwd()
endfunction

function! project_root#find_file(what, ...) abort
    let direction = a:0 > 0 ? a:1 : ';'
    let old_suffixesadd = &suffixesadd
    try
        let &suffixesadd = ''
        return findfile(a:what, escape(expand('%:p'), '*[]?{}, ') . direction)
    finally
        let &suffixesadd = old_suffixesadd
    endtry
endfunction
