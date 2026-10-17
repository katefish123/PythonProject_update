param([string]$Suffix='local',[switch]$Map,[switch]$Composed,[switch]$ReferenceSchedule)
$ErrorActionPreference='Stop'
$out="D:/FPGA/output/lens_fast_20261017_$Suffix"
if(Test-Path -LiteralPath $out){throw 'Use fresh output suffix'}
New-Item -ItemType Directory -Path "$out/source_snapshot" | Out-Null
$baseline=Join-Path (Split-Path $PSScriptRoot) 'lens_model_next'
$files=@("$PSScriptRoot/q30_alu_fast.v","$baseline/q30_alu.v")
if($Map){
 $files+=@("$PSScriptRoot/generated/lens_map_fast.v","$PSScriptRoot/generated/lens_composed_map_fast.v",'D:/FPGA/output/c_stream_board_v4s_20261016/vendor/b/rtl/bilinear_interp.v',"$baseline/tb_lens_map.sv")
 $bench='tb_lens_map'
}else{$files+="$PSScriptRoot/tb_div_equivalence.sv";$bench='tb_div_equivalence'}
foreach($p in $files){Copy-Item -LiteralPath $p -Destination "$out/source_snapshot/$([IO.Path]::GetFileName($p))"}
if($ReferenceSchedule){
 if($Map){throw 'ReferenceSchedule is an ALU performance negative control only'}
 $alias='module q30_alu_fast(input wire clk,rst_n,start,input wire[1:0]op,input wire signed[63:0]a,b,output wire ready,done,error,output wire signed[63:0]value); q30_alu old_schedule(.*); endmodule'
 [IO.File]::WriteAllText("$out/source_snapshot/q30_alu_fast.v",$alias)
}
if($Map){
 New-Item -ItemType Directory -Path "$out/fixtures" | Out-Null
 foreach($n in @('vectors.hex','composed_vectors.hex','expected_pixels.hex','manifest.json')){Copy-Item -LiteralPath "D:/FPGA/output/lens_vectors_20261017/$n" -Destination "$out/fixtures/$n"}
 $bp="$out/source_snapshot/tb_lens_map.sv"
 $code=[IO.File]::ReadAllText($bp).Replace('D:/FPGA/output/lens_vectors_20261017',"$out/fixtures").Replace('lens_composed_map dut(','lens_composed_map_fast dut(').Replace('lens_map dut(','lens_map_fast dut(')
 [IO.File]::WriteAllText($bp,$code)
}
$hashes=@{};Get-ChildItem -LiteralPath "$out/source_snapshot" -File | ForEach-Object{$hashes[$_.Name]=(Get-FileHash -LiteralPath $_.FullName).Hash.ToLower()}
$hashes | ConvertTo-Json | Out-File -Encoding utf8 "$out/compiled_hashes.json"
Push-Location $out
try{
 & D:/softwares/modelsim/win64/vlib.exe work | Out-File library.log
 & D:/softwares/modelsim/win64/vlog.exe -sv @((Get-ChildItem -LiteralPath "$out/source_snapshot" -File).FullName) | Out-File compile.log
 if($LASTEXITCODE -ne 0){throw 'Compile failed'}
 $generic=@();if($Composed){$generic+='-gCOMPOSED=1'}
 & D:/softwares/modelsim/win64/vsim.exe -c @generic -do 'onfinish stop;run -all;quit -f' "work.$bench" | Out-File simulation.log
 if($LASTEXITCODE -ne 0 -or (Select-String compile.log,simulation.log -Pattern '\*\* (Fatal|Error|Warning):' -Quiet) -or -not(Select-String simulation.log -Pattern 'PASS ' -Quiet)){throw 'Regression failed'}
 Get-Content simulation.log | Select-String 'PASS |Errors:'
}finally{Pop-Location}
