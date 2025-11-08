# Fix compilation errors with newer GCC versions
# glib (used by pkgconfig) uses 'bool' as a struct member name which conflicts with C99 bool keyword

# Fix the glib source file to rename the struct member
python do_patch:append() {
    import os
    import re
    
    # Find and fix goption.c in the glib subdirectory
    goption_c = os.path.join(d.getVar('S'), 'glib', 'glib', 'goption.c')
    if os.path.exists(goption_c):
        with open(goption_c, 'r') as f:
            content = f.read()
        
        # Replace struct member definition: bool -> bool_val
        content = re.sub(r'\bbool\s*;', 'bool_val;', content)
        # Replace usage: .bool -> .bool_val
        content = re.sub(r'\.bool\b', '.bool_val', content)
        # Replace usage: ->bool -> ->bool_val
        content = re.sub(r'->bool\b', '->bool_val', content)
        
        with open(goption_c, 'w') as f:
            f.write(content)
}

