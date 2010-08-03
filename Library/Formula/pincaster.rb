require 'formula'

class Pincaster <Formula
  url 'http://download.pureftpd.org/pincaster/releases/pincaster-0.5.tar.gz'
  homepage 'http://github.com/jedisct1/Pincaster'
  md5 'd2cba33470c1d23d381a2003b3986efe'

  def install
    system "./configure", "--prefix=#{prefix}"
    system "make install"

    inreplace "pincaster.conf" do |s|
      s.gsub! "/var/db/pincaster/pincaster.db", "#{var}/db/pincaster/pincaster.db"
      s.gsub! "# LogFileName       /tmp/pincaster.log", "LogFileName  /var/log/pincaster.log"
    end

    etc.install "pincaster.conf"
    (var+"db/pincaster/").mkpath

    launchd_plist "com.github.pincaster" do
      run_at_load true; keep_alive true
      program_arguments ["#{bin}/pincaster","#{etc}/pincaster.conf"]
      user_name `whoami`.chomp
      working_directory "#{var}"
      standard_error_path "/var/log/pincaster.log"
      standard_out_path   "/var/log/pincaster.log"
    end
  end

  def caveats
    <<-EOS.undent
      Automatically load on login with:
        launchctl load -w #{prefix}/com.github.pincaster.plist

      To start pincaster manually:
        pincaster #{etc}/pincaster.conf
    EOS
  end
end
