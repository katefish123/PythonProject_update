"""Frozen, optional experiment: bound only four lookup coordinate fanouts.

ADS Synthesis User Guide PDF pages 88-89 documents syn_maxfan. This adds
no registers/cycles, changes no expressions and does not target clock/reset.
It is not a physical qualification; mapped load counts must be inspected.
"""
PAIRS=[]
for axis in ['','1']:
    x='lookup_x'+axis; y='lookup_y'+axis
    lx='l_x'+axis; sx='s_x'+axis; ly='l_y'+axis; sy='s_y'+axis
    old=f' wire[11:0]{x}=lookup_l?{lx}:{sx},{y}=lookup_l?{ly}:{sy};'
    new=(f' (* syn_maxfan=32 *) wire[11:0]{x}=lookup_l?{lx}:{sx};\n'
         f' (* syn_maxfan=32 *) wire[11:0]{y}=lookup_l?{ly}:{sy};')
    PAIRS.append((old,new))

def transform(text):
    if 'syn_maxfan' in text:raise RuntimeError('Parent already has fanout directives')
    for old,new in PAIRS:
        if text.count(old)!=1:raise RuntimeError('Unexpected lookup declaration')
        text=text.replace(old,new)
    return text

def restore(text):
    for old,new in PAIRS:
        if text.count(new)!=1:raise RuntimeError('Unexpected fanout experiment')
        text=text.replace(new,old)
    if 'syn_maxfan' in text:raise RuntimeError('Unexpected extra directive')
    return text
