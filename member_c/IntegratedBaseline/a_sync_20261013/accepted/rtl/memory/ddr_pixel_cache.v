`timescale 1ns/1ps
`default_nettype none

// Two-entry, fully-associative cache for RGB888 pixels stored one per
// 32-bit DDR word. Cache lines are the DDR IP's 256-bit / eight-word beats.
// base_word_addr must be eight-word aligned, and the frame must fit the 28-bit
// word address space without overflow.
module ddr_pixel_cache (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          invalidate,

    input  wire          mem_valid,
    output wire          mem_ready,
    input  wire [23:0]   mem_addr,
    output reg           mem_rsp_valid,
    output reg  [23:0]   mem_rgb,
    input  wire [27:0]   base_word_addr,

    output wire          cmd_valid,
    input  wire          cmd_ready,
    output wire          cmd_write,
    output reg  [27:0]   cmd_addr,
    output wire [255:0]  cmd_wdata,
    output wire [31:0]   cmd_wstrb,

    input  wire          rsp_valid,
    input  wire          rsp_write,
    input  wire [255:0]  rsp_rdata
);

    localparam [1:0] ST_IDLE = 2'd0;
    localparam [1:0] ST_CMD  = 2'd1;
    localparam [1:0] ST_RSP  = 2'd2;

    reg [1:0] state;
    reg valid0, valid1;
    reg [24:0] tag0, tag1;
    reg [255:0] data0, data1;
    reg replace_way;

    reg [24:0] miss_tag;
    reg [2:0] miss_offset;
    reg miss_way;
    reg invalidate_pending;

    wire [27:0] req_line_addr = base_word_addr + {4'd0, mem_addr[23:3], 3'b000};
    wire [24:0] req_tag = req_line_addr[27:3];
    wire hit0 = valid0 && (tag0 == req_tag);
    wire hit1 = valid1 && (tag1 == req_tag);

    assign mem_ready = rst_n && (state == ST_IDLE);
    assign cmd_valid = rst_n && (state == ST_CMD);
    assign cmd_write = 1'b0;
    assign cmd_wdata = 256'd0;
    assign cmd_wstrb = 32'd0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            valid0 <= 1'b0;
            valid1 <= 1'b0;
            tag0 <= 25'd0;
            tag1 <= 25'd0;
            data0 <= 256'd0;
            data1 <= 256'd0;
            replace_way <= 1'b0;
            miss_tag <= 25'd0;
            miss_offset <= 3'd0;
            miss_way <= 1'b0;
            cmd_addr <= 28'd0;
            invalidate_pending <= 1'b0;
            mem_rsp_valid <= 1'b0;
            mem_rgb <= 24'd0;
        end else begin
            mem_rsp_valid <= 1'b0;

            case (state)
                ST_IDLE: begin
                    invalidate_pending <= 1'b0;
                    if (invalidate) begin
                        valid0 <= 1'b0;
                        valid1 <= 1'b0;
                    end

                    if (mem_valid && mem_ready) begin
                        if (!invalidate && hit0) begin
                            mem_rgb <= data0[mem_addr[2:0]*32 +: 24];
                            mem_rsp_valid <= 1'b1;
                            replace_way <= 1'b1;
                        end else if (!invalidate && hit1) begin
                            mem_rgb <= data1[mem_addr[2:0]*32 +: 24];
                            mem_rsp_valid <= 1'b1;
                            replace_way <= 1'b0;
                        end else begin
                            miss_tag <= req_tag;
                            miss_offset <= mem_addr[2:0];
                            cmd_addr <= req_line_addr;
                            if (invalidate || !valid0)
                                miss_way <= 1'b0;
                            else if (!valid1)
                                miss_way <= 1'b1;
                            else
                                miss_way <= replace_way;
                            state <= ST_CMD;
                        end
                    end
                end

                ST_CMD: begin
                    if (invalidate)
                        invalidate_pending <= 1'b1;
                    if (cmd_ready) begin
                        if (rsp_valid) begin
                            mem_rgb <= rsp_write ? 24'd0 : rsp_rdata[miss_offset*32 +: 24];
                            mem_rsp_valid <= 1'b1;
                            if (invalidate || invalidate_pending || rsp_write) begin
                                valid0 <= 1'b0;
                                valid1 <= 1'b0;
                            end else if (miss_way) begin
                                valid1 <= 1'b1;
                                tag1 <= miss_tag;
                                data1 <= rsp_rdata;
                                replace_way <= 1'b0;
                            end else begin
                                valid0 <= 1'b1;
                                tag0 <= miss_tag;
                                data0 <= rsp_rdata;
                                replace_way <= 1'b1;
                            end
                            invalidate_pending <= 1'b0;
                            state <= ST_IDLE;
                        end else begin
                            state <= ST_RSP;
                        end
                    end
                end

                ST_RSP: begin
                    if (invalidate)
                        invalidate_pending <= 1'b1;
                    if (rsp_valid) begin
                        mem_rgb <= rsp_write ? 24'd0 : rsp_rdata[miss_offset*32 +: 24];
                        mem_rsp_valid <= 1'b1;
                        if (invalidate || invalidate_pending || rsp_write) begin
                            valid0 <= 1'b0;
                            valid1 <= 1'b0;
                        end else if (miss_way) begin
                            valid1 <= 1'b1;
                            tag1 <= miss_tag;
                            data1 <= rsp_rdata;
                            replace_way <= 1'b0;
                        end else begin
                            valid0 <= 1'b1;
                            tag0 <= miss_tag;
                            data0 <= rsp_rdata;
                            replace_way <= 1'b1;
                        end
                        invalidate_pending <= 1'b0;
                        state <= ST_IDLE;
                    end
                end

                default: begin
                    state <= ST_IDLE;
                    valid0 <= 1'b0;
                    valid1 <= 1'b0;
                    invalidate_pending <= 1'b0;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
