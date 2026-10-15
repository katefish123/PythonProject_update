# Isolated64word result bursts

New modules only: ddr_result_writer_burst64 and ddr_word_engine_result_burst. Existing production writer/engine/B and current implementation candidate remain untouched.

Writer retains stream writer ports and adds cmd_write_block and cmd_block_data[2047:0]. Defaults OUT_W768 OUT_H1080 BASE0/1=0x200000/0x400000 FIFO_ADDR_BITS4(min2). Frame pixelcount must divisible64. cmd_wdata is firstbeat; cmd_wstrb allones. Word0 occupies bits31:0 and word63 bits2047:2016; each RGB word has zero highbyte. Internal epoch32 advances only valid drained frame_start and accompanies immutable command/ACK packets.

Engine adds cmd_result_block and result_block_data[2047:0], separately retaining capture_burst_data and cmd_source_block/rsp_source_block. Route result flag/data only with result-client grant. Resultblock mustwrite, aligned64 and safeinsideoneRESULTregion; source+result flags mutuallyexclusive. Illegalcommands respondreason1 without AW/AR. One response follows all8checked nativeWREADY beats, including AW/Wsamecycle. WID/WLAST faultsreason2, AW/Wtimeouts4/5 hardstop until coordinatedhardreset. Normalread caches, explicit sourceblock and captureburst behavior remain.

Abort/error discards only partial<64sourcewords; queued/held/issued blocks drain with immutable payload/address/epoch. drained requires partial0 and all owned ACKsconsumed. Busyframe_start faults without forgettingownership. Abort clearsfault and blocksnewpixels untilvaliddrainedframe_start. Bothdomainsreset withnativeenginehardreset; softabort neverflushesFIFOs. UIreservesACKFIFOcredit and oneblockinflight; successorcanprefetch. Sourceaccepts1pixel/clock whileFIFOspace.

Fresh all-in-one run D:/FPGA/output/c_result_burst_unit_20261015_final: ninebenches compile/simulate Errors0 Warnings0; pre/post sourcehashes match. run_tests.ps1 -Suffix final reproduces. Evidencecopies bounded logs/manifests; no WLF/worklibraries/sourceRAMdumps.

- RED baseline64pixels measured8UIcommands vsrequired1; REDengine forcedresult AWLEN0 vsrequired7. Expectedfailurelogs retained.
- Randomsource/UIclocks, commandstalls/ACKdelays, fullACKFIFO with stoppedsourceclock, bankpinchanges, malformedorder/end, badresponse, partial/owned/inflightabortlateACK, busystart andreset/restart pass.
- Nativeprotocol covers distinct result/capturepayloads,8beatdata, stableWdataunderstall, AW/Wsamecycle, early/missingWLAST, wrongWID, W/AWtimeouts andillegalread/unaligned/unsafe-tail/nonresult/mutualflags.
- Legacy singlebeat/resultcache/sourceprefetch/capture8beat/sourceblock regressions pass.
- Native54MHzsource/125MHzUI transports three829440wordframes from independent nontrivial bilinear goldenvariants0/1/2, banks0/1/0. EveryRGB/padding/strobe/address andresultRAMword checks. Eachframe12960commands/103680nativeWbeats/12960responses, zero sourcestalls; elapsed15.359792/15.359793/15.359811ms. Nativeabort209sourcepixels=>3ownedblocks+17partial discards only17 and drains192nativewords, thennextbank/epoch and commonreset/restart pass.

This reduces resultcommandcount103680->12960 (87.5% fewer arbitrationevents), with unchanged103680payloadWbeats. Nativebench feeds independentlycomputed correctedgoldens into resulttransport; it does not rerun correctionprocessor. Evidence excludes capture/displaycontention, DDRrefresh/physicaltiming, static timingclosure andboardmeasurement. It establishes transportcapacity, not60distinctcameraFPS. Integrate onlyNEWcandidate, then qualify fullcorrection/capture/display/nativeDDRcontention andimplementation.
