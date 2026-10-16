`timescale 1ns/1ps
module ddr3_ip #(
 
   parameter MEM_ROW_WIDTH       = 15          ,
    
   parameter MEM_COLUMN_WIDTH    = 10          ,
   
   parameter MEM_BANK_WIDTH      = 3           ,
  
  parameter MEM_DQ_WIDTH         =  32         ,
  
  parameter MEM_DM_WIDTH         =  4         ,
  
  parameter MEM_DQS_WIDTH        =  4         ,
   
   parameter CTRL_ADDR_WIDTH     = MEM_ROW_WIDTH + MEM_COLUMN_WIDTH + MEM_BANK_WIDTH        
  )(                                                              
   input                              ref_clk                       ,    
   input                              resetn                        ,            
   output                             core_clk                      ,            
   output                             pll_lock                      ,    
   output                             phy_pll_lock                  ,
   output                             gpll_lock                     ,        
   output                             rst_gpll_lock                 ,            
   output                             ddrphy_cpd_lock               ,      
   output                             ddr_init_done                 ,            

   input  [CTRL_ADDR_WIDTH-1:0]       axi_awaddr                    ,
   input                              axi_awuser_ap                 ,
   input  [3:0]                       axi_awuser_id                 ,
   input  [3:0]                       axi_awlen                     ,
   output                             axi_awready                   ,
   input                              axi_awvalid                   ,

   input  [8*MEM_DQ_WIDTH-1:0]        axi_wdata                     ,
   input  [MEM_DQ_WIDTH-1:0]          axi_wstrb                     ,
   output                             axi_wready                    ,
   output [3:0]                       axi_wusero_id                 ,
   output                             axi_wusero_last               ,

   input  [CTRL_ADDR_WIDTH-1:0]       axi_araddr                    ,
   input                              axi_aruser_ap                 ,
   input  [3:0]                       axi_aruser_id                 ,
   input  [3:0]                       axi_arlen                     ,
   output                             axi_arready                   ,
   input                              axi_arvalid                   ,

   output [8*MEM_DQ_WIDTH-1:0]        axi_rdata                     ,
   output [3:0]                       axi_rid                       ,
   output                             axi_rlast                     ,
   output                             axi_rvalid                    ,

   input                              apb_clk                       ,
   input                              apb_rst_n                     ,
   input                              apb_sel                       ,
   input                              apb_enable                    ,
   input  [7:0]                       apb_addr                      ,
   input                              apb_write                     ,
   output                             apb_ready                     ,
   input  [15:0]                      apb_wdata                     ,
   output [15:0]                      apb_rdata                     ,


   output                             mem_cs_n                      ,

   output                             mem_rst_n                     ,                       
   output                             mem_ck                        ,
   output                             mem_ck_n                      ,
   output                             mem_cke                       ,
   output                             mem_ras_n                     ,
   output                             mem_cas_n                     ,
   output                             mem_we_n                      , 
   output                             mem_odt                       ,
   output [MEM_ROW_WIDTH-1:0]         mem_a                         ,   
   output [MEM_BANK_WIDTH-1:0]        mem_ba                        ,   
   inout  [MEM_DQS_WIDTH-1:0]         mem_dqs                       ,
   inout  [MEM_DQS_WIDTH-1:0]         mem_dqs_n                     ,
   inout  [MEM_DQ_WIDTH-1:0]          mem_dq                        ,
   output [MEM_DM_WIDTH-1:0]          mem_dm                        , 

   //debug
   input                              dbg_gate_start                ,
   input                              dbg_cpd_start                 ,
   input                              dbg_ddrphy_rst_n              ,
   input                              dbg_gpll_scan_rst             ,

   input                              samp_position_dyn_adj         ,
   input  [8*MEM_DQS_WIDTH-1:0]       init_samp_position_even       ,
   input  [8*MEM_DQS_WIDTH-1:0]       init_samp_position_odd        ,

   input                              wrcal_position_dyn_adj        ,
   input  [8*MEM_DQS_WIDTH-1:0]       init_wrcal_position           ,
 
   input                              force_read_clk_ctrl           ,
   input  [4*MEM_DQS_WIDTH-1:0]       init_slip_step                ,  
   input  [3*MEM_DQS_WIDTH-1:0]       init_read_clk_ctrl            ,

   output [33:0]                      debug_calib_ctrl              ,
   output [17*MEM_DQS_WIDTH -1:0]     dbg_slice_status              ,
   output [22*MEM_DQS_WIDTH -1:0]     dbg_slice_state               ,
   output [69*MEM_DQS_WIDTH -1:0]     debug_data                    ,
   output [1:0]                       dbg_dll_upd_state             ,
   output [8:0]                       debug_gpll_dps_phase          ,
   
   output [2:0]                       dbg_rst_dps_state             ,
   output [5:0]                       dbg_tran_err_rst_cnt          ,
   output                             dbg_ddrphy_init_fail          , 
   
   input                              debug_cpd_offset_adj          ,
   input                              debug_cpd_offset_dir          ,
   input  [9:0]                       debug_cpd_offset              ,  
   output [9:0]                       debug_dps_cnt_dir0            , 
   output [9:0]                       debug_dps_cnt_dir1            ,

   input                              ck_dly_en                     ,
   input  [7:0]                       init_ck_dly_step              ,
   output [7:0]                       ck_dly_set_bin                ,
  
   output                             align_error                   ,
   output [3:0]                       debug_rst_state               ,
   output [3:0]                       debug_cpd_state               
);
 reg inject_align=0,inject_phy=0,inject_stall=0;
 reg[7:0]init_count=0;reg ready=0;
 assign core_clk=ref_clk;assign pll_lock=resetn;assign ddr_init_done=ready;
 assign dbg_ddrphy_init_fail=inject_phy;assign align_error=inject_align;
 always @(posedge ref_clk or negedge resetn)begin
 if(!resetn)begin init_count<=0;ready<=0;end
 else if(init_count<24)init_count<=init_count+1;else ready<=1;
 end
 localparam WORDS=128*48,RESULT_WORDS=64*48;
 reg[255:0]source0[0:WORDS/8-1],source1[0:WORDS/8-1],result0[0:RESULT_WORDS/8-1],result1[0:RESULT_WORDS/8-1],bist[0:255];
 reg writing=0,reading=0;reg[27:0]wa=0,ra=0;integer wi=0,wn=0,ri=0,rn=0,delay_left=0,tick=0;
 reg[255:0]rd=0;reg rv=0,rl=0;
 assign axi_awready=ready&&!inject_stall&&(tick%17>=2);
 assign axi_arready=ready&&!reading&&!inject_stall&&(tick%7!=0);
 assign axi_wready=ready&&!inject_stall&&(tick%11!=0);
 assign axi_wusero_id=0;assign axi_wusero_last=writing?wi==wn-1:axi_awlen==0;
 assign axi_rdata=rd;assign axi_rvalid=rv;assign axi_rlast=rl;assign axi_rid=0;
 function[255:0]read_word(input[27:0]a);
 if(a<WORDS)read_word=source0[a>>3];
 else if(a>=28'h0800000&&a<28'h0800000+WORDS)read_word=source1[(a-28'h0800000)>>3];
 else if(a>=28'h0200000&&a<28'h0200000+RESULT_WORDS)read_word=result0[(a-28'h0200000)>>3];
 else if(a>=28'h0400000&&a<28'h0400000+RESULT_WORDS)read_word=result1[(a-28'h0400000)>>3];
 else if(a>=28'h0600000&&a<28'h0600800)read_word=bist[(a-28'h0600000)>>3];
 else begin read_word=0;$fatal(1,"stub native read unmapped %h",a);end
 endfunction
 always @(posedge ref_clk or negedge resetn)begin: native
 reg[27:0]a;
 if(!resetn)begin writing<=0;reading<=0;wi<=0;ri<=0;delay_left<=0;tick<=0;end
 else begin
 tick<=tick+1;
 if(axi_awvalid&&axi_awready)begin
 if(writing)$fatal(1,"multiple native AW owners");
 writing<=1;wa<=axi_awaddr;wi<=0;wn<=axi_awlen+1;
 end
 if(axi_wready&&(writing||(axi_awvalid&&axi_awready)))begin
 a=writing?wa+wi*8:axi_awaddr;
 if(axi_wstrb!==32'hffffffff)$fatal(1,"invalid native write mask");
 if(a<WORDS)source0[a>>3]<=axi_wdata;
 else if(a>=28'h0800000&&a<28'h0800000+WORDS)source1[(a-28'h0800000)>>3]<=axi_wdata;
 else if(a>=28'h0200000&&a<28'h0200000+RESULT_WORDS)result0[(a-28'h0200000)>>3]<=axi_wdata;
 else if(a>=28'h0400000&&a<28'h0400000+RESULT_WORDS)result1[(a-28'h0400000)>>3]<=axi_wdata;
 else if(a>=28'h0600000&&a<28'h0600800)bist[(a-28'h0600000)>>3]<=axi_wdata;
 else $fatal(1,"stub native write unmapped %h",a);
 if(axi_wusero_last)begin writing<=0;wi<=0;end else begin writing<=1;wi<=writing?wi+1:1;end
 end
 if(axi_arvalid&&axi_arready)begin reading<=1;ra<=axi_araddr;ri<=0;rn<=axi_arlen+1;delay_left<=28;end
 // Read drive is registered on the opposite edge, matching the standalone
 // native protocol model. A common reset cancels both accepted transactions.
 end end
 always @(negedge ref_clk or negedge resetn)begin
 if(!resetn)begin rv<=0;rl<=0;rd<=0;end
 else begin rv<=0;rl<=0;
 if(reading&&!inject_stall)begin
 if(delay_left>0)delay_left<=delay_left-1;
 else begin rv<=1;rl<=ri==rn-1;rd<=read_word(ra+ri*8);ri<=ri+1;if(ri==rn-1)reading<=0;end
 end end end
endmodule
module GTP_INBUFDS(input I,IB,output O);assign O=I;endmodule
module video_pll_27m_148m5(input clkin1,output reg clkout0=0,output reg clkout57=0,output lock);
 always #3.3670035 clkout0=~clkout0;always #8.754037 clkout57=~clkout57;assign lock=1;endmodule
module config_pll_27m_10m(input clkin1,output reg clkout0=0,output lock);
 always #50 clkout0=~clkout0;assign lock=1;endmodule
module hdmi_config #(parameter TX_FIRST=1)(input cfg_clk,reset_n,output rx_done,tx_done,scl,inout sda,output ack_error,config_error,startup_retry_seen);
 assign rx_done=reset_n;assign tx_done=reset_n;assign scl=1;assign ack_error=0;assign config_error=0;assign startup_retry_seen=0;endmodule
