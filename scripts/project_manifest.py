"""Explicit portable project inputs shared by verification and packaging."""

def source_files(root):
    files = [root / name for name in ('Makefile', 'README.md', 'requirements.txt', '.gitignore')]
    for folder in ('rtl', 'tests', 'formal', 'examples', 'scripts', 'docs', '.github'):
        files.extend(p for p in (root / folder).rglob('*')
                     if p.is_file() and p.suffix in ('.v', '.py', '.mk', '.md', '.yml'))
    return sorted(files)
