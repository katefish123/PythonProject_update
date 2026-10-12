"""Prototype an internal eight-beat result read cache, retaining the public single-beat API."""
from pathlib import Path
import hashlib
import json

D=Path(__file__).resolve().parent
R=D.parents[1]
O=D/"results"
O.mkdir(exist_ok=True)
baseline=json.loads((R/"release/ddr_camera_hires_20261011/source_hashes.json").read_text(encoding="utf-8-sig"))
p=R/"rtl/memory/ddr_word_engine.v"
assert baseline[str(p)]==hashlib.sha256(p.read_bytes()).hexdigest()
text=p.read_text(encoding="utf-8-sig")
def change(before,after):
    global text
    assert text.count(before)==1,before
    text=text.replace(before,after)
change('parameter integer WATCHDOG_CYCLES = 1024', '''parameter integer WATCHDOG_CYCLES = 1024,
    parameter integer READ_AHEAD_ENABLE = 0,
    parameter integer RESULT_WORDS = 640*904,
    parameter [27:0] RESULT_BASE0 = 28'h0100000,
    parameter [27:0] RESULT_BASE1 = 28'h0200000''')
change('reg [31:0] watchdog_count;', '''reg [31:0] watchdog_count;
    reg cache_valid,read_burst;
    reg [21:0] cache_tag;
    reg [2:0] read_index;
    reg [255:0] result_cache[0:7];
    wire [27:0] request_block={cmd_addr[27:6],6'b0};
    wire result_read=READ_AHEAD_ENABLE && !cmd_write &&
        ((request_block>=RESULT_BASE0 && request_block+28'd63<RESULT_BASE0+RESULT_WORDS) ||
         (request_block>=RESULT_BASE1 && request_block+28'd63<RESULT_BASE1+RESULT_WORDS));
    wire cache_hit=result_read && cache_valid && cache_tag==cmd_addr[27:6];

    // Public clients still receive exactly one response for one accepted command.
    // A cache fill consumes every unbackpressurable IP beat before responding.
    task receive_read;
        begin
            if(read_burst)begin
                if(axi_rid!==4'd0 || axi_rlast!==(read_index==3'd7))begin
                    fault<=1;cache_valid<=0;rsp_rdata<=0;state<=ST_RSP;
                end else begin
                    result_cache[read_index]<=axi_rdata;
                    if(read_index==3'd7)begin
                        cache_tag<=addr_hold[27:6];cache_valid<=1;
                        rsp_rdata<=(addr_hold[5:3]==3'd7) ? axi_rdata : result_cache[addr_hold[5:3]];
                        state<=ST_RSP;
                    end else begin
                        read_index<=read_index+1'b1;watchdog_count<=0;state<=ST_R;
                    end
                end
            end else begin
                rsp_rdata<=axi_rdata;
                if(axi_rid!==4'd0 || axi_rlast!==1'b1)begin fault<=1;cache_valid<=0;end
                state<=ST_RSP;
            end
        end
    endtask''')
change('assign axi_araddr = addr_hold;', 'assign axi_araddr = read_burst?{addr_hold[27:6],6\'b0}:addr_hold;')
change('assign axi_arlen = 4\'b0000;', 'assign axi_arlen = read_burst?4\'d7:4\'d0;')
change('fault <= 1\'b0;', 'fault <= 1\'b0;cache_valid<=0;cache_tag<=0;read_burst<=0;read_index<=0;')
change('rsp_rdata <= 256\'d0;\n                        if (cmd_addr[2:0]', '''rsp_rdata <= 256'd0;
                        read_burst<=0;read_index<=0;
                        if(cmd_write && cache_valid && cache_tag==cmd_addr[27:6])cache_valid<=0;
                        if (cmd_addr[2:0]''')
change('''                        end else begin
                            state <= ST_AR;
                        end''', '''                        end else if(cache_hit)begin
                            rsp_rdata<=result_cache[cmd_addr[5:3]];state<=ST_RSP;
                        end else begin
                            read_burst<=result_read;
                            if(result_read)cache_valid<=0;
                            state <= ST_AR;
                        end''')
change('''                            rsp_rdata <= axi_rdata;
                            if (axi_rid !== 4'b0000 || axi_rlast !== 1'b1)
                                fault <= 1'b1;
                            state <= ST_RSP;''', '                            receive_read;')
change('''                        // No RREADY exists; every valid beat is captured now.
                        rsp_rdata <= axi_rdata;
                        if (axi_rid !== 4'b0000 || axi_rlast !== 1'b1)
                            fault <= 1'b1;
                        state <= ST_RSP;''', '                        // No RREADY exists; consecutive beats cannot be dropped.\n                        receive_read;')
target=O/"ddr_word_engine.v"
target.write_text(text,encoding="utf-8")
record={"prototype_only":True,"programmed":False,"qualified_for_board":False,
    "interface":"Existing single-command / single-response 256-bit client API retained.",
    "implementation":"Only completed-result ranges may fill an aligned 64-word cache using ARLEN=7. Cache publishes after all eight valid beats; overlapping writes invalidate it. Source reads/BIST/writes retain single-beat behavior.",
    "protocol_source":"C:/pango/PDS_2022.2-SP6.4/ip/system_ip/ips2l_hmic_s/ips2l_hmic_eval/ips2l_hmic_s/UG042003_Logos2_HMIC_S_IP.pdf, pp31-38; ARLEN+1 beat count and no RREADY.",
    "engine_sha256":hashlib.sha256(target.read_bytes()).hexdigest(),
    "limit":"Independent unit/integrated display regression, synthesis/timing and actual board comparison required. Current board diagnostic must first confirm the row deadline."}
(O/"prototype.json").write_text(json.dumps(record,indent=2)+"\n",encoding="utf-8")
print("Prepared unprogrammed result read-ahead prototype with unchanged external command interface.")
