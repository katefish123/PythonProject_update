module reset_sync (
    input  wire clk,
    input  wire async_rst_n,
    output wire sync_rst_n
);

    reg sync_ff1 /* synthesis syn_preserve = 1 */;
    reg sync_ff2 /* synthesis syn_preserve = 1 */;

    always @(posedge clk or negedge async_rst_n) begin
        if (!async_rst_n) begin
            sync_ff1 <= 1'b0;
            sync_ff2 <= 1'b0;
        end
        else begin
            sync_ff1 <= 1'b1;
            sync_ff2 <= sync_ff1;
        end
    end

    assign sync_rst_n = sync_ff2;

endmodule
