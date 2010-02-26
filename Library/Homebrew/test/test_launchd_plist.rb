



def program_arguments array=nil
  array
    @program_arguments = array
  else
    @program_arguments
  end
end

def watch_paths array=nil
  array.class == Array ? @watch_paths = array : @watch_paths
end

def label string
end


@xml_keys = {
  'Label' => 'com.howbrew.haml', 
  'EnvironmentVariables' => {
    'PATH' => '/sbin:/usr/sbin:/bin:/usr/bin',
    'RUBY_LIB' => '/usr/lib/ruby/site_ruby/1.8'
  },

  'ProgramArguments' => [
		"bash", "-l", "-c", "/usr/bin/env", "ruby", "-e", "puts RUBY_VERSION"
		],

  'Sockets' => { 
		'netbios' => {
			'SockServiceName' => 'netbios-ssn',
			'SockFamily' => 'IPv4'
		},

		'direct' => {
		'SockServiceName' => 'netbios-ssn',
		'SockFamily' => 'IPv4',
		'Bonjour' => [
			'smb'
			],		
		}
	},

	'StartCalendarInterval' => {
		'Hour' => 3,
		'Minute' => 15,
		'Weekday' => 6,
	},

  'WatchPaths' => [
		"/Volumes/CD\ ROM",
		"/var/run"
		],

  'RunAtLoad' => true,
  'Debug' => true
}


@launchd << plist "myprogram" do
  env   "PATH" => '/sbin:/usr/sbin:/bin:/usr/bin',
    "RUBY_LIB" =>  '/usr/lib/ruby/site_ruby/1.8'    
  end
end

@launchd << plist "myprogram" do
  sockets do
    netbios do
      name "netbios-ssn"
    end
    direct do
      name "netbios"
      bonjour ['smb']
    end
  end

@launchd << plist "myprogram" do
  socket "netbios", :name => "netbios-ssn"

  socket "direct", :name => "netbios" do
    bonjour ['smb']
  end
end

@launchd << plist "myprogram" do
  start_calendar_interval do
    hour 3
    minute 15
    weekday 6
  end
end

@launchd << plist "com.github.homebrew.myprogram" do
  label               "com.github.homebrew.myprogram"
  program_arguments   [prefix+"bin/myprogram"]
  run_at_load         true
  working_directory   "/var/db/myprogram"
  standard_out_path   "/var/log/myprogram.log"
  # ...
end

@launchd << plist do
  label               "com.github.homebrew.myprogram"
  program_arguments   [prefix+"bin/myprogram"]
  run_at_load         true
  working_directory   "/var/db/myprogram"
  standard_out_path   "/var/log/myprogram.log"
  # ...
end

@launchd << plist "com.apache.couchdb"
@launchd << plist "com.sun.mysql.client", "com.sun.mysql.server"


# o = Haml::Engine.new("%p Haml code!").render
# engine = Haml::Engine.new("%p Haml code!")

# require 'rubygems'
# require 'haml'
# pwd = `pwd`.delete("\n")
# require "#{pwd}/test_plist.feature.rb"
# engine = Haml::Engine.new File.read("#{pwd}/launchd_plist.haml")
# print engine.render(self)



# <key>Sockets</key>
# <dict>
#   <key>netbios</key>
#   <dict>
#     <key>SockServiceName</key>
#     <string>netbios-ssn</string>
#     <key>SockFamily</key>
#     <string>IPv4</string>
#   </dict>
#   <key>direct</key>
#   <dict>
#     <key>SockServiceName</key>
#     <string>microsoft-ds</string>
#     <key>SockFamily</key>
#     <string>IPv4</string>
#     <key>Bonjour</key>
#     <array>
#       <string>smb</string>
#     </array>
#   </dict>
# </dict>
# 
# <key>StartCalendarInterval</key>
# <dict>
#   <key>Hour</key>
#   <integer>3</integer>
#   <key>Minute</key>
#   <integer>15</integer>
#   <key>Weekday</key>
#   <integer>6</integer>
# </dict>
# 
# <key>WatchPaths</key>
# <array>
#     <string>/Library/Preferences/SystemConfiguration/com.apple.smb.server.plist</string>
# </array>
# 
# <key>Sockets</key>
# <dict>
#   <key>Listeners</key>
#   <dict>
#     <key>SockServiceName</key>
#     <string>bootps</string>
#     <key>SockType</key>
#     <string>dgram</string>
#     <key>SockFamily</key>
#     <string>IPv4</string>
#   </dict>
# </dict>
# 
# <key>inetdCompatibility</key>
# <dict>
#   <key>Wait</key>
#   <true/>
# </dict>
# 
# <key>WatchPaths</key>
# <array>
#   <string><path to some dir></string>
# </array>
# 
# <key>Sockets</key>
# <dict>
#   <key>Listeners</key>
#   <dict>
#     <key>Bonjour</key>
#     <array>
#       <string>ssh</string>
#       <string>sftp-ssh</string>
#     </array>
#     <key>SockServiceName</key>
#     <string>ssh</string>
#   </dict>
# </dict>
# 
# <key>Sockets</key>
# <dict>
#   <key>Listeners</key>
#   <dict>
#     <key>SockPassive</key>
#     <true/>
#     <key>SockServiceName</key>
#     <string>ftp</string>
#     <key>SockType</key>
#     <string>SOCK_STREAM</string>
#   </dict>
# </dict>
# 
# <key>StartCalendarInterval</key>
# <dict>
#   <key>Hour</key>
#   <integer>3</integer>
#   <key>Minute</key>
#   <integer>15</integer>
#   <key>Weekday</key>
#   <integer>6</integer>
# </dict>


