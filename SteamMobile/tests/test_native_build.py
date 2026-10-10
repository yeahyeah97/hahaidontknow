#!/usr/bin/env python3
"""Clean-server build plan tests; no claim of iOS compiler validation."""
import importlib.util
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("native", Path(__file__).resolve().parents[1] / "tools/prepare_native_build.py")
native = importlib.util.module_from_spec(spec)
spec.loader.exec_module(native)

SCRIPT = '''#!/bin/bash
# Copy the base library if we don't have one yet
exit 1
CC_FLAGS=()
PATCHED_FILES=(
    "main_ios:main_ios.c:main.o"
    "extra:extra.c:extra.o"
)
case "${1:-all}" in
    all)
        echo "=== Building all patched wineserver files ==="
        ;;
esac
# Map of patched .o files
old_archive_code
echo "=== Renaming colliding symbols in every .o (objcopy sweep) ==="
'''


class CleanServerBuild(unittest.TestCase):
    def test_every_source_is_built_once_with_overrides(self):
        result, objects = native.patch_server(SCRIPT, "SOURCES = \\\n+ main.c \\\n+ atom.c \\\n+ security.h\n\nUNIX_LIBS = ignored")
        self.assertEqual(objects, ["atom", "main_ios", "extra", "wineserver_ios_kill"])
        self.assertIn('for name in atom; do', result)
        self.assertNotIn('old_archive_code', result)
        self.assertNotIn('Copy the base library', result)
        self.assertIn('Clean build requires all', result)
        self.assertIn('Renaming colliding symbols', result)
        self.assertNotIn('"$OBJ_DIR/main.o"', result)
        self.assertNotIn('"$OBJ_DIR"/*.o', result)

    def test_duplicate_sources_rejected(self):
        with self.assertRaises(ValueError):
            native.server_sources('SOURCES = main.c main.c\n\n')

    def test_changed_upstream_fails_closed(self):
        with self.assertRaises(ValueError):
            native.patch_server(SCRIPT.replace('PATCHED_FILES=(', 'CHANGED=('), 'SOURCES = main.c\n\n')


if __name__ == '__main__':
    unittest.main()
