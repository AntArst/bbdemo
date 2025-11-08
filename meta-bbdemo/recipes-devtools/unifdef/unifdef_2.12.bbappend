# Fix compilation errors with newer GCC versions
# unifdef uses 'constexpr' as a variable name which conflicts with C++ keyword

# Fix the source file to rename the variable
python do_patch:append() {
    import os
    import re
    
    unifdef_c = os.path.join(d.getVar('S'), 'unifdef.c')
    if os.path.exists(unifdef_c):
        with open(unifdef_c, 'r') as f:
            content = f.read()
        
        # Replace variable name: constexpr -> const_expr
        content = re.sub(r'\bconstexpr\b', 'const_expr', content)
        
        with open(unifdef_c, 'w') as f:
            f.write(content)
}

