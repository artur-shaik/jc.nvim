function! s:is_windows() abort
    return has("win32") || has("win64") || has("win16") || has("dos32") || has("dos16")
endfunction

if s:is_windows()
    let g:PATH_SEP    = ';'
    let g:FILE_SEP    = '\'
else
    let g:PATH_SEP    = ':'
    let g:FILE_SEP    = '/'
endif

function! project_root#get_basedir(extra)
    let dir = get(g:, 'jc_basedir', expand('~'. g:FILE_SEP. '.local'. g:FILE_SEP. 'share')). g:FILE_SEP. 'jc.nvim'. g:FILE_SEP. a:extra. g:FILE_SEP
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
        if !exists('g:JavaComplete_PomPath')
            let g:JavaComplete_PomPath = project_root#find_file('pom.xml')
            if g:JavaComplete_PomPath != ""
                return fnamemodify(g:JavaComplete_PomPath, ':p')
            endif
        endif
    endif

    if !get(g:, 'JavaComplete_GradleRepositoryDisabled', 0)
        if !exists('g:JavaComplete_GradlePath')
            if filereadable(getcwd(). g:FILE_SEP. "build.gradle")
                let g:JavaComplete_GradlePath = getcwd(). g:FILE_SEP. "build.gradle"
            else
                let g:JavaComplete_GradlePath = project_root#find_file('build.gradle', '**3')
            endif
            if g:JavaComplete_GradlePath != ""
                return fnamemodify(g:JavaComplete_GradlePath, ':p')
            endif
        endif
    endif

    if !get(g:, 'JavaComplete_AntRepositoryDisabled', 0)
        if !exists('g:JavaComplete_AntPath')
            if filereadable(getcwd(). g:FILE_SEP. "build.xml")
                let g:JavaComplete_AntPath = getcwd(). g:FILE_SEP. "build.xml"
            else
                let g:JavaComplete_AntPath = project_root#find_file('build.xml', '**3')
            endif
            if g:JavaComplete_AntPath != ""
                return fnamemodify(g:JavaComplete_AntPath, ':p')
            endif
        endif
    endif

    return getcwd()
endfunction

function! project_root#find_file(what, ...) abort
    let direction = a:0 > 0 ? a:1 : ';'
    let old_suffixesadd = &suffixesadd
    try
        let &suffixesadd = ''
        return findfile(a:what, escape(expand('.'), '*[]?{}, ') . direction)
    finally
        let &suffixesadd = old_suffixesadd
    endtry
endfunction
