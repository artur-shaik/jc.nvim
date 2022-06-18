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
        if !exists('g:JavaComplete_PomPath')
            if filereadable(getcwd() . g:utils#FILE_SEP . "pom.xml")
                let g:JavaComplete_PomPath = getcwd() . g:utils#FILE_SEP . "pom.xml"
            else
                let g:JavaComplete_PomPath = project_root#find_file('pom.xml')
            endif
        endif
        if g:JavaComplete_PomPath != ""
            let g:JavaComplete_PomPath = fnamemodify(g:JavaComplete_PomPath, ':p')
            return g:JavaComplete_PomPath
        else
            unlet g:JavaComplete_PomPath
        endif
    endif

    if !get(g:, 'JavaComplete_GradleRepositoryDisabled', 0)
        if !exists('g:JavaComplete_GradlePath')
            if filereadable(getcwd() . g:utils#FILE_SEP . "build.gradle")
                let g:JavaComplete_GradlePath = getcwd() . g:utils#FILE_SEP . "build.gradle"
            else
                let g:JavaComplete_GradlePath = project_root#find_file('build.gradle')
            endif
        endif
        if g:JavaComplete_GradlePath != ""
            let g:JavaComplete_GradlePath = fnamemodify(g:JavaComplete_GradlePath, ':p')
            return g:JavaComplete_GradlePath
        else
            unlet g:JavaComplete_GradlePath
        endif
    endif

    if !get(g:, 'JavaComplete_AntRepositoryDisabled', 0)
        if !exists('g:JavaComplete_AntPath')
            if filereadable(getcwd() . g:utils#FILE_SEP . "build.xml")
                let g:JavaComplete_AntPath = getcwd() . g:utils#FILE_SEP . "build.xml"
            else
                let g:JavaComplete_AntPath = project_root#find_file('build.xml')
            endif
        endif
        if g:JavaComplete_AntPath != ""
            let g:JavaComplete_AntPath = fnamemodify(g:JavaComplete_AntPath, ':p')
            return g:JavaComplete_AntPath
        else
            unlet g:JavaComplete_AntPath
        endif
    endif

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
