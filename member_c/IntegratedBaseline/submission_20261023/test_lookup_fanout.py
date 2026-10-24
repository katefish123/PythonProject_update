"""A fanout experiment may change only four synthesis declarations."""
import unittest
from pathlib import Path

class LookupFanoutTests(unittest.TestCase):
    def test_exact_four_nets_and_no_logic_change(self):
        from prepare_lookup_fanout import transform, restore
        src=Path('D:/FPGA/output/b_lens_board_payload_20261023/sources/ddr_quad_tile_cache.v').read_text(encoding='utf-8')
        changed=transform(src)
        self.assertEqual(changed.count('(* syn_maxfan=32 *)'),4)
        self.assertEqual(restore(changed),src)

    def test_unexpected_parent_and_repeat_are_rejected(self):
        from prepare_lookup_fanout import transform
        src=Path('D:/FPGA/output/b_lens_board_payload_20261023/sources/ddr_quad_tile_cache.v').read_text(encoding='utf-8')
        for bad in [src.replace('lookup_y=lookup_l?l_y:s_y','lookup_y=s_y'),transform(src)]:
            with self.assertRaises(RuntimeError):transform(bad)

if __name__=='__main__':unittest.main()
