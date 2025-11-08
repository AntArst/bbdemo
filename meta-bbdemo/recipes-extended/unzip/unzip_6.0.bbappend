# Fix compilation errors with newer GCC versions
# The unzip 6.0 source has old-style function declarations that conflict
# with newer GCC's stricter type checking

python do_patch:append() {
    import os
    import subprocess
    
    unxcfg_h = os.path.join(d.getVar('S'), 'unix', 'unxcfg.h')
    if os.path.exists(unxcfg_h):
        subprocess.run(['sed', '-i', 
            's/struct tm \\*gmtime(), \\*localtime();/struct tm *gmtime(const time_t *), *localtime(const time_t *);/', 
            unxcfg_h], check=False)
}

