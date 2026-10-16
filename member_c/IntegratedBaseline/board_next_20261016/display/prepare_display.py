"""Derive this isolated display candidate from immutable frozen S, never edit S."""
from pathlib import Path
import hashlib
import json

HERE=Path(__file__).resolve().parent
SOURCE=Path('D:/FPGA/output/c_stream_board_v4s_20261016/rtl/stream/ddr_result_display_block64.v')

def build():
    text=SOURCE.read_text()
    def replace(old,new,count=1):
        nonlocal text
        assert text.count(old)==count,(old,text.count(old),count)
        text=text.replace(old,new)
    replace('module ddr_result_display_block64 #(', 'module ddr_result_display_raw_corrected #(')
    replace('parameter OUT_W=320, OUT_H=452, SCALE=2,',
            'parameter OUT_W=768, OUT_H=1080, SCALE=1,\n    parameter SRC_W=1920,SRC_H=1080,')
    replace("parameter [27:0] BASE1=28'h0200000", "parameter [27:0] BASE1=28'h0400000,\n    parameter [27:0] SOURCE_BASE0=28'd0,SOURCE_BASE1=28'h0800000")
    replace("parameter [27:0] BASE0=28'h0100000", "parameter [27:0] BASE0=28'h0200000")
    replace('input  wire         publish_bank,', 'input  wire         publish_bank,\n    input wire publish_raw,output reg display_raw,\n    output wire scan_frame_pulse,output reg image_swap_pulse,')
    replace('output wire         cmd_valid,', 'output wire         cmd_valid,\n    output wire cmd_source_block,')
    replace('localparam WIN_X=(H_ACTIVE-OUT_W*SCALE)/2;',
            'wire [11:0] visible_width=display_raw?SRC_W:OUT_W;\n    wire [11:0] WIN_X=(H_ACTIVE-visible_width)/2;')
    replace('localparam X0=H_SYNC+H_BACK+WIN_X;', 'wire [11:0] X0=H_SYNC+H_BACK+WIN_X;')
    replace('localparam BURSTS_PER_ROW=OUT_W/8;',
            'localparam MAX_W=(SRC_W>OUT_W)?SRC_W:OUT_W;\n    localparam BURSTS_PER_ROW=MAX_W/8;')
    replace('reg req_bank;', 'reg req_bank,req_raw;')
    replace('reg want_valid, want_bank;', 'reg want_valid, want_bank,want_raw;')
    replace('reg line_bank0, line_bank1;', 'reg line_bank0, line_bank1,line_raw0,line_raw1;')
    replace('localparam BLOCK_PIXELS=(OUT_W%64==0)?64:8;\n    localparam BLOCK_BEATS=BLOCK_PIXELS/8;',
            'localparam BLOCK_PIXELS=64;\n    localparam BLOCK_BEATS=8;')
    replace('reg[15:0]ui_line_gen;', 'reg[15:0]ui_line_gen;reg ui_line_raw;\n    reg[BURST_BITS:0]ui_row_beats;')
    replace('assign cmd_addr=cmd_addr_r;', 'assign cmd_addr=cmd_addr_r;\n    assign cmd_source_block=ui_line_raw;')
    replace('ui_state<=UI_IDLE;ui_line_gen<=0;ui_line_row<=0;burst_index<=0;',
            'ui_state<=UI_IDLE;ui_line_gen<=0;ui_line_raw<=0;ui_row_beats<=OUT_W/8;ui_line_row<=0;burst_index<=0;')
    replace('ui_req_seen<=req_sync_ui[2];ui_line_gen<=req_gen;ui_line_row<=req_row;\n         active_base<=req_bank?BASE1:BASE0;burst_index<=0;\n         cmd_addr_r<=(req_bank?BASE1:BASE0)+req_row*OUT_W;',
            'ui_req_seen<=req_sync_ui[2];ui_line_gen<=req_gen;ui_line_row<=req_row;\n         ui_line_raw<=req_raw;ui_row_beats<=req_raw?SRC_W/8:OUT_W/8;\n         active_base<=req_raw?(req_bank?SOURCE_BASE1:SOURCE_BASE0):(req_bank?BASE1:BASE0);burst_index<=0;\n         cmd_addr_r<=(req_raw?(req_bank?SOURCE_BASE1:SOURCE_BASE0):(req_bank?BASE1:BASE0))+req_row*(req_raw?SRC_W:OUT_W);')
    replace('if(burst_index==BURSTS_PER_ROW-1)begin', 'if(burst_index==ui_row_beats-1)begin')
    replace('(* ASYNC_REG="TRUE" *) reg [2:0] pub_toggle_sync, pub_bank_sync;',
            '(* ASYNC_REG="TRUE" *) reg [2:0] pub_toggle_sync, pub_bank_sync,pub_raw_sync;')
    replace('pub_toggle_sync<=0; pub_bank_sync<=0; ui_ack_sync<=0;', 'pub_toggle_sync<=0; pub_bank_sync<=0;pub_raw_sync<=0; ui_ack_sync<=0;')
    replace('pub_bank_sync<={pub_bank_sync[1:0],publish_bank};',
            'pub_bank_sync<={pub_bank_sync[1:0],publish_bank};\n            pub_raw_sync<={pub_raw_sync[1:0],publish_raw};')
    replace('line_gen0==display_gen;', 'line_gen0==display_gen && line_raw0==display_raw;',2)
    replace('line_gen1==display_gen;', 'line_gen1==display_gen && line_raw1==display_raw;',2)
    replace('hc<X0+OUT_W*SCALE', 'hc<X0+visible_width')
    replace('ack_toggle<=0; display_bank<=0; display_gen<=0; image_valid<=0; underrun<=0;',
            'ack_toggle<=0; display_bank<=0;display_raw<=0;image_swap_pulse<=0; display_gen<=0; image_valid<=0; underrun<=0;')
    replace('req_toggle<=0; req_bank<=0; req_gen<=0; req_row<=0;', 'req_toggle<=0; req_bank<=0;req_raw<=0; req_gen<=0; req_row<=0;')
    replace('want_valid<=0; want_bank<=0; want_gen<=0; want_row<=0;', 'want_valid<=0; want_bank<=0;want_raw<=0; want_gen<=0; want_row<=0;')
    replace('line_valid<=0; line_row0<=0; line_row1<=0; line_bank0<=0; line_bank1<=0;',
            'line_valid<=0; line_row0<=0; line_row1<=0; line_bank0<=0; line_bank1<=0;line_raw0<=0;line_raw1<=0;')
    replace('ack_sync_pix<={ack_sync_pix[1:0],ui_ack_toggle};',
            'image_swap_pulse<=0;\n            ack_sync_pix<={ack_sync_pix[1:0],ui_ack_toggle};')
    replace('line_gen1<=req_gen;', 'line_gen1<=req_gen;line_raw1<=req_raw;')
    replace('line_gen0<=req_gen;', 'line_gen0<=req_gen;line_raw0<=req_raw;')
    replace('display_bank<=pub_bank_sync[2];display_gen<=display_gen+1\'b1;',
            'display_bank<=pub_bank_sync[2];display_raw<=pub_raw_sync[2];image_swap_pulse<=1;display_gen<=display_gen+1\'b1;')
    replace('want_bank<=pub_bank_sync[2];want_gen', 'want_bank<=pub_bank_sync[2];want_raw<=pub_raw_sync[2];want_gen')
    replace('line_gen0==display_gen) &&', 'line_gen0==display_gen && line_raw0==display_raw) &&')
    replace('line_gen1==display_gen)) begin', 'line_gen1==display_gen && line_raw1==display_raw)) begin')
    replace('want_bank<=display_bank;want_gen', 'want_bank<=display_bank;want_raw<=display_raw;want_gen',3)
    replace('req_row<=want_row;req_bank<=want_bank;req_gen<=want_gen;',
            'req_row<=want_row;req_bank<=want_bank;req_raw<=want_raw;req_gen<=want_gen;')
    replace('assign scan_de=vtc_de;assign scan_start=frame_start;assign scan_reset_n=pix_local_rst_n;',
            'assign scan_de=vtc_de;assign scan_start=frame_start;assign scan_frame_pulse=frame_start;assign scan_reset_n=pix_local_rst_n;')
    replace('endmodule\n\n`default_nettype wire', '''// synthesis translate_off
    initial begin
        if(SCALE!=1 || SRC_H!=OUT_H)$fatal(1,"RAW/CORRECTED requires SCALE1 and equal heights");
        if(SRC_W%64!=0 || OUT_W%64!=0 || SRC_W<64 || OUT_W<64)$fatal(1,"row widths must be positive multiples64");
        if(SRC_W>H_ACTIVE || OUT_W>H_ACTIVE || OUT_H>V_ACTIVE || OUT_H<1)$fatal(1,"window exceeds canvas");
    end
    // synthesis translate_on
endmodule

`default_nettype wire''')
    # Credit and metadata retirement must see precisely the same physical ACK
    # synchronizer. Independent chains can resolve on different PIX cycles.
    replace('    (* ASYNC_REG="TRUE" *) reg [2:0] ack_sync_pix;\n','')
    replace('ack_sync_pix<=0; ack_seen_pix<=0;','ack_seen_pix<=0;')
    replace('            ack_sync_pix<={ack_sync_pix[1:0],ui_ack_toggle};\n','')
    replace('req_toggle==ack_sync_pix[2]', 'req_toggle==ui_ack_sync[2]')
    header='''// Isolated board_next candidate, derived from frozen S. One VTC, RAW1:1 and
// CORRECTED1:1. Root owns source/result leases and grant-qualified sidebands.
// Mode is a held payload on both toggle mailboxes. All resets share assertion.
'''
    target=HERE/'ddr_result_display_raw_corrected.v'
    target.write_text(header+text)
    manifest={'source':str(SOURCE),'source_sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
              'candidate':str(target),'candidate_sha256':hashlib.sha256(target.read_bytes()).hexdigest(),
              'physical_timing_qualified':False,'hardware_accepted':False}
    (HERE/'source_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print('ISOLATED_DISPLAY_GENERATED; no PDS or board acceptance')

if __name__=='__main__':build()
