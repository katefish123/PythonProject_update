"""Extend C's source-prefetch engine, retaining both independent caches."""
from pathlib import Path
import argparse


def transform(code):
    def once(old, new):
        nonlocal code
        assert code.count(old) == 1, old
        code = code.replace(old, new)

    once('parameter integer WATCHDOG_CYCLES = 1024,',
         'parameter integer WATCHDOG_CYCLES = 1024,\n    parameter integer CAPTURE_BURST_BEATS=1,')
    once('input  wire [31:0]   cmd_wstrb,',
         'input  wire [31:0]   cmd_wstrb,\n    input wire [2047:0] capture_burst_data,')
    once('output reg           fault,', 'output reg           fault,\n    output reg [3:0] fault_reason,')
    once('reg [31:0] watchdog_count;', '''reg [31:0] watchdog_count;
    reg write_burst;
    reg [3:0] write_index;
    reg [2047:0] write_buffer;
    wire source_write=cmd_write &&
        ((cmd_addr>=SOURCE_BASE0 && cmd_addr<SOURCE_BASE0+SOURCE_WORDS) ||
         (cmd_addr>=SOURCE_BASE1 && cmd_addr<SOURCE_BASE1+SOURCE_WORDS));
    wire capture_command=CAPTURE_BURST_BEATS>1 && source_write;''')
    once("assign axi_awlen = 4'b0000;", "assign axi_awlen = write_burst?CAPTURE_BURST_BEATS-1:4'd0;")
    once('assign axi_wdata = wdata_hold;',
         'assign axi_wdata = write_burst?write_buffer[write_index*256+:256]:wdata_hold;')
    once('state <= ST_IDLE;\n            addr_hold',
         'state <= ST_IDLE;write_burst<=0;write_index<=0;write_buffer<=0;fault_reason<=0;\n            addr_hold')
    once('                        addr_hold <= cmd_addr;',
         '                        write_burst<=capture_command;write_index<=0;write_buffer<=capture_burst_data;\n                        addr_hold <= cmd_addr;')
    once("if (cmd_addr[2:0] != 3'b000) begin", "if (cmd_addr[2:0] != 3'b000 || (capture_command && (cmd_addr[5:0]!=0 || !source_block_safe))) begin")
    once("// by one 256-bit beat. Retire with zero data.\n                            fault <= 1'b1;",
         "// by one 256-bit beat. Retire with zero data.\n                            fault_reason<=1;fault <= 1'b1;")
    # Preserve source and result cache invalidation on command acceptance.
    code = code.replace('fault<=1;cache_valid<=0;', 'fault_reason<=3;fault<=1;cache_valid<=0;')
    # Both AW/W same-edge and later W consumption share exactly the same rule.
    old = """                            if (axi_wusero_id !== 4'b0000 || axi_wusero_last !== 1'b1)
                                fault <= 1'b1;
                            state <= ST_RSP;"""
    once(old, '                            receive_write;')
    old = """                        if (axi_wusero_id !== 4'b0000 || axi_wusero_last !== 1'b1)
                            fault <= 1'b1;
                        state <= ST_RSP;"""
    once(old, '                        receive_write;')
    once('    always @(posedge clk or negedge rst_n) begin', '''    task receive_write;
        begin
            if(axi_wusero_id!==4'd0 || axi_wusero_last!==(write_burst?(write_index==CAPTURE_BURST_BEATS-1):1'b1))begin
                fault_reason<=2;fault<=1;state<=ST_RSP;
            end else if(!write_burst || write_index==CAPTURE_BURST_BEATS-1)begin
                write_burst<=0;state<=ST_RSP;
            end else begin
                write_index<=write_index+1'b1;watchdog_count<=0;state<=ST_W;
            end
        end
    endtask

    always @(posedge clk or negedge rst_n) begin''')
    for state, reason in [('ST_AW', 4), ('ST_W', 5), ('ST_AR', 6), ('ST_R', 7)]:
        begin = code.index('                '+state+': begin')
        end = code.index('\n                end', begin)
        section = code[begin:end].replace("fault <= 1'b1;", f"fault_reason<=4'd{reason};fault <= 1'b1;")
        code = code[:begin]+section+code[end:]
    return code


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(transform(args.input.read_text()))
