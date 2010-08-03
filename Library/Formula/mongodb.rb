require 'formula'
require 'hardware'

class Mongodb <Formula
  homepage 'http://www.mongodb.org/'

  if Hardware.is_64_bit? and not ARGV.include? '--32bit'
    url 'http://fastdl.mongodb.org/osx/mongodb-osx-x86_64-1.6.2.tgz'
    md5 '6d1d81a81f69e07f5cc6f54a00796a37'
    version '1.6.2-x86_64'
  else
    url 'http://fastdl.mongodb.org/osx/mongodb-osx-i386-1.6.2.tgz'
    md5 'f1c0e58ef50333de0d43161345ac83a8'
    version '1.6.2-i386'
  end

  skip_clean :all

  def options
    [['--32bit', 'Install the 32-bit version.']]
  end

  def install
    # Copy the prebuilt binaries to prefix
    prefix.install Dir['*']

    # Create the data and log directories under /var
    (var+'mongodb').mkpath
    (var+'log/mongodb').mkpath

    # Write the configuration files and launchd script
    (prefix+'mongod.conf').write mongodb_conf

    launchd_plist "org.mongodb.mongod" do
      run_at_load true; keep_alive true
      program_arguments ["#{bin}/mongod","run","--config","#{prefix}/mongod.conf"]
      user_name `whoami`.chomp
      working_directory "#{HOMEBREW_PREFIX}"
      standard_error_path "#{var}/log/mongodb/output.log"
      standard_out_path   "#{var}/log/mongodb/output.log"
    end
  end

  def caveats; <<-EOS
If this is your first install, automatically load on login with:
    cp #{prefix}/org.mongodb.mongod.plist ~/Library/LaunchAgents
    launchctl load -w ~/Library/LaunchAgents/org.mongodb.mongod.plist

If this is an upgrade and you already have the org.mongodb.mongod.plist loaded:
    launchctl unload -w ~/Library/LaunchAgents/org.mongodb.mongod.plist
    cp #{prefix}/org.mongodb.mongod.plist ~/Library/LaunchAgents
    launchctl load -w ~/Library/LaunchAgents/org.mongodb.mongod.plist

Or start it manually:
    mongod run --config #{prefix}/mongod.conf
EOS
  end

  def mongodb_conf
    return <<-EOS
# Store data in #{var}/mongodb instead of the default /data/db
dbpath = #{var}/mongodb

# Only accept local connections
bind_ip = 127.0.0.1
EOS
  end
end
