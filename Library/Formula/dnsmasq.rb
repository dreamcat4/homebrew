require 'formula'

class Dnsmasq <Formula
  url 'http://www.thekelleys.org.uk/dnsmasq/dnsmasq-2.55.tar.gz'
  homepage 'http://www.thekelleys.org.uk/dnsmasq/doc.html'
  md5 'b093d7c6bc7f97ae6fd35d048529232a'

  def install
    ENV.deparallelize

    inreplace "src/config.h", "/etc/dnsmasq.conf", "#{etc}/dnsmasq.conf"
    system "make install PREFIX=#{prefix}"

    prefix.install "dnsmasq.conf.example"

    launchd_plist "uk.org.thekelleys.dnsmasq" do
      run_at_load true; keep_alive { network_state true }
      program_arguments ["/usr/local/sbin/dnsmasq","--keep-in-foreground"]
    end
  end

  def caveats; <<-EOS.undent
    To configure dnsmasq, copy the example configuration to #{etc}/dnsmasq.conf
    and edit to taste.

      cp #{prefix}/dnsmasq.conf.example #{etc}/dnsmasq.conf

    To load dnsmasq automatically on startup, install and load the provided launchd
    item as follows:

      sudo cp #{prefix}/uk.org.thekelleys.dnsmasq.plist /Library/LaunchDaemons
      sudo launchctl load -w /Library/LaunchDaemons/uk.org.thekelleys.dnsmasq.plist
    EOS
  end
end

