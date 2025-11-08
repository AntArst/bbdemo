# Fix compilation errors with newer GCC versions
# gdbm uses 'bool' as a struct member name which conflicts with C99 bool keyword

# Fix the source file to rename the struct member
python do_patch:append() {
    import os
    import subprocess
    import re
    
    var_c = os.path.join(d.getVar('S'), 'tools', 'var.c')
    if os.path.exists(var_c):
        with open(var_c, 'r') as f:
            content = f.read()
        
        # Replace struct member definition: bool -> bool_val
        content = re.sub(r'\bbool\s*;', 'bool_val;', content)
        # Replace usage: .bool -> .bool_val
        content = re.sub(r'\.bool\b', '.bool_val', content)
        # Replace usage: ->bool -> ->bool_val  
        content = re.sub(r'->bool\b', '->bool_val', content)
        
        with open(var_c, 'w') as f:
            f.write(content)
}

