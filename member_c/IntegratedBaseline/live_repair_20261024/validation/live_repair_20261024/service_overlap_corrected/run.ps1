$ErrorActionPreference='Stop'
& D:/softwares/modelsim/win64/vlib.exe work *> library.log
$files=(Get-ChildItem ./source_snapshot -File).FullName
& D:/softwares/modelsim/win64/vlog.exe -sv @files *> compile.log
if($LASTEXITCODE -ne 0){throw 'Compile failed'}
& D:/softwares/modelsim/win64/vsim.exe -c -do 'onfinish stop;run -all;quit -f' work.tb_raw_pipeline *> simulation.log
if(-not(Select-String simulation.log -Pattern 'PASS RAW_PIPELINE' -Quiet)){throw 'Simulation failed; inspect log'}
Get-Content simulation.log | Select-String 'PASS RAW_PIPELINE|PUBLICATION|Errors:'
