require 'formula'

class Redis <Formula
  url 'http://redis.googlecode.com/files/redis-2.0.1.tar.gz'
  head 'git://github.com/antirez/redis.git'
  homepage 'http://code.google.com/p/redis/'
  sha1 '364665c966c90eb5ab7d16065734a2b713d4b8eb'

  def install
    fails_with_llvm "Breaks with LLVM"

    # Head and stable have different code layouts
    src = File.exists?('src/Makefile') ? 'src' : '.'
    system "make -C #{src}"

    %w( redis-benchmark redis-cli redis-server redis-check-dump redis-check-aof ).each { |p|
      bin.install "#{src}/#{p}" rescue nil
    }

    %w( run db/redis log ).each { |p| (var+p).mkpath }

    # Fix up default conf file to match our paths
    inreplace "redis.conf" do |s|
      s.gsub! "/var/run/redis.pid", "#{var}/run/redis.pid"
      s.gsub! "dir ./", "dir #{var}/db/redis/"
    end

    doc.install Dir["doc/*"]
    etc.install "redis.conf"

    launchd_plist "io.redis.redis-server" do
      run_at_load true; keep_alive true
      program_arguments ["#{bin}/redis-server","#{etc}/redis.conf"]
      user_name `whoami`.chomp
      working_directory "#{var}"
      standard_error_path "/var/log/redis.log"
      standard_out_path   "/var/log/redis.log"
    end
  end

  def caveats
    <<-EOS.undent
      To start redis manually:
        redis-server #{etc}/redis.conf

      To access the server:
        redis-cli
    EOS
  end
end
