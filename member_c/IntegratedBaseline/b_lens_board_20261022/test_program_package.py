"""No hardware: verify the programming preflight's server-launch decisions."""
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest import TestCase, main
from unittest.mock import MagicMock, patch
import program_package as package

class ServerPreflight(TestCase):
    def test_existing_server_is_reused(self):
        with patch.object(package.socket,'create_connection',return_value=MagicMock()), patch.object(package.subprocess,'Popen') as launch:
            package.ensure_jtag_server(Path('unused/cdt_cfg_shell.exe'),Path('unused'))
            launch.assert_not_called()

    def test_matching_server_is_launched_hidden(self):
        with TemporaryDirectory(prefix='fpga_server_test_') as tmp:
            root=Path(tmp);(root/'cdt_js.exe').touch()
            with patch.object(package.socket,'create_connection',side_effect=[OSError('offline'),MagicMock()]), patch.object(package.subprocess,'Popen') as launch:
                package.ensure_jtag_server(root/'cdt_cfg_shell.exe',root)
                args,kwargs=launch.call_args
                self.assertEqual(args[0],[str(root/'cdt_js.exe'),'-port','65420'])
                self.assertEqual(kwargs['cwd'],root)
                self.assertEqual(kwargs['creationflags'],getattr(package.subprocess,'CREATE_NO_WINDOW',0))

    def test_server_failure_stops_before_programming(self):
        with TemporaryDirectory(prefix='fpga_server_test_') as tmp:
            root=Path(tmp);(root/'cdt_js.exe').touch();child=MagicMock();child.poll.return_value=1
            with patch.object(package.socket,'create_connection',side_effect=OSError('offline')), patch.object(package.subprocess,'Popen',return_value=child), patch.object(package.time,'sleep') as sleep:
                with self.assertRaisesRegex(RuntimeError,'JTAG server stopped'):
                    package.ensure_jtag_server(root/'cdt_cfg_shell.exe',root)
                sleep.assert_not_called()

if __name__=='__main__':main()
