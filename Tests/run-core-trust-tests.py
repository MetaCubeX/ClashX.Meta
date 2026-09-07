#!/usr/bin/python3
"""Exercise the real bundled-core manifest generator with temporary fixtures."""

import gzip
import hashlib
import io
import os
from pathlib import Path
import subprocess
import sys
import tempfile


class CoreTrustTests:
    def __init__(self, directory):
        self.directory = directory
        self.script = Path(__file__).resolve().parents[1] / "scripts/generate-core-trust.sh"
        self.checks = 0
        self.invocations = 0

    def require(self, condition, description):
        self.checks += 1
        if not condition:
            raise AssertionError(description)

    def invoke(self, archive, output, succeeds):
        self.invocations += 1
        result = subprocess.run(
            ["/bin/bash", str(self.script), str(archive), str(output)],
            cwd=self.directory,
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )
        self.require(
            (result.returncode == 0) == succeeds,
            "Unexpected generator exit {} for {!r}: {}".format(
                result.returncode, str(output), result.stderr.strip()
            ),
        )
        self.no_temporary_manifest(Path(output))

    def no_temporary_manifest(self, output):
        leftovers = []
        if output.parent.is_dir():
            leftovers = [entry.name for entry in output.parent.iterdir()
                         if entry.name.startswith(output.name + ".")]
        self.require(not leftovers, "Temporary manifest left behind: {!r}".format(leftovers))

    @staticmethod
    def manifest(data):
        digest = hashlib.sha256(data).hexdigest()
        return ('enum BundledCoreTrust {\n    static let sha256 = "' + digest + '"\n}\n').encode()

    @staticmethod
    def snapshot(path):
        info = path.stat()
        return path.read_bytes(), info.st_mtime_ns, info.st_ino

    def run(self):
        # Deliberately non-executable bytes: the generator only decompresses and hashes them.
        data = b"abc"
        self.require(hashlib.sha256(data).hexdigest() ==
                     "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
                     "Known SHA256 fixture is incorrect")
        archive = self.directory / "core.gz"
        compressed = gzip.compress(data, mtime=0)
        archive.write_bytes(compressed)
        output = self.directory / "new parent" / "BundledCoreTrust.swift"
        self.invoke(archive, output, succeeds=True)
        self.require(output.read_bytes() == self.manifest(data), "Manifest must hash decompressed executable bytes")

        # Give the file a distinctive timestamp; no sleeps or clock resolution assumptions are needed.
        os.utime(output, ns=(1_600_000_000_123_456_789, 1_600_000_000_123_456_789))
        original = self.snapshot(output)
        self.invoke(archive, output, succeeds=True)
        self.require(self.snapshot(output) == original, "An identical manifest must preserve bytes, mtime and inode")

        container = io.BytesIO()
        with gzip.GzipFile(filename="different gzip header", fileobj=container, mode="wb", mtime=123) as stream:
            stream.write(data)
        self.require(container.getvalue() != compressed, "Container fixture must differ from the original gzip")
        archive.write_bytes(container.getvalue())
        self.invoke(archive, output, succeeds=True)
        self.require(self.snapshot(output) == original, "Gzip metadata changes must not rewrite an unchanged executable digest")

        changed = b"different core build fixture\n"
        archive.write_bytes(gzip.compress(changed, mtime=0))
        self.invoke(archive, output, succeeds=True)
        self.require(output.read_bytes() == self.manifest(changed), "Changed executable bytes must update the manifest")
        preserved = self.snapshot(output)

        corrupt_crc = bytearray(compressed)
        corrupt_crc[-8] ^= 1
        corrupt_length = bytearray(compressed)
        corrupt_length[-4] ^= 1
        invalid_archives = {
            "zero-bytes.gz": b"",
            "not-gzip.gz": b"This is not a gzip archive.\n",
            "truncated-header.gz": compressed[:8],
            "truncated-body.gz": compressed[:12],
            "truncated-footer.gz": compressed[:-4],
            "bad-crc.gz": bytes(corrupt_crc),
            "bad-length.gz": bytes(corrupt_length),
        }
        missing = self.directory / "missing.gz"
        directory_archive = self.directory / "archive-directory"
        directory_archive.mkdir()
        failed_sources = [missing, directory_archive]
        for name, contents in invalid_archives.items():
            fixture = self.directory / name
            fixture.write_bytes(contents)
            failed_sources.append(fixture)
        for fixture in failed_sources:
            self.invoke(fixture, output, succeeds=False)
            self.require(self.snapshot(output) == preserved,
                         "Invalid archive changed the previous manifest: " + fixture.name)
        absent_output = self.directory / "should-not-exist.swift"
        self.invoke(missing, absent_output, succeeds=False)
        self.require(not absent_output.exists(), "Missing input must not create a manifest")

        special_parent = self.directory / "space ' $HOME $(touch dollar-marker) `touch backtick-marker`"
        special_parent.mkdir()
        special_archive = special_parent / "core's $USER $(touch input-marker) `touch input-backtick`.gz"
        special_output = special_parent / "manifest ' $PATH $(touch output-marker) `touch output-backtick`.swift"
        special_archive.write_bytes(compressed)
        self.invoke(special_archive, special_output, succeeds=True)
        self.require(special_output.read_bytes() == self.manifest(data), "Special paths must preserve the intended input and output")
        special_snapshot = self.snapshot(special_output)
        self.invoke(special_archive, special_output, succeeds=True)
        self.require(self.snapshot(special_output) == special_snapshot, "Special-path output must also be idempotent")
        markers = ["dollar-marker", "backtick-marker", "input-marker", "input-backtick",
                   "output-marker", "output-backtick"]
        self.require(not any((self.directory / marker).exists() for marker in markers),
                     "A path unexpectedly executed shell content")

        directory_output = self.directory / "directory-output"
        directory_output.mkdir()
        self.invoke(archive, directory_output, succeeds=False)
        self.require(list(directory_output.iterdir()) == [], "Directory output must not receive a randomly named manifest")
        self.invoke(archive, str(directory_output) + "/", succeeds=False)
        self.require(list(directory_output.iterdir()) == [], "A trailing slash must not move a manifest into a directory")

        file_link = self.directory / "file-link.swift"
        directory_link = self.directory / "directory-link.swift"
        broken_link = self.directory / "broken-link.swift"
        file_link.symlink_to(output)
        directory_link.symlink_to(directory_output)
        broken_link.symlink_to(self.directory / "missing-link-target")
        for link in [file_link, directory_link, broken_link]:
            target = os.readlink(link)
            self.invoke(archive, link, succeeds=False)
            self.require(link.is_symlink() and os.readlink(link) == target,
                         "Rejected output symlink was replaced")
        self.require(self.snapshot(output) == preserved, "Rejected output symlink changed its target")
        self.require(list(directory_output.iterdir()) == [], "Rejected directory symlink received a manifest")
        self.require(not (self.directory / "missing-link-target").exists(), "Rejected broken symlink created its target")

        fifo = self.directory / "output.fifo"
        os.mkfifo(fifo)
        fifo_info = fifo.lstat()
        self.invoke(archive, fifo, succeeds=False)
        self.require(fifo.lstat().st_ino == fifo_info.st_ino, "Rejected FIFO was replaced")
        blocked_parent = self.directory / "parent-is-file"
        blocked_parent.write_bytes(b"preserve this parent")
        self.invoke(archive, blocked_parent / "manifest.swift", succeeds=False)
        self.require(blocked_parent.read_bytes() == b"preserve this parent", "Failed output creation damaged its parent")
        self.require(self.snapshot(output) == preserved, "Failure scenarios must preserve the existing trusted manifest")


def main():
    with tempfile.TemporaryDirectory(prefix="clashx-core-trust-tests.", dir="/private/tmp") as directory:
        suite = CoreTrustTests(Path(directory))
        suite.run()
    suite.require(not Path(directory).exists(), "Temporary fixtures were not cleaned up")
    print("PASS: {} core trust checks across {} generator invocations; no executable invocation".format(
        suite.checks, suite.invocations))


if __name__ == "__main__":
    try:
        main()
    except (AssertionError, OSError, subprocess.SubprocessError) as error:
        print("FAIL: " + str(error), file=sys.stderr)
        sys.exit(1)
