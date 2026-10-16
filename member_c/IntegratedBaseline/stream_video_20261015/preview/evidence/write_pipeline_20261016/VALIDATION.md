# Preview local write pipeline

The old V4P path is rx_rgb_q[15] to preview/bank1_15/DA0[0], slack -0.924ns. It has zero combinational logic levels:0.185ns clock-to-Q and7.213ns routing, data-net fanout19. Exact old report path and source hashes are in summary.json and v4p_rx_worst.rtr.txt.

The preview keeps full24-bit RGB. Data, RAM address, target bank and sample-valid are registered together on the RX edge; only these local signals drive the RAM write. Every sampled pixel is written one edge later to the matching address and bank. A valid close sets publish_pending. Publication waits for write_valid to be empty, so the final write has retired before the complete bank is offered. Pending publication and occupied write stage block admission. Existing display ACK ownership, scan_start-only swap, decimation and row-base read timing are unchanged. Either reset clears shared preview identity and the write-valid stage.

The old preview fails the new publication-drain boundary check. The frozen candidate passes all three complete pixel cases (D1,2,8),3584 exact RGB24 checks each, final sample, cross-frame old-bank hold during new writes, display ACK backpressure, invalid-frame recovery, reset between sample/write, and shared/pixel-only reset. Existing display+preview raster regression also passes2496 pixel checks. Final runs have zero errors/warnings. No source capture, writer, engine, clocks, constraints or other module was changed.

No full60 or PDS was started. These local functional results do not establish native full-system throughput or physical timing closure. Root must generate and validate a snapshot bound to the frozen source SHA.
