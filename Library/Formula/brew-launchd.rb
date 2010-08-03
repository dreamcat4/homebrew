require 'formula'

class BrewLaunchd < Formula
  url 'git://github.com/dreamcat4/brew-launchd.git', :tag => 'stable'
  homepage 'http://dreamcat4.github.com/brew-launchd'
  
  def install
    prefix.install Dir['*']
    bin.install    Dir["bin/*"]
    man1.install   gzip("#{prefix}/man1/brew-launchd.1")
  end

    def caveats; <<-EOS.undent
      Run `sudo brew launchd default --boot` to target launchr for Boot services.
      `brew launchd --help` or `man brew-launchd` for more information.
      
      Note: Boot time services may fail to start if brew is on a mounted volume
            for example - Apple Filevault. If in doubt move brew to /usr/local.

      EOS
    end
end
