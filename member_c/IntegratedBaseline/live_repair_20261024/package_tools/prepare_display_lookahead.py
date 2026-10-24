"""Isolated four-row lookahead candidate. No hardware IO or baseline edits."""
from pathlib import Path
import argparse,hashlib,json

def once(s,old,new):
    assert s.count(old)==1,old[:100]
    return s.replace(old,new)

def transform(s):
    s=once(s,'reg [255:0] line_mem1[0:BURSTS_PER_ROW-1];',
        'reg [255:0] line_mem1[0:BURSTS_PER_ROW-1];\n    (* syn_ramstyle="block_ram" *) reg[255:0]line_mem2[0:BURSTS_PER_ROW-1];\n    (* syn_ramstyle="block_ram" *) reg[255:0]line_mem3[0:BURSTS_PER_ROW-1];')
    s=once(s,'reg [1:0] line_valid;','reg [3:0] line_valid;')
    s=once(s,'reg [ROW_BITS-1:0] line_row0, line_row1;','reg [ROW_BITS-1:0] line_row0, line_row1,line_row2,line_row3;\n    reg[ROW_BITS-1:0]prefetch_row;')
    s=once(s,'reg line_bank0, line_bank1,line_raw0,line_raw1;','reg line_bank0, line_bank1,line_raw0,line_raw1,line_bank2,line_bank3,line_raw2,line_raw3;')
    s=once(s,'reg [15:0] line_gen0, line_gen1;','reg [15:0] line_gen0, line_gen1,line_gen2,line_gen3;')
    s=once(s,'    wire buffer_free=', '    wire[1:0]ui_buffer=ui_line_row,scan_buffer=scan_row_ui2,req_buffer=req_row;\n    wire buffer_free=')
    s=once(s,'ui_line_row[0]!=scan_row_ui2[0]','ui_buffer!=scan_buffer')
    s=once(s,'if(ui_line_row[0])line_mem1[burst_index]<=block_data[block_beat*256+:256];\n        else line_mem0[burst_index]<=block_data[block_beat*256+:256];',
        '''case(ui_buffer)
        0:line_mem0[burst_index]<=block_data[block_beat*256+:256];
        1:line_mem1[burst_index]<=block_data[block_beat*256+:256];
        2:line_mem2[burst_index]<=block_data[block_beat*256+:256];
        3:line_mem3[burst_index]<=block_data[block_beat*256+:256];
        endcase''')
    anchor='    wire next_match0='
    start=s.index(anchor);end=s.index('    wire active_window=',start)
    s=s[:start]+'''    wire dest_match2=line_valid[2] && line_row2==dest_row && line_bank2==display_bank && line_gen2==display_gen && line_raw2==display_raw;
    wire dest_match3=line_valid[3] && line_row3==dest_row && line_bank3==display_bank && line_gen3==display_gen && line_raw3==display_raw;
    wire dest_match=dest_match0||dest_match1||dest_match2||dest_match3;
    wire[ROW_BITS:0]prefetch_limit=first_dest_line?{1'b0,dest_row}+3:3;
'''+s[end:]
    s=once(s,'line_valid<=0; line_row0<=0; line_row1<=0; line_bank0<=0; line_bank1<=0;line_raw0<=0;line_raw1<=0;',
        'line_valid<=0; line_row0<=0; line_row1<=0; line_row2<=0;line_row3<=0;line_bank0<=0; line_bank1<=0;line_bank2<=0;line_bank3<=0;line_raw0<=0;line_raw1<=0;line_raw2<=0;line_raw3<=0;prefetch_row<=0;')
    s=once(s,'line_gen0<=0; line_gen1<=0;scan_active_pix<=0;scan_row_pix<=0;',
        'line_gen0<=0; line_gen1<=0;line_gen2<=0;line_gen3<=0;scan_active_pix<=0;scan_row_pix<=0;')
    start=s.index('                if(req_row[0]) begin');end=s.index('\n            end',start)
    s=s[:start]+'''                case(req_buffer)
'''+''.join(f'                {n}:begin line_valid[{n}]<=1;line_row{n}<=req_row;line_bank{n}<=req_bank;line_gen{n}<=req_gen;line_raw{n}<=req_raw;end\n' for n in range(4))+'''                endcase
                if(req_gen==display_gen && req_bank==display_bank && req_raw==display_raw)
                    prefetch_row<=req_row+1'b1;'''+s[end:]
    start=s.index('            if(publication_boundary) begin');end=s.index('\n            if(hc==0) begin',start)
    s=s[:start]+'''            // Four physical rows, at most three rows ahead of the scan.
            // The request payload is immutable until its line-complete ACK.
            // A new publication/frame restart rewinds the cursor; old ACKs
            // carry their original generation and cannot advance a new cursor.
            if(publication_boundary) begin
                prefetch_row<=0;
                if(pub_toggle_sync[2]!=ack_toggle&&(!swapped_this_scan||frame_start)) begin
                    swapped_this_scan<=1;
                    display_frame_id<=publish_frame_id;display_bank<=pub_bank_sync[2];display_raw<=pub_raw_sync[2];image_swap_pulse<=1;display_gen<=display_gen+1'b1;
                    image_valid<=1;ack_toggle<=pub_toggle_sync[2];line_valid<=0;
                end else if(image_valid)begin
                    // Each scan has a fresh line epoch even if the same
                    // completed image is scanned again. Late prior-scan ACKs
                    // cannot move the rewound prefetch cursor past row zero.
                    display_gen<=display_gen+1'b1;line_valid<=0;
                end
            end else begin
                if(hc==0 && first_dest_line && !force_pattern && image_valid && !dest_match)underrun<=1;
                if(image_valid && req_toggle==ui_ack_sync[2] && ui_ack_sync[2]==ack_seen_pix &&
                   prefetch_row<OUT_H && {1'b0,prefetch_row}<=prefetch_limit)begin
                    req_row<=prefetch_row;req_bank<=display_bank;req_raw<=display_raw;req_gen<=display_gen;
                    req_toggle<=~req_toggle;
                end
            end
'''+s[end:]
    s=s.replace('(dest_match0||dest_match1)','dest_match')
    s=once(s,'if(cur_y[0]) line_word_q<=line_mem1[cur_x>>3];\n                else line_word_q<=line_mem0[cur_x>>3];',
        '''case(cur_y[1:0])
                0:line_word_q<=line_mem0[cur_x>>3];
                1:line_word_q<=line_mem1[cur_x>>3];
                2:line_word_q<=line_mem2[cur_x>>3];
                3:line_word_q<=line_mem3[cur_x>>3];
                endcase''')
    return s

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
    assert not a.output.exists();a.output.parent.mkdir(parents=True,exist_ok=True)
    a.output.write_text(transform(a.source.read_text()))
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    a.output.with_suffix('.binding.json').write_text(json.dumps({'parent':str(a.source),'parent_sha256':sha(a.source),'candidate_sha256':sha(a.output),
        'scope':'Four-row lookahead; bank/row/mode/generation guards and current read-bank exclusion retained; no B/RX/DDR engine changes',
        'hardware_programmed':False},indent=2)+'\n')
    print(a.output)
