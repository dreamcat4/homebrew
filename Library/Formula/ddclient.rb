require 'formula'

class Ddclient <Formula
  url 'http://downloads.sourceforge.net/project/ddclient/ddclient/ddclient-3.8.0/ddclient-3.8.0.tar.bz2'
  homepage 'http://sourceforge.net/apps/trac/ddclient'
  md5 '6cac7a5eb1da781bfd4d98cef0b21f8e'

  skip_clean 'etc'
  skip_clean 'var'

  def install
    # Adjust default paths in script
    inreplace 'ddclient' do |s|
      s.gsub! "/etc/ddclient", (etc + 'ddclient')
      s.gsub! "/var/cache/ddclient", (var + 'run/ddclient')
    end

    # Copy script to sbin
    sbin.install "ddclient"

    # Install sample files
    inreplace 'sample-ddclient-wrapper.sh' do |s|
      s.gsub! "/etc/ddclient", (etc + 'ddclient')
    end
    inreplace 'sample-etc_cron.d_ddclient' do |s|
      s.gsub! "/usr/sbin/ddclient", (sbin + 'ddclient')
    end
    inreplace 'sample-etc_ddclient.conf' do |s|
      s.gsub! "/var/run/ddclient.pid", (var + 'run/ddclient/pid')
    end
    (share + 'doc/ddclient').install ['sample-ddclient-wrapper.sh',\
                                          'sample-etc_cron.d_ddclient',\
                                          'sample-etc_ddclient.conf']

    # Create etc & var paths
    (etc + 'ddclient').mkpath
    (var + 'run/ddclient').mkpath

    # Write the launchd script
    launchd_plist "org.ddclient" do
      run_at_load true; on_demand true
      program_arguments ["#{sbin}/ddclient","-file","#{etc}/ddclient/ddclient.conf"]
      start_calendar_interval do
        minute 0
      end
      watch_paths ["#{etc}/ddclient"]
      working_directory "#{etc}/ddclient"
    end
  end

  def caveats; <<-EOS
For ddclient to work, you will need to do the following:

1) Create configuration file in #{etc}/ddclient, sample
   configuration can be found in #{share}/doc/ddclient

2) Install the launchd item in /Library/LaunchDaemons, like so:

   sudo cp -vf #{prefix}/org.ddclient.plist /Library/LaunchDaemons/.
   sudo chown -v root:wheel /Library/LaunchDaemons/org.ddclient.plist

3) Start the daemon using:

   sudo launchctl load /Library/LaunchDaemons/org.ddclient.plist

Next boot of system will automatically start ddclient.
EOS
  end
end
