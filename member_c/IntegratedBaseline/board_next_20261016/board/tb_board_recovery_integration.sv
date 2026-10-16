`timescale 1ns/1ps
module tb_board_recovery_integration;
 reg sys_clk=0,ref_clk=0,rx_clk=0,rst_n=0;
 always #18.5185 sys_clk=~sys_clk;always #4 ref_clk=~ref_clk;always #3.3670035 rx_clk=~rx_clk;
 reg camera_vs=0,camera_de=0,camera_hs=0;reg[23:0]camera_rgb=0;
 wire[7:0]led;wire[3:0]dqsp,dqsn;wire[31:0]dq;wire sda;
 video_correct_ddr_top #(.SOURCE_W(128),.SOURCE_H(48),.RESULT_W(64),.RESULT_H(48),
 .HS(4),.HB(8),.HF(512),.VS(2),.VB(4),.VF(4),.BIST_BEATS(8),.HDMI_HOLD(10),.RECOVERY_HOLD(12),.RECOVERY_TIMEOUT(100),.RECOVERY_SETTLE(12)) dut(
 .sys_clk_27m(sys_clk),.rst_n(rst_n),.key1_pattern_n(1'b1),.key2_nearest_n(1'b1),.ddr_ref_clk_p(ref_clk),.ddr_ref_clk_n(!ref_clk),
 .hd_rx_pclk(rx_clk),.hd_rx_vs(camera_vs),.hd_rx_hs(camera_hs),.hd_rx_de(camera_de),.hd_rx_data(camera_rgb),
 .hd_tx_pclk(),.hd_tx_vs(),.hd_tx_hs(),.hd_tx_de(),.hd_tx_data(),.hd_reset_n(),.hd_scl(),.hd_sda(sda),.led(led),
 .mem_cs_n(),.mem_rst_n(),.mem_ck(),.mem_ck_n(),.mem_cke(),.mem_ras_n(),.mem_cas_n(),.mem_we_n(),.mem_odt(),.mem_a(),.mem_ba(),.mem_dqs(dqsp),.mem_dqs_n(dqsn),.mem_dq(dq),.mem_dm());
 integer x=0,y=0,frames=0,resets=0;
 reg testing_observer=0,observer_reset_seen=0;
 reg[7:0]v;
 always @(negedge rx_clk)if(rst_n)begin
 camera_hs=x<4;camera_vs=y<2;camera_de=x>=12&&x<140&&y>=6&&y<54;
 v=80+(frames*11+x+y)%120;camera_rgb={v,v,v};
 if(x==651)begin x=0;if(y==57)begin y=0;frames++;end else y++;end else x++;
 end
 always @(negedge dut.memory_release_n)if(rst_n)begin resets++;if(testing_observer)observer_reset_seen=1;end
 task wait_video;
 begin wait(!dut.recovering);wait(dut.raw_count>=2);wait(dut.image_valid);repeat(15)@(posedge ref_clk);
 if(!dut.display_raw||dut.corr_count!=0||dut.source_faults!=0)$fatal(1,"RAW failed recovery/marker independence");end endtask
 task assert_all_owners_reset;
 begin wait(!dut.mem_reset);#1;
 if(dut.engine.state!=0||dut.core.continuous_sources.manager.state[0]!=0||dut.core.continuous_sources.manager.state[1]!=0||dut.core.continuous_sources.capture.used!=0||dut.core.modes.raw_lease_valid||dut.core.display_reader.ack_toggle!=0)
 $fatal(1,"partial reset left owner/lease/transaction behind");end endtask
 initial begin
 #100;rst_n=1;wait_video();
 // Corrupt only the read-only diagnostic mailbox output. This must not
 // control reset/protection. Real source protection has its own synchronizer.
 testing_observer=1;force dut.diagnostics.current_source_fault=4'h2;
 repeat(20)@(posedge dut.cfg_clk);release dut.diagnostics.current_source_fault;
 testing_observer=0;
 if(observer_reset_seen||dut.recovery_count!=0)$fatal(1,"DIAGNOSTIC_OBSERVER_TRIGGERED_RECOVERY");
 // Clear the deliberately corrupted observation before actual fault tests.
 rst_n=0;repeat(10)@(posedge ref_clk);rst_n=1;wait_video();
 // Inject the real source manager fault flag (not its diagnostic copy).
 // Release before the common reset so its ordinary asynchronous reset can
 // clear the flag. This validates the protection path, not a PHY root cause.
 force dut.core.continuous_sources.manager.fault=1'b1;
 wait(dut.epoch_fault);release dut.core.continuous_sources.manager.fault;
 wait(dut.current_kind==1);assert_all_owners_reset();wait_video();
 if(dut.recovery_count!=1||!dut.source_first_valid||dut.source_first_fault!=4'h4||dut.source_first_proc_tick==0||dut.source_first_received_ui_tick==0||dut.first_kind!=1||dut.current_mask!=0)$fatal(1,"independent source protection/history/recovery failed");
 rst_n=0;repeat(10)@(posedge ref_clk);rst_n=1;wait_video();resets=0;
 // Record pressure, then a real UI fault pulse while native ownership exists.
 wait(dut.memory_ip.reading||dut.memory_ip.writing);dut.memory_ip.inject_stall=1;repeat(20)@(posedge ref_clk);dut.memory_ip.inject_stall=0;
 wait(dut.memory_ip.reading||dut.memory_ip.writing);@(negedge ref_clk);dut.memory_ip.inject_align=1;
 @(negedge ref_clk);dut.memory_ip.inject_align=0;
 assert_all_owners_reset();wait_video();
 if(dut.recovery_count!=1||!dut.first_valid||dut.first_kind!=4||dut.first_mask[3]!=1||dut.current_mask!=0||dut.first_tick==0)$fatal(1,"ALIGN first/current/recovery history failed");
 if(dut.proc_first_service==0)$fatal(1,"service pressure history absent");
 // Second independent PHY event must not be relabeled by historical ALIGN.
 @(negedge ref_clk);dut.memory_ip.inject_phy=1;
 wait(dut.current_kind==3);if(dut.first_kind!=4)$fatal(1,"first history overwritten");
 @(negedge ref_clk);dut.memory_ip.inject_phy=0;assert_all_owners_reset();wait_video();
 if(dut.recovery_count!=2||dut.current_mask!=0)$fatal(1,"second coordinated recovery failed");
 // A controller watchdog fault is produced by withheld service, not forced
 // internal state. Application protection persists until full reset.
 wait(dut.memory_ip.reading||dut.memory_ip.writing);dut.memory_ip.inject_stall=1;
 wait(dut.engine_fault);wait(dut.current_kind==2);if(dut.first_kind!=4)$fatal(1,"engine fault used ALIGN history");
 assert_all_owners_reset();dut.memory_ip.inject_stall=0;wait_video();
 if(dut.recovery_count!=3)$fatal(1,"third retry missing");
 // A fourth fault exhausts the budget, holds the common memory reset and
 // returns no isolated credit. Manual reset is required to restart.
 @(negedge ref_clk);dut.memory_ip.inject_align=1;@(negedge ref_clk);dut.memory_ip.inject_align=0;
 wait(dut.retry_exhausted);repeat(100)@(posedge ref_clk);
 if(dut.memory_release_n||dut.recovery_count!=3||dut.mem_reset||resets!=4)$fatal(1,"retry limit/reset containment failed");
 rst_n=0;repeat(10)@(posedge ref_clk);rst_n=1;wait_video();
 if(dut.recovery_count!=0||dut.first_valid)$fatal(1,"manual reset did not clear history/budget");
 $display("PASS BOARD_RECOVERY_INTEGRATION observer isolation, real source fault flag/history/recovery, RAW before/after three coordinated resets; UI ALIGN pulse, PHY fault, real watchdog, immutable first history, all source/display/native owners reset, retry limit, manual restart");$finish;
 end
 initial begin #20000000;$fatal(1,"board integration timeout");end
endmodule
