#57.115MHz processing clock candidate

The existing GPLL VCO remains742.5MHz; input divider1, multiplier2, feedback fraction13.75 and pixel divider5 are unchanged. Previously unused integer output1 changes from divider40 to13 (duty13), giving742.5/13=57.115384615MHz. Pixel output0 remains148.5MHz. This changes only processing clock routing, not B arithmetic or image dimensions.

The production PLL file is tested directly with the Pango GTP_GPLL model. After lock,4096 measured periods give processing57.115385184MHz and pixel148.500001483MHz, with zero compile/simulation warnings/errors. The separate generated candidate routes processing from CLKOUT1, declares17.508418ns in FDC, updates the source/controller/overlay millisecond prescalers to57115 and preserves timeout wall times. Prescaler rounding error is about6.7ppm.

`prepare_candidate.py` applies these changes to a fresh verified turnaround snapshot. The57MHz whole-system bench uses the same source fixtures and integer goldens, with matching processing period and millisecond prescaler. Native DDR/HDMI60 distinct-image testing and physical timing are separate requirements. No board programming or acceptance follows from PLL simulation.
