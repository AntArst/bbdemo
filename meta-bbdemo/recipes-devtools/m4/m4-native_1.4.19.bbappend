# Fix compilation errors with newer GCC versions
# m4 1.4.19 has issues with _GL_ATTRIBUTE_NODISCARD not being recognized
# by newer GCC versions when used with GL_OSET_INLINE and GL_LIST_INLINE

# Fix the source files by removing the problematic attribute
python do_patch:append() {
    import os
    import subprocess
    
    # Fix gl_oset.h
    gl_oset_h = os.path.join(d.getVar('S'), 'lib', 'gl_oset.h')
    if os.path.exists(gl_oset_h):
        subprocess.run(['sed', '-i', 's/_GL_ATTRIBUTE_NODISCARD //g', gl_oset_h], check=False)
    
    # Fix gl_list.h  
    gl_list_h = os.path.join(d.getVar('S'), 'lib', 'gl_list.h')
    if os.path.exists(gl_list_h):
        subprocess.run(['sed', '-i', 's/_GL_ATTRIBUTE_NODISCARD //g', gl_list_h], check=False)
}

