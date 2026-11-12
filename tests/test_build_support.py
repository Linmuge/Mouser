import os
import re
import stat
import unittest

from build_support import normalized_qt_library_stem, should_keep_linux_qt_asset


class LinuxQtAssetFilterTests(unittest.TestCase):
    def test_normalizes_versioned_abi3_shared_library_names(self):
        cases = {
            "/tmp/_internal/PySide6/libpyside6.abi3.so.6.11": "pyside6",
            "/tmp/_internal/PySide6/libpyside6qml.abi3.so.6.11": "pyside6qml",
            "/tmp/_internal/PySide6/libshiboken6.abi3.so.6.11": "shiboken6",
        }

        for path, expected in cases.items():
            with self.subTest(path=path):
                self.assertEqual(normalized_qt_library_stem(path), expected)

    def test_keeps_versioned_pyside6_abi3_runtime_library(self):
        runtime_paths = [
            "/tmp/_internal/PySide6/libpyside6.abi3.so.6.11",
            "/tmp/_internal/PySide6/libpyside6qml.abi3.so.6.11",
            "/tmp/_internal/PySide6/libshiboken6.abi3.so.6.11",
        ]

        for path in runtime_paths:
            with self.subTest(path=path):
                self.assertTrue(should_keep_linux_qt_asset(path))

    def test_keeps_core_qt_dependency_libraries(self):
        dependency_paths = [
            "/tmp/_internal/PySide6/Qt/lib/libQt6DBus.so.6",
            "/tmp/_internal/PySide6/Qt/lib/libQt6XcbQpa.so.6",
            "/tmp/_internal/PySide6/Qt/lib/libicui18n.so.73",
            "/tmp/_internal/PySide6/Qt/lib/libicuuc.so.73",
            "/tmp/_internal/PySide6/Qt/lib/libicudata.so.73",
        ]

        for path in dependency_paths:
            with self.subTest(path=path):
                self.assertTrue(should_keep_linux_qt_asset(path))

    def test_drops_unneeded_qt_webengine_binary(self):
        path = "/tmp/_internal/PySide6/Qt/lib/libQt6WebEngineCore.so.6"
        self.assertFalse(should_keep_linux_qt_asset(path))

    def test_drops_optional_qml_style_family(self):
        path = "/tmp/_internal/PySide6/qml/QtQuick/Controls/Fusion/Button.qml"
        self.assertFalse(should_keep_linux_qt_asset(path))


class LinuxPermissionPackagingTests(unittest.TestCase):
    def test_linux_permission_helper_files_exist(self):
        root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        helper = os.path.join(
            root, "packaging", "linux", "install-linux-permissions.sh"
        )
        rules = os.path.join(
            root, "packaging", "linux", "69-mouser-logitech.rules"
        )

        self.assertTrue(os.path.isfile(helper))
        self.assertTrue(os.stat(helper).st_mode & stat.S_IXUSR)
        self.assertTrue(os.path.isfile(rules))

    def test_linux_permissions_do_not_grant_all_logitech_keyboard_nodes(self):
        root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        rules_path = os.path.join(
            root, "packaging", "linux", "69-mouser-logitech.rules"
        )
        with open(rules_path, encoding="utf-8") as rules_file:
            lines = rules_file.read().splitlines()

        hidraw_rules = [line for line in lines if 'KERNEL=="hidraw*"' in line]
        event_rules = [line for line in lines if 'KERNEL=="event*"' in line]
        self.assertTrue(hidraw_rules)
        self.assertTrue(event_rules)
        self.assertTrue(all("HID_ID" in line for line in hidraw_rules))
        self.assertFalse(any('KERNELS=="0005:046D:*"' in line for line in hidraw_rules))
        self.assertTrue(any("bInterfaceProtocol" in line for line in hidraw_rules))
        self.assertTrue(all('ID_INPUT_MOUSE}=="1"' in line for line in event_rules))
        self.assertTrue(all('ID_INPUT_KEYBOARD}!="1"' in line for line in event_rules))

    def test_linux_spec_packages_linux_files_into_linux_directory(self):
        root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        spec_path = os.path.join(root, "Mouser-linux.spec")
        with open(spec_path, encoding="utf-8") as spec_file:
            spec_text = spec_file.read()

        linux_assets = (
            "69-mouser-logitech.rules",
            "install-linux-permissions.sh",
            "io.github.tombadash.mouser.desktop.in",
        )
        for asset_name in linux_assets:
            with self.subTest(asset=asset_name):
                self.assertRegex(
                    spec_text,
                    re.compile(
                        rf'os\.path\.join\(ROOT, "packaging", "linux", '
                        rf'"{re.escape(asset_name)}"\),\s*"linux",',
                        re.MULTILINE,
                    ),
                )
                self.assertNotIn(
                    f'os.path.join("linux", "{asset_name}")',
                    spec_text,
                )


class ReleaseWorkflowSecurityTests(unittest.TestCase):
    def test_windows_release_signs_and_validates_full_content_catalog(self):
        root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        workflow_path = os.path.join(root, ".github", "workflows", "release.yml")
        with open(workflow_path, encoding="utf-8") as workflow_file:
            workflow = workflow_file.read()

        required_contract = (
            "New-FileCatalog",
            "-CatalogVersion 2.0",
            "Get-PfxCertificate",
            "Set-AuthenticodeSignature",
            'Join-Path $bundlePath "Mouser-Contents.cat"',
            "Test-FileCatalog",
            '-FilesToSkip "Mouser-Contents.cat"',
            "$catalogPublisher -ne $env:MOUSER_WINDOWS_PUBLISHER",
        )
        for expected in required_contract:
            with self.subTest(expected=expected):
                self.assertIn(expected, workflow)

    def test_release_installs_only_hash_locked_dependencies(self):
        root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        workflow_path = os.path.join(root, ".github", "workflows", "release.yml")
        with open(workflow_path, encoding="utf-8") as workflow_file:
            workflow = workflow_file.read()
        lock_path = os.path.join(root, "requirements-release.txt")
        build_lock_path = os.path.join(root, "requirements-release-build.txt")
        with open(lock_path, encoding="utf-8") as lock_file:
            lock = lock_file.read()
        with open(build_lock_path, encoding="utf-8") as build_lock_file:
            build_lock = build_lock_file.read()

        self.assertEqual(workflow.count("--require-hashes"), 6)
        self.assertEqual(workflow.count("--no-build-isolation"), 3)
        self.assertNotIn("-c requirements-release.txt", workflow)
        self.assertIn("--hash=sha256:", lock)
        self.assertIn("setuptools==83.0.0", build_lock)
        self.assertIn("--hash=sha256:", build_lock)


if __name__ == "__main__":
    unittest.main()
