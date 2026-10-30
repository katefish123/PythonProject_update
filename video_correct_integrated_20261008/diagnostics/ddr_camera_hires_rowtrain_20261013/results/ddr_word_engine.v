`timescale 1ns/1ps
`default_nettype none

// Single-outstanding, single-256-bit-beat adapter for the PG2L100H DDR IP.
// Addresses are 32-bit word addresses; one beat covers eight words.
module ddr_word_engine #(
    parameter integer WATCHDOG_CYCLES = 1024,
    parameter integer READ_AHEAD_ENABLE = 0,
    parameter integer RESULT_WORDS = 640*904,
    parameter [27:0] RESULT_BASE0 = 28'h0100000,
    parameter [27:0] RESULT_BASE1 = 28'h0200000
) (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          init_done,

    input  wire          cmd_valid,
    output wire          cmd_ready,
    input  wire          cmd_write,
    input  wire [27:0]   cmd_addr,
    input  wire [255:0]  cmd_wdata,
    input  wire [31:0]   cmd_wstrb,

    output wire          rsp_valid,
    output reg           rsp_write,
    output reg  [255:0]  rsp_rdata,
    output reg           fault,

    output wire [27:0]   axi_awaddr,
    output wire          axi_awuser_ap,
    output wire [3:0]    axi_awuser_id,
    output wire [3:0]    axi_awlen,
    output wire          axi_awvalid,
    input  wire          axi_awready,

    output wire [255:0]  axi_wdata,
    output wire [31:0]   axi_wstrb,
    input  wire          axi_wready,
    input  wire [3:0]    axi_wusero_id,
    input  wire          axi_wusero_last,

    output wire [27:0]   axi_araddr,
    output wire          axi_aruser_ap,
    output wire [3:0]    axi_aruser_id,
    output wire [3:0]    axi_arlen,
    output wire          axi_arvalid,
    input  wire          axi_arready,

    input  wire [255:0]  axi_rdata,
    input  wire [3:0]    axi_rid,
    input  wire          axi_rlast,
    input  wire          axi_rvalid
);

    localparam [2:0] ST_IDLE = 3'd0;
    localparam [2:0] ST_AW   = 3'd1;
    localparam [2:0] ST_W    = 3'd2;
    localparam [2:0] ST_AR   = 3'd3;
    localparam [2:0] ST_R    = 3'd4;
    localparam [2:0] ST_RSP  = 3'd5;

    reg [2:0] state;
    reg [27:0] addr_hold;
    reg [255:0] wdata_hold;
    reg [31:0] wstrb_hold;
    reg [31:0] watchdog_count;
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
    endtask

    // A sticky protocol/timeout fault is a hard stop until the shared DDR
    // reset flushes both this adapter and the DDR IP's in-flight responses.
    assign cmd_ready = rst_n && init_done && !fault && (state == ST_IDLE);
    assign rsp_valid = rst_n && (state == ST_RSP);

    assign axi_awaddr = addr_hold;
    assign axi_awuser_ap = 1'b0;
    assign axi_awuser_id = 4'b0000;
    assign axi_awlen = 4'b0000;
    assign axi_awvalid = (state == ST_AW);

    // There is no WVALID on this IP. Keep the beat stable from command
    // acceptance through the WREADY consumption edge.
    assign axi_wdata = wdata_hold;
    assign axi_wstrb = wstrb_hold;

    assign axi_araddr = read_burst?{addr_hold[27:6],6'b0}:addr_hold;
    assign axi_aruser_ap = 1'b0;
    assign axi_aruser_id = 4'b0000;
    assign axi_arlen = read_burst?4'd7:4'd0;
    assign axi_arvalid = (state == ST_AR);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            addr_hold <= 28'd0;
            wdata_hold <= 256'd0;
            wstrb_hold <= 32'd0;
            watchdog_count <= 32'd0;
            rsp_write <= 1'b0;
            rsp_rdata <= 256'd0;
            fault <= 1'b0;cache_valid<=0;cache_tag<=0;read_burst<=0;read_index<=0;
        end else begin
            case (state)
                ST_IDLE: begin
                    watchdog_count <= 32'd0;
                    if (cmd_valid && cmd_ready) begin
                        addr_hold <= cmd_addr;
                        wdata_hold <= cmd_wdata;
                        wstrb_hold <= cmd_wstrb;
                        rsp_write <= cmd_write;
                        rsp_rdata <= 256'd0;
                        read_burst<=0;read_index<=0;
                        if(cmd_write && cache_valid && cache_tag==cmd_addr[27:6])cache_valid<=0;
                        if (cmd_addr[2:0] != 3'b000) begin
                            // Misaligned block commands cannot be represented
                            // by one 256-bit beat. Retire with zero data.
                            fault <= 1'b1;
                            state <= ST_RSP;
                        end else if (cmd_write) begin
                            state <= ST_AW;
                        end else if(cache_hit)begin
                            rsp_rdata<=result_cache[cmd_addr[5:3]];state<=ST_RSP;
                        end else begin
                            read_burst<=result_read;
                            if(result_read)cache_valid<=0;
                            state <= ST_AR;
                        end
                    end
                end

                ST_AW: begin
                    if (axi_awready) begin
                        if (axi_wready) begin
                            if (axi_wusero_id !== 4'b0000 || axi_wusero_last !== 1'b1)
                                fault <= 1'b1;
                            state <= ST_RSP;
                        end else begin
                            state <= ST_W;
                        end
                    end else if (watchdog_count >= WATCHDOG_CYCLES-1) begin
                        fault <= 1'b1;
                        rsp_rdata <= 256'd0;
                        state <= ST_RSP;
                    end else begin
                        watchdog_count <= watchdog_count + 1'b1;
                    end
                end

                ST_W: begin
                    if (axi_wready) begin
                        if (axi_wusero_id !== 4'b0000 || axi_wusero_last !== 1'b1)
                            fault <= 1'b1;
                        state <= ST_RSP;
                    end else if (watchdog_count >= WATCHDOG_CYCLES-1) begin
                        fault <= 1'b1;
                        rsp_rdata <= 256'd0;
                        state <= ST_RSP;
                    end else begin
                        watchdog_count <= watchdog_count + 1'b1;
                    end
                end

                ST_AR: begin
                    if (axi_arready) begin
                        if (axi_rvalid) begin
                            receive_read;
                        end else begin
                            state <= ST_R;
                        end
                    end else if (watchdog_count >= WATCHDOG_CYCLES-1) begin
                        fault <= 1'b1;
                        rsp_rdata <= 256'd0;
                        state <= ST_RSP;
                    end else begin
                        watchdog_count <= watchdog_count + 1'b1;
                    end
                end

                ST_R: begin
                    if (axi_rvalid) begin
                        // No RREADY exists; consecutive beats cannot be dropped.
                        receive_read;
                    end else if (watchdog_count >= WATCHDOG_CYCLES-1) begin
                        fault <= 1'b1;
                        rsp_rdata <= 256'd0;
                        state <= ST_RSP;
                    end else begin
                        watchdog_count <= watchdog_count + 1'b1;
                    end
                end

                ST_RSP: begin
                    watchdog_count <= 32'd0;
                    state <= ST_IDLE;
                end

                default: begin
                    fault <= 1'b1;
                    rsp_rdata <= 256'd0;
                    rsp_write <= 1'b0;
                    state <= ST_RSP;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
