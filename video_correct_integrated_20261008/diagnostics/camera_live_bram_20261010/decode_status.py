"""Decode only this preview's no-camera diagnostic grid, never a camera photo."""
from pathlib import Path
import argparse
import json
from PIL import Image

def decode(path):
    frame = Image.open(path).convert('RGB')
    if frame.size != (1920,1080):
        raise ValueError('A native 1920x1080 source screenshot is required')
    bits = []
    for row in range(20):
        for col in range(16):
            red,green,blue = frame.getpixel((60+120*col,846+12*row))
            if max(red,green)<60 or abs(red-green)<50:
                raise ValueError(f'Not a readable diagnostic grid at ({row},{col})')
            bits.append('1' if green>red else '0')
    all_bits = int(''.join(bits),2)
    word = all_bits >> 64
    extract = lambda hi,lo:(word>>lo)&((1<<(hi-lo+1))-1)
    if extract(255,240)!=0xD104 or (all_bits>>48)&0xffff!=0xB401:
        raise ValueError('Wrong preview diagnostic signatures')
    names = ['config_error','startup_retry_seen','tx_done','rx_done','ack_error',
             'tx_probe_done','rx_probe_done','select_tx','rx_clock_seen','de_seen',
             'vs_seen','hs_seen','cfg_pll_locked','pixel_pll_locked',
             'cfg_snapshot_returned','rx_snapshot_returned']
    result = {name:bool(extract(239-i,239-i)) for i,name in enumerate(names)}
    result.update(frame=str(path),word_hex=f'{all_bits:080x}',
        frequency_registers=f'0x{extract(223,192):08x}',
        rx_register_1281=f'0x{extract(191,184):02x}',
        last_device=f'0x{extract(183,176):02x}',last_address=f'0x{extract(175,160):04x}',
        last_read=f'0x{extract(159,152):02x}',last_nack_device=f'0x{extract(151,144):02x}',
        last_nack_address=f'0x{extract(143,128):04x}',nack_count=extract(127,112),
        transaction_count=extract(111,96),rx_width=extract(95,80),active_height=extract(79,64),
        rx_hs_period=extract(63,48),vs_edge_count=extract(47,32),
        sample_rgb=f'0x{extract(31,8):06x}',
        frame_valid=bool((all_bits>>32)&1),samples_written=(all_bits>>13)&0xffff,
        writer_flags=(all_bits>>29)&7,display_frame_counter=all_bits&0x1fff)
    return result

if __name__=='__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('frame',type=Path)
    ap.add_argument('--output',type=Path)
    args = ap.parse_args()
    text = json.dumps(decode(args.frame),ensure_ascii=False,indent=2)+'\n'
    if args.output: args.output.write_text(text,encoding='utf-8')
    print(text)
