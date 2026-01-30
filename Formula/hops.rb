class Hops < Formula
  desc "Lightweight sandboxing for untrusted code on macOS using Apple Containerization"
  homepage "https://github.com/plyght/hops"
  head "https://github.com/plyght/hops.git", branch: "main"

  depends_on xcode: ["15.0", :build]
  depends_on :macos => :sequoia
  depends_on arch: :arm64

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox"

    bin.install ".build/release/hops"
    bin.install ".build/release/hopsd"
    bin.install ".build/release/hops-create-rootfs"

    entitlements_file = "#{buildpath}/hopsd.entitlements"
    system "codesign", "-s", "-", "--entitlements", entitlements_file, "--force", "#{bin}/hopsd"
  end

  def post_install
    system "#{bin}/hops", "init"
  end

  def caveats
    <<~EOS
      Hops has been installed. To get started:

      1. Run your first sandboxed command:
         hops run /tmp -- /bin/echo "Hello from Hops!"

      The daemon starts automatically when needed. No manual setup required.

      For more information:
         hops doctor                  # Diagnose system setup
         hops profile list            # List available profiles
         hops system start            # Manually manage daemon (optional)
         hops --help                  # Show all commands

      Runtime files are stored in ~/.hops/
      Configuration files are in ~/.hops/profiles/

      Note: hopsd requires virtualization entitlements and is code-signed during installation.
    EOS
  end

  test do
    assert_match "hops", shell_output("#{bin}/hops --version")
    assert_predicate bin/"hopsd", :exist?
    assert_predicate bin/"hops-create-rootfs", :exist?
  end
end
