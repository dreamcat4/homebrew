require 'formula'

class Memcached <Formula
  url "http://memcached.googlecode.com/files/memcached-1.4.5.tar.gz"
  homepage 'http://www.danga.com/memcached/'
  sha1 'c7d6517764b82d23ae2de76b56c2494343c53f02'

  depends_on 'libevent'

  def install
    system "./configure", "--prefix=#{prefix}"
    system "make install"

    launchd_plist "com.danga.memcached" do
      run_at_load true; keep_alive true
      program_arguments ["#{HOMEBREW_PREFIX}/bin/memcached","-l","127.0.0.1"]
      working_directory "#{HOMEBREW_PREFIX}"
    end
  end

  def caveats; <<-EOS
You can enabled memcached to automatically load on login with:
    cp #{prefix}/com.danga.memcached.plist ~/Library/LaunchAgents/
    launchctl load -w ~/Library/LaunchAgents/com.danga.memcached.plist

Or start it manually:
    #{HOMEBREW_PREFIX}/bin/memcached

Add "-d" to start it as a daemon.
    EOS
  end
end
