"""Create sample_memo.chappy from sample_apps/memo (no dependencies)."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

root = Path(__file__).resolve().parents[1]
sample = root / 'sample_apps' / 'memo'
target = root / 'sample_memo.chappy'
with ZipFile(target, 'w', ZIP_DEFLATED, compresslevel=6) as archive:
    for path in sorted(sample.rglob('*')):
        if path.is_file():
            archive.write(path, path.relative_to(sample).as_posix())
print(f'Generated: {target} ({target.stat().st_size} bytes)')
