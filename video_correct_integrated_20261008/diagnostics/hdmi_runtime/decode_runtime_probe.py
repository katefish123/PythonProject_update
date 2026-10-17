"""Read the hardware status grid, rejecting black/ambiguous/non-probe frames."""
from pathlib import Path
import argparse
import json
from PIL import Image

def decode(path, rect=None):
    frame=Image.open(path).convert('RGB')
    if rect is None:
        if frame.size!=(1920,1080):raise ValueError('Native 1920x1080 frame or explicit preview rectangle required')
        rect=(0,0,1920,1080)
    left,top,right,bottom=rect
    if not (0<=left<right<=frame.width and 0<=top<bottom<=frame.height):
        raise ValueError('Preview rectangle is outside the supplied frame')
    bits=[]
    colors=[]
    for row in range(16):
        for col in range(16):
            x=int(left+(60+120*col)*(right-left)/1920)
            y=int(top+(894+12*row)*(bottom-top)/1080)
            red,green,blue=frame.getpixel((x,y))
            if max(red,green)<60 or abs(red-green)<50:
                raise ValueError(f'Ambiguous status cell ({row},{col}): {(red,green,blue)}')
            bits.append('1' if green>red else '0')
            colors.append([red,green,blue])
    word=int(''.join(bits),2)
    extract=lambda hi,lo:(word>>lo)&((1<<(hi-lo+1))-1)
    if extract(255,240)!=0xD103:raise ValueError(f'Wrong probe signature: {extract(255,240):04x}')
    names=['config_error','startup_retry_seen','tx_done','rx_done','ack_error',
           'tx_probe_done','rx_probe_done','select_tx','rx_clock_seen','de_seen',
           'vs_seen','hs_seen','cfg_pll_locked','pixel_pll_locked',
           'cfg_snapshot_returned','rx_snapshot_returned']
    result={name:bool(extract(239-i,239-i)) for i,name in enumerate(names)}
    result.update(frame=str(path),preview_rect=rect,word_hex=f'{word:064x}',
        frequency_registers=f'0x{extract(223,192):08x}',rx_register_1281=f'0x{extract(191,184):02x}',
        last_device=f'0x{extract(183,176):02x}',last_address=f'0x{extract(175,160):04x}',
        last_read=f'0x{extract(159,152):02x}',last_nack_device=f'0x{extract(151,144):02x}',
        last_nack_address=f'0x{extract(143,128):04x}',nack_count=extract(127,112),
        transaction_count=extract(111,96),rx_width=extract(95,80),active_height=extract(79,64),
        rx_hs_period=extract(63,48),vs_edge_count=extract(47,32),
        sample_rgb=f'0x{extract(31,8):06x}',bus_busy=bool(extract(4,4)),
        last_owner_tx=bool(extract(3,3)),last_write=bool(extract(2,2)),
        last_nack_owner_tx=bool(extract(1,1)),last_nack_write=bool(extract(0,0)))
    return result

if __name__=='__main__':
    ap=argparse.ArgumentParser()
    ap.add_argument('frame',type=Path)
    ap.add_argument('--rect',nargs=4,type=int)
    ap.add_argument('--output',type=Path)
    args=ap.parse_args()
    result=decode(args.frame,args.rect)
    rendered=json.dumps(result,ensure_ascii=False,indent=2)+'\n'
    if args.output:args.output.write_text(rendered,encoding='utf-8')
    print(rendered)
