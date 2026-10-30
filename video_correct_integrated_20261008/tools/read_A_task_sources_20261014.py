"""Read the supplied team plan and A checklist without changing them."""
from pathlib import Path
import hashlib
import json
from docx import Document
from docx.table import Table
from docx.text.paragraph import Paragraph
from pypdf import PdfReader

task_root = Path('C:/D/FPGA/个人任务')
out = Path('C:/D/FPGA/video_correct_integrated_20261008/tmp/a_tasks_20261014')
out.mkdir(parents=True, exist_ok=True)
sources = []
for path in sorted(task_root.iterdir()):
    if path.suffix.lower() == '.pdf':
        reader = PdfReader(path)
        pages = [{'page': i + 1, 'text': p.extract_text(extraction_mode='layout')} for i, p in enumerate(reader.pages)]
        item = {'path': str(path), 'kind': 'pdf', 'pages': pages}
        text = '\n\n'.join(f'--- 第 {p["page"]} 页 ---\n{p["text"]}' for p in pages)
    elif path.suffix.lower() == '.docx':
        doc = Document(path)
        blocks = []
        for child in doc.element.body.iterchildren():
            if child.tag.endswith('}p'):
                paragraph = Paragraph(child, doc)
                if paragraph.text.strip():
                    blocks.append({'kind': 'paragraph', 'style': paragraph.style.name, 'text': paragraph.text})
            elif child.tag.endswith('}tbl'):
                table = Table(child, doc)
                blocks.append({'kind': 'table', 'rows': [[c.text for c in row.cells] for row in table.rows]})
        item = {'path': str(path), 'kind': 'docx', 'blocks': blocks}
        text = '\n'.join(b['text'] if b['kind'] == 'paragraph' else '\n'.join(' | '.join(r) for r in b['rows']) for b in blocks)
    else:
        continue
    item['sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
    sources.append(item)
    (out / (path.stem + '.txt')).write_text(text, encoding='utf-8')
    print(f'\n=== {path.name} ===\n{text}')
(out / 'task_sources.json').write_text(json.dumps(sources, ensure_ascii=False, indent=2), encoding='utf-8')
