require 'formula'

class Lighttpd <Formula
  url 'http://download.lighttpd.net/lighttpd/releases-1.4.x/lighttpd-1.4.28.tar.bz2'
  md5 '586eb535d31ac299652495b058dd87c4'
  homepage 'http://www.lighttpd.net/'

  depends_on 'pkg-config'
  depends_on 'pcre'

  def install
    system "./configure", "--disable-dependency-tracking",
                          "--prefix=#{prefix}",
                          "--with-openssl", "--with-ldap"
    system "make install"

    launchd_plist do
      run_at_load true; keep_alive { network_state true }
      program_arguments ["#{bin}/lighttpd", "-D", "-f", "#{etc}/lighttpd.conf"]
      standard_error_path "/var/log/lighttpd.log"
      user_name "www"
    end
  end
end
