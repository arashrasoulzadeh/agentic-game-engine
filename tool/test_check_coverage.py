import contextlib
import io
from pathlib import Path
import tempfile
import unittest

from check_coverage import check


class CoverageGateTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.package = Path(self.temp.name).resolve()
        (self.package / 'lib').mkdir()
        (self.package / 'lib/value.dart').write_text('int value() => 1;\n')
        self.report = self.package / 'lcov.info'

    def result(self, reports=None):
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            return check(self.package, reports or [self.report])

    def test_uncovered_line_fails(self):
        self.report.write_text('SF:lib/value.dart\nDA:1,0\nend_of_record\n')
        self.assertFalse(self.result())

    def test_missing_file_and_exclusion_fail_even_when_report_is_full(self):
        self.report.write_text('SF:lib/value.dart\nDA:1,1\nend_of_record\n')
        self.assertTrue(self.result())
        source = self.package / 'lib/missing.dart'
        source.write_text('int other() => 2;\n')
        self.assertFalse(self.result())
        source.unlink()
        (self.package / 'lib/value.dart').write_text('// coverage:ignore-file\nint value() => 1;')
        self.assertFalse(self.result())

    def test_reports_merge_relative_and_absolute_source_names(self):
        self.report.write_text('SF:lib/value.dart\nDA:1,0\nDA:2,1\nend_of_record\n')
        extra = self.package / 'extra.info'
        extra.write_text(f'SF:{self.package}/lib/value.dart\nDA:1,1\nDA:2,0\nend_of_record\n')
        self.assertTrue(self.result([self.report, extra]))

    def test_export_only_file_needs_no_executable_lines(self):
        self.report.write_text('SF:lib/value.dart\nDA:1,1\nend_of_record\n')
        (self.package / 'lib/api.dart').write_text("// public API\nexport 'value.dart';\n")
        self.assertTrue(self.result())


if __name__ == '__main__':
    unittest.main()
