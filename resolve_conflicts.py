import re
import sys

def resolve_conflicts(content):
    """Keep all changes from both sides of conflicts."""
    result = []
    in_head = False
    in_other = False
    head_lines = []
    other_lines = []
    
    for line in content.split('\n'):
        if line.startswith('<<<<<<< '):
            in_head = True
            head_lines = []
            other_lines = []
        elif line == '=======' and in_head:
            in_head = False
            in_other = True
        elif line.startswith('>>>>>>> ') and in_other:
            in_other = False
            # Merge: add head lines, then other lines that aren't duplicates
            result.extend(head_lines)
            for l in other_lines:
                if l not in head_lines:
                    result.append(l)
            head_lines = []
            other_lines = []
        elif in_head:
            head_lines.append(line)
        elif in_other:
            other_lines.append(line)
        else:
            result.append(line)
    
    return '\n'.join(result)

with open(sys.argv[1], 'r') as f:
    content = f.read()

resolved = resolve_conflicts(content)

with open(sys.argv[1], 'w') as f:
    f.write(resolved)

print(f"Resolved: {sys.argv[1]}")
