# Algorithm-only synthesis example. Do not add a second clock constraint
# on the same clock in A/C's complete project. Replace with actual PLL clocks.
create_clock -name b_processing_clk -period 20.000 [get_ports {clk}]
# No blanket false-path/clock-group exceptions are supplied.
# Input/output delays and CDC constraints belong to the actual system boundary.
