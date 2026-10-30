"""Offline UART wire-level protocol regression; never opens a COM port."""
from pathlib import Path
import datetime
import hashlib
import importlib.util
import json
import re
import shutil
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[1]
TOOLS=Path('C:/modeltech64_2020.4/win64')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
spec=importlib.util.spec_from_file_location('send_lens_angle',ROOT/'tools/send_lens_angle.py')
host=importlib.util.module_from_spec(spec);spec.loader.exec_module(host)


def main():
    out=ROOT/'verification'/('uart_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
    out.mkdir();print('UART_RUN '+str(out),flush=True)
    values=[16668374,0,146376934,0,16668374,100663296]
    va=[16777216,-12345,7654321,12345,16000000,-456789]
    vb=[16000000,76543,-234567,-76543,16000000,890123]
    packets={'a':host.encode_packet(0x1234,values),'b':host.encode_packet(0x5678,va),'c':host.encode_packet(0x9abc,vb)}
    assert all(len(p)==38 for p in packets.values())
    assert host.crc16(b'123456789')==0x29b1
    # Independent Python decoding validates all signed40 positions/endianness.
    for name,p in packets.items():
        expected={'a':values,'b':va,'c':vb}[name]
        assert [int.from_bytes(p[6+k*5:11+k*5],'little',signed=True) for k in range(6)]==expected
    for name,p in packets.items():
        (out/('packet_'+name+'.hex')).write_text(''.join('%02x\n'%x for x in p))
        seq=int.from_bytes(p[3:5],'little')
        (out/('ack_'+name+'.hex')).write_text(''.join('%02x\n'%x for x in host.encode_ack(seq)))
    malformed={}
    bad=bytearray(packets['a']);bad[10]^=0x40;malformed['crc']=bad
    for name,offset,value in [('version',2,2),('flags',5,1)]:
        p=bytearray(packets['a']);p[offset]=value;p[-2:]=host.crc16(p[2:-2]).to_bytes(2,'little');malformed[name]=p
    for name,p in malformed.items():(out/('bad_'+name+'.hex')).write_text(''.join('%02x\n'%x for x in p))
    tb=r'''`timescale 1ns/1ps
module tb_uart;
 localparam BIT=16;
 reg clk=0,rst_n=0,uart_rx=1,cfg_ready=0,commit_valid=0;
 reg[15:0]commit_sequence=0;wire uart_tx,cfg_valid;wire[15:0]cfg_sequence;wire[239:0]cfg_affine;
 always #5 clk=~clk;
 lens_uart_control #(.CLOCK_HZ(27000000),.BAUD(1687500)) dut(.*);
 reg[7:0]pa[0:37],pb[0:37],pc[0:37],bad_crc[0:37],bad_version[0:37],bad_flags[0:37];
 reg[7:0]aa[0:7],ab[0:7],ac[0:7],received[0:63];integer ack_bytes=0,handshakes=0;
 reg[7:0]rx_ack;reg[239:0]held;reg[15:0]held_seq;reg stalled=0;
 always @(posedge clk)begin
  if(!rst_n)stalled<=0;
  else begin
   if(stalled&&(!cfg_valid||cfg_affine!==held||cfg_sequence!==held_seq))$fatal(1,"CFG_UNSTABLE_UNDER_STALL");
   stalled<=cfg_valid&&!cfg_ready;held<=cfg_affine;held_seq<=cfg_sequence;
   if(cfg_valid&&cfg_ready)handshakes=handshakes+1;
  end
 end
 // Independent serial monitor, samples each bit at its middle.
 initial forever begin
  @(negedge uart_tx);repeat(BIT+BIT/2)@(posedge clk);#1;
  for(integer j=0;j<8;j=j+1)begin
   rx_ack[j]=uart_tx;repeat(BIT)@(posedge clk);#1;
  end
  if(!uart_tx)$fatal(1,"BAD_TX_STOP");
  received[ack_bytes]=rx_ack;ack_bytes=ack_bytes+1;
 end
 task byte_send(input[7:0]v,input bit bad_stop);
  begin
   @(negedge clk);uart_rx=0;repeat(BIT)@(negedge clk);
   for(integer j=0;j<8;j=j+1)begin uart_rx=v[j];repeat(BIT)@(negedge clk);end
   uart_rx=!bad_stop;repeat(BIT)@(negedge clk);uart_rx=1;
  end
 endtask
 task packet_send(input integer kind,input integer length);
  reg[7:0]v;
  begin
   for(integer k=0;k<length;k=k+1)begin
    case(kind)0:v=pa[k];1:v=pb[k];2:v=pc[k];3:v=bad_crc[k];4:v=bad_version[k];5:v=bad_flags[k];endcase
    byte_send(v,0);
   end
   repeat(8)@(negedge clk);
  end
 endtask
 task commit(input[15:0]seq);
  begin @(negedge clk);commit_valid=1;commit_sequence=seq;@(negedge clk);commit_valid=0;end
 endtask
 task expect_idle;
  begin repeat(BIT*45)@(negedge clk);if(cfg_valid||handshakes!=0||ack_bytes!=0)$fatal(1,"REJECT_LEAKED");end
 endtask
 task check_cfg(input integer kind,input[15:0]seq);
  reg[239:0]v;
  begin
   for(integer k=0;k<30;k=k+1)case(kind)0:v[k*8+:8]=pa[k+6];1:v[k*8+:8]=pb[k+6];2:v[k*8+:8]=pc[k+6];endcase
   if(!cfg_valid||cfg_sequence!==seq||cfg_affine!==v)$fatal(1,"CFG_MISMATCH kind=%0d seq=%h",kind,cfg_sequence);
  end
 endtask
 task wait_ack(input integer total,input integer kind);
  integer t;reg[7:0]v;
  begin
   for(t=0;t<BIT*100&&ack_bytes<total;t=t+1)@(negedge clk);
   if(ack_bytes!=total)$fatal(1,"ACK_TIMEOUT bytes=%0d expected=%0d",ack_bytes,total);
   for(integer k=0;k<8;k=k+1)begin
    case(kind)0:v=aa[k];1:v=ab[k];2:v=ac[k];endcase
    if(received[total-8+k]!==v)$fatal(1,"ACK_GOLDEN_MISMATCH byte=%0d",k);
   end
   repeat(BIT*3)@(negedge clk);
  end
 endtask
 initial begin
  $readmemh("packet_a.hex",pa);$readmemh("packet_b.hex",pb);$readmemh("packet_c.hex",pc);
  $readmemh("ack_a.hex",aa);$readmemh("ack_b.hex",ab);$readmemh("ack_c.hex",ac);
  $readmemh("bad_crc.hex",bad_crc);$readmemh("bad_version.hex",bad_version);$readmemh("bad_flags.hex",bad_flags);
  repeat(5)@(negedge clk);rst_n=1;repeat(5)@(negedge clk);
  packet_send(3,38);expect_idle();packet_send(4,38);expect_idle();packet_send(5,38);expect_idle();
  packet_send(0,12);expect_idle();
  // Bad stop cannot manufacture a parameter request.
  byte_send(8'ha5,1);expect_idle();
  // Overlapping header prefix and two packets with no application consumption.
  byte_send(8'ha5,0);packet_send(0,38);check_cfg(0,16'h1234);
  packet_send(1,38);check_cfg(0,16'h1234);
  commit(16'h1234);repeat(BIT*12)@(negedge clk);
  if(ack_bytes!=0)$fatal(1,"ACK_BEFORE_CONSUMPTION");
  @(negedge clk);cfg_ready=1;@(negedge clk);cfg_ready=0;
  if(handshakes!=1||cfg_valid)$fatal(1,"CFG_NOT_CONSUMED_ONCE");
  commit(16'h4321);repeat(BIT*12)@(negedge clk);
  if(ack_bytes!=0)$fatal(1,"ACK_FOR_WRONG_SEQUENCE");
  packet_send(2,38);if(cfg_valid)$fatal(1,"ACCEPTED_WHILE_WAITING_FOR_COMMIT");
  commit(16'h1234);wait_ack(8,0);
  // New packet after previous ACK; same-edge ready+commit is permitted.
  packet_send(2,38);check_cfg(2,16'h9abc);
  @(negedge clk);cfg_ready=1;commit_valid=1;commit_sequence=16'h9abc;
  @(negedge clk);cfg_ready=0;commit_valid=0;
  wait_ack(16,2);if(handshakes!=2)$fatal(1,"HANDSHAKE_COUNT");
  // Reset cancels a truncated packet and a pending application transaction.
  packet_send(1,16);rst_n=0;repeat(4)@(negedge clk);rst_n=1;expect_reset_idle;
  packet_send(1,38);check_cfg(1,16'h5678);rst_n=0;repeat(4)@(negedge clk);rst_n=1;expect_reset_idle;
  commit(16'h5678);repeat(BIT*12)@(negedge clk);if(ack_bytes!=16)$fatal(1,"RESET_OLD_COMMIT_ACK");
  packet_send(1,38);check_cfg(1,16'h5678);
  @(negedge clk);cfg_ready=1;@(negedge clk);cfg_ready=0;commit(16'h5678);wait_ack(24,1);
  if(handshakes!=3)$fatal(1,"FINAL_HANDSHAKE_COUNT");
  $display("UART_CONTROL_PASS crc_bad=1 invalid_version=1 invalid_flags=1 truncated=1 back_to_back_busy=1 held_cfg=1 no_early_ack=1 stale_commit=1 commit_ack=3 reset_cancel=2 wire_golden_bytes=24");$finish;
 end
 task expect_reset_idle;
  begin repeat(BIT*45)@(negedge clk);if(cfg_valid||ack_bytes!=16)$fatal(1,"RESET_PACKET_LEAK");end
 endtask
 initial begin #5000000;$fatal(1,"UART_TEST_TIMEOUT");end
endmodule
'''
    (out/'tb_uart.sv').write_text(tb)
    rtl=ROOT/'rtl/lens_uart_control.v';shutil.copyfile(rtl,out/rtl.name)
    shutil.copyfile(Path(__file__),out/'checker_snapshot.py')
    ini=out/'modelsim.ini';shutil.copyfile(TOOLS.parent/'modelsim.ini',ini)
    inputs={'rtl_sha256':sha(rtl),'host_tool_sha256':sha(ROOT/'tools/send_lens_angle.py'),
            'checker_sha256':sha(Path(__file__)),'testbench_sha256':sha(out/'tb_uart.sv'),
            'fixtures':{p.name:sha(p) for p in out.glob('*.hex')},
            'hardware_accessed':False,'serial_ports_opened':False}
    (out/'inputs.json').write_text(json.dumps(inputs,indent=2))
    def run(argv,name):
        with (out/name).open('w') as log:
            r=subprocess.run([p.as_posix() if isinstance(p,Path) else str(p) for p in argv],cwd=out,stdout=log,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
        if r.returncode:raise RuntimeError(str(out/name))
    run([TOOLS/'vlib.exe',out/'work'],'library.log');run([TOOLS/'vmap.exe','-modelsimini',ini,'work',out/'work'],'mapping.log')
    run([TOOLS/'vlog.exe','-sv','-modelsimini',ini,out/rtl.name,out/'tb_uart.sv'],'compile.log')
    (out/'run.do').write_text('onerror {quit -code 2 -f}\nonbreak {resume}\nonfinish stop\nrun -all\nquit -f\n')
    try:run([TOOLS/'vsim.exe','-modelsimini',ini,'-c','work.tb_uart','-do',out/'run.do'],'simulation.log')
    except RuntimeError:pass
    log=(out/'simulation.log').read_text(errors='replace')
    passed='UART_CONTROL_PASS' in log and not re.search(r'\*\* (?:Error|Fatal|Warning)(?:\s|:)',log)
    assert sha(rtl)==inputs['rtl_sha256']
    result={'passed':passed,'hardware_accessed':False,'serial_ports_opened':False,
            'inputs_sha256':sha(out/'inputs.json'),'simulation_log_sha256':sha(out/'simulation.log'),
            'observations':[x for x in log.splitlines() if 'UART_CONTROL_PASS' in x or '** Error' in x or '** Fatal' in x or '** Warning' in x]}
    (out/'verification.json').write_text(json.dumps(result,indent=2));print(json.dumps({'directory':str(out),**result},indent=2))
    sys.exit(0 if passed else 1)


if __name__=='__main__':main()
