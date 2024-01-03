" gtags_cscope module for Gutentags

if !has('cscope')
    throw "Can't enable the gtags-cscope module for Gutentags, "
                \"this Vim has no support for cscope files."
endif

" Global Options {{{

if !exists('g:gutentags_gtags_executable')
    let g:gutentags_gtags_executable = 'gtags'
endif

if !exists('g:gutentags_gtags_dbpath')
    let g:gutentags_gtags_dbpath = ''
endif

if !exists('g:gutentags_gtags_options_file')
    let g:gutentags_gtags_options_file = '.gutgtags'
endif

if !exists('g:gutentags_gtags_cscope_executable')
    let g:gutentags_gtags_cscope_executable = 'gtags-cscope'
endif

if !exists('g:gutentags_auto_add_gtags_cscope')
    let g:gutentags_auto_add_gtags_cscope = 1
endif

" }}}

" Gutentags Module Interface {{{

let s:runner_exe = gutentags#get_plat_file('update_gtags')
let s:added_db_files = {}

function! s:add_db(db_file) abort
    if filereadable(a:db_file)
        call gutentags#trace(
                    \"Adding cscope DB file: " . a:db_file)
        set nocscopeverbose
        execute 'cs add ' . fnameescape(a:db_file)
        set cscopeverbose
        let s:added_db_files[a:db_file] = 1
    else
        call gutentags#trace(
                    \"Not adding cscope DB file because it doesn't " .
                    \"exist yet: " . a:db_file)
    endif
endfunction

function! gutentags#gtags_cscope#init(project_root) abort
    let l:db_path = gutentags#get_cachefile(
                \a:project_root, g:gutentags_gtags_dbpath)
    if !isdirectory(l:db_path)
        call mkdir(l:db_path, 'p')
    endif
    let l:db_path = gutentags#stripslash(l:db_path)
    let l:db_file = fnamemodify(l:db_path, ':p') . 'GTAGS'
    let l:db_file = gutentags#normalizepath(l:db_file)

    let b:gutentags_files['gtags_cscope'] = l:db_file

    execute 'set cscopeprg=' . fnameescape(g:gutentags_gtags_cscope_executable)

    " The combination of gtags-cscope, vim's cscope and global files is
    " a bit flaky. Environment variables are safer than vim passing
    " paths around and interpreting input correctly.
    let $GTAGSDBPATH = l:db_path
    let $GTAGSROOT = a:project_root
    if get(g:, 'gutentags_trace', 0)
        let $GTAGSLOGGING = fnamemodify(l:db_path, ':p') . 'GLOG'
    endif

    if g:gutentags_auto_add_gtags_cscope && 
                \!has_key(s:added_db_files, l:db_file)
        let s:added_db_files[l:db_file] = 0
        call s:add_db(l:db_file)
    endif
endfunction

function! gutentags#gtags_cscope#generate(proj_dir, tags_file, gen_opts) abort
    if get(g:, 'gutentags_gtags_executable', 'gtags') == 'gtags'
        let l:cmd = [g:gutentags_gtags_executable]
    else
        let l:cmd = [s:runner_exe]
        let l:cmd += ['-e', '"' . g:gutentags_gtags_executable . '"']
    endif

    let l:file_list_cmd = gutentags#get_project_file_list_cmd(a:proj_dir)
    if !empty(l:file_list_cmd)
        let l:cmd += ['-L', '"' . l:file_list_cmd . '"']
    endif

    let l:proj_options_file = a:proj_dir . '/' . g:gutentags_gtags_options_file
    if filereadable(l:proj_options_file)
        let l:proj_options = readfile(l:proj_options_file)
        let l:cmd += l:proj_options
    endif

    " gtags doesn't honour GTAGSDBPATH and GTAGSROOT, so PWD and dbpath
    " have to be set
    if exists("$GTAGSROOT")
        let l:gtagsroot = $GTAGSROOT
    elseif exists("*FindRootDirectory")
        let l:gtagsroot = FindRootDirectory()
    else
        let l:gtagsroot = getcwd()
    endif
    if exists('*trim')
        let l:gtagsroot = trim(l:gtagsroot)
    endif
    let l:gtagsroot = substitute(l:gtagsroot, ' ', '\\ ', 'g')
    let l:cmd += ['--directory', '"'.l:gtagsroot.'"']
    let l:db_path = fnamemodify(a:tags_file, ':p:h')
    let l:cmd += ['--incremental', '"'.l:db_path.'"']
    " add gtags verbose debugging info
    if get(g:, 'gutentags_trace', 0)
        let l:cmd += ['--verbose']
    endif

    let l:cmd = gutentags#make_args(l:cmd)

    call gutentags#trace("Running: " . join(l:cmd, ' '))
    call gutentags#trace("In:      " . getcwd())
    if !g:gutentags_fake
        let l:job_opts = gutentags#build_default_job_options('gtags_cscope')
        let l:job = gutentags#start_job(l:cmd, l:job_opts)
        call gutentags#add_job('gtags_cscope', a:tags_file, l:job)
    else
        call gutentags#trace("(fake... not actually running)")
    endif
    call gutentags#trace("")
endfunction

function! gutentags#gtags_cscope#on_job_exit(job, exit_val) abort
    let l:job_idx = gutentags#find_job_index_by_data('gtags_cscope', a:job)
    let l:dbfile_path = gutentags#get_job_tags_file('gtags_cscope', l:job_idx)
    call gutentags#remove_job('gtags_cscope', l:job_idx)

    if g:gutentags_auto_add_gtags_cscope
        call s:add_db(l:dbfile_path)
    endif

    if a:exit_val != 0 && !g:__gutentags_vim_is_leaving
        call gutentags#warning(
                    \"gtags-cscope job failed, returned: ".
                    \string(a:exit_val))
    endif
    if has('win32') && g:__gutentags_vim_is_leaving
        " The process got interrupted because Vim is quitting.
        " Remove the db file on Windows because there's no `trap`
        " statement in the update script.
        try | call delete(l:dbfile_path) | endtry
    endif
endfunction

" }}}
