 module ROI_Box_Adjust #(
      parameter IMG_WIDTH   = 1920,
      parameter IMG_HEIGHT  = 1080,
      parameter X_BITS      = 12,
      parameter Y_BITS      = 12,

      // 固定扩边
      parameter PAD_X       = 8,
      parameter PAD_Y       = 4
  )(
      input  wire                 clk,
      input  wire                 rst_n,

      input  wire                 roi_valid_in,
      input  wire [X_BITS-1:0]    roi_x1_in,
      input  wire [Y_BITS-1:0]    roi_y1_in,
      input  wire [X_BITS-1:0]    roi_x2_in,
      input  wire [Y_BITS-1:0]    roi_y2_in,

      output reg                  roi_valid_out,
      output reg [X_BITS-1:0]     roi_x1_out,
      output reg [Y_BITS-1:0]     roi_y1_out,
      output reg [X_BITS-1:0]     roi_x2_out,
      output reg [Y_BITS-1:0]     roi_y2_out
  );

      always @(posedge clk or negedge rst_n) begin
          if(!rst_n) begin
              roi_valid_out <= 1'b0;
              roi_x1_out    <= {X_BITS{1'b0}};
              roi_y1_out    <= {Y_BITS{1'b0}};
              roi_x2_out    <= {X_BITS{1'b0}};
              roi_y2_out    <= {Y_BITS{1'b0}};
          end
          else begin
              if(roi_valid_in) begin
                  roi_valid_out <= 1'b1;

                  if(roi_x1_in > PAD_X)
                      roi_x1_out <= roi_x1_in - PAD_X;
                  else
                      roi_x1_out <= {X_BITS{1'b0}};

                  if(roi_y1_in > PAD_Y)
                      roi_y1_out <= roi_y1_in - PAD_Y;
                  else
                      roi_y1_out <= {Y_BITS{1'b0}};

                  if(({1'b0, roi_x2_in} + PAD_X) < IMG_WIDTH)
                      roi_x2_out <= roi_x2_in + PAD_X;
                  else
                      roi_x2_out <= IMG_WIDTH - 1;

                  if(({1'b0, roi_y2_in} + PAD_Y) < IMG_HEIGHT)
                      roi_y2_out <= roi_y2_in + PAD_Y;
                  else
                      roi_y2_out <= IMG_HEIGHT - 1;
              end
              else begin
                  roi_valid_out <= 1'b0;
                  roi_x1_out    <= {X_BITS{1'b0}};
                  roi_y1_out    <= {Y_BITS{1'b0}};
                  roi_x2_out    <= {X_BITS{1'b0}};
                  roi_y2_out    <= {Y_BITS{1'b0}};
              end
          end
      end

  endmodule