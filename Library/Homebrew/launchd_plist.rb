#  Copyright 2009 Max Howell and other contributors.
#
#  Redistribution and use in source and binary forms, with or without
#  modification, are permitted provided that the following conditions
#  are met:
#
#  1. Redistributions of source code must retain the above copyright
#     notice, this list of conditions and the following disclaimer.
#  2. Redistributions in binary form must reproduce the above copyright
#     notice, this list of conditions and the following disclaimer in the
#     documentation and/or other materials provided with the distribution.
#
#  THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
#  IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
#  OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
#  IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
#  INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
#  NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
#  DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
#  THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
#  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
#  THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#

require 'global'
module BrewMixins
# This method was found in formula.rb, and it also requires global.rb
# perhaps we can get hold of this system() method a better way, dunno
def system cmd, *args
  ohai "#{cmd} #{args*' '}".strip

  if ARGV.verbose?
    safe_system cmd, *args
  else
    rd, wr = IO.pipe
    pid = fork do
      rd.close
      $stdout.reopen wr
      $stderr.reopen wr
      exec(cmd, *args) rescue nil
      exit! 1 # never gets here unless exec threw or failed
    end
    wr.close
    out = ''
    out << rd.read until rd.eof?
    Process.wait
    unless $?.success?
      puts out
      raise
    end
  end
rescue SystemCallError
  # usually because exec could not be find the command that was requested
  raise
rescue
  raise BuildError.new(cmd, args, $?)
end
end

class Object
  def method_name
    if  /`(.*)'/.match(caller.first)
      return $1
    end
    nil
  end
end

class String
  def camelcase
    str = self.dup.capitalize.gsub(/[-_.\s]([a-zA-Z0-9])/) { $1.upcase } \
                  .gsub('+', 'x')
  end

  def snake_case
    str = self.dup.gsub(/[A-Z]/) {|s| "_" + s}
    str = str.downcase.sub(/^\_/, "")
  end
end

module LaunchdPlistStructs
  def valid_keys
    {
      :string => %w[Label UserName GroupName LimitLoadToSessionType Program RootDirectory WorkingDirectory StandardInPath StandardOutPath StandardErrorPath],
      :bool => %w[Disabled EnableGlobbing EnableTransactions OnDemand RunAtLoad InitGroups StartOnMount Debug WaitForDebugger AbandonProcessGroup HopefullyExitsFirst HopefullyExitsLast LowPriorityIO LaunchOnlyOnce],
      :integer => %w[Umask TimeOut ExitTimeOut ThrottleInterval StartInterval Nice],
      :array_of_strings => %w[LimitLoadToHosts LimitLoadFromHosts ProgramArguments WatchPaths QueueDirectories],
      :complex_keys => %w[inetdCompatibility KeepAlive EnvironmentVariables StartCalendarInterval SoftResourceLimits, HardResourceLimits MachServices Sockets]
    }
  end

  module DataMethods
    def classes_for_key_type
      {
        :string => [String], 
        :bool => [TrueClass,FalseClass],
        :integer => [Fixnum], 
        :array_of_strings => [Array],
        :hash_of_bools => [Hash],
        :hash => [Hash],
        :bool_or_string_or_array_of_strings => [TrueClass,FalseClass,String,Array]
      }
    end

    def valid_keys
      {}
    end

    def method_missing method_symbol, *args, &block
      valid_keys.reject(){ |k,v| k == :complex_keys}.each do |key_type, valid_keys_of_those_type|
        if valid_keys_of_those_type.include?(method_symbol.to_s.camelcase)
          return eval("set_or_return #{key_type} method_symbol.to_s.camelcase, *args, &blk")
        end
      end
    end

    def validate_value key_type, key, value
      unless classes_for_key_type[key_type].include? value.class
        raise "Key: #{key}, value: #{value.inspect} is of type #{value.class}. Should be: #{classes_for_key_type[key_type].join ", "}"
      end
      case key_type
      when :array_of_strings, :bool_or_string_or_array_of_strings
        if value.class == Array
          value.each_index do |i|
            unless value[i].class == String
              raise "Element: #{key}[#{i}], value: #{value[i].inspect} is of type #{value[i].class}. Should be: #{classes_for_key_type[:string].join ", "}"
            end
          end
        end
      when :hash_of_bools
        value.each do |k,v|
          unless [TrueClass,FalseClass].include? v.class
            raise "Key: #{key}[#{k}], value: #{v.inspect} is of type #{v.class}. Should be: #{classes_for_key_type[:bool].join ", "}"
          end
        end
      end
    end

    def set_or_return key_type, key, value=nil
      if value
        validate_value key_type, key, value
        @hash[key] = value
      else
        @orig[key]
      end
    end
  end
  include DataMethods
  
  class ArrayDict
    include DataMethods
    
    def initialize orig, index=nil, &blk
      @orig = orig
      if index
        @enclosing_block = self.class.to_s.snake_case + "[#{index}]"
        @orig = @orig[index]
      else
        @enclosing_block = self.class.to_s.snake_case
      end
      @hash = {}
      instance_eval(&blk)
    end

    def hash
      @hash
    end

    def select *keys
      import_all
      keys.each do |k|
        @hash[k] = @orig[k]
      end
      unselect_all
    end

    def unselect *keys
      keys.each do |k|
        @orig.delete k
      end
    end

    def unselect_all
      @orig = nil
      @hash = {}
    end

    def import_all
      @hash = @orig
    end
  end

  # :call-seq:
  #   inetdCompatibility({:wait => true})
  #   inetdCompatibility -> hash or nil
  #
  # inetd_compatibility <hash>
  # The presence of this key specifies that the daemon expects to be run as if it were launched from inetd.
  # 
  #   :wait <boolean>
  #   This flag corresponds to the "wait" or "nowait" option of inetd. If true, then the listening socket is passed via the standard in/out/error file descriptors.
  #   If false, then accept(2) is called on behalf of the job, and the result is passed via the standard in/out/error descriptors.
  def inetd_compatibility value=nil
    key = "inetdCompatibility"
    case value
    when Hash
      if value[:wait]
        @hash[key] = value[:wait]
      else
        raise "Invalid value: #{method_name} #{value.inspect}. Should be: #{method_name} :wait => true|false"
      end
    when nil
      @hash[key]
    else
      raise "Invalid value: #{method_name} #{value.inspect}. Should be: #{method_name} :wait => true|false"
    end
  end
  
  class KeepAlive < ArrayDict
    def valid_keys
      {
        :bool => %w[SuccessfulExit NetworkState],
        :hash_of_bools => %w[PathState OtherJobEnabled]
      }
    end
  end

  # :call-seq:
  #   keep_alive(true)
  #   keep_alive(false)
  #   keep_alive { block_of_keys }
  #   keep_alive => true, false, Hash, or nil
  #
  # keep_alive <boolean or block of keys>
  # This optional key is used to control whether your job is to be kept continuously running or to let demand and conditions control the invocation. The default is
  # false and therefore only demand will start the job. The value may be set to true to unconditionally keep the job alive. Alternatively, a dictionary of conditions
  # may be specified to selectively control whether launchd keeps a job alive or not. If multiple keys are provided, launchd ORs them, thus providing maximum flexibil-
  # ity to the job to refine the logic and stall if necessary. If launchd finds no reason to restart the job, it falls back on demand based invocation.  Jobs that exit
  # quickly and frequently when configured to be kept alive will be throttled to converve system resources.
  # 
  # keep_alive do
  # 
  #   successful_exit <boolean>
  #   If true, the job will be restarted as long as the program exits and with an exit status of zero.  If false, the job will be restarted in the inverse condi-
  #   tion.  This key implies that "RunAtLoad" is set to true, since the job needs to run at least once before we can get an exit status.
  # 
  #   network_state <boolean>
  #   If true, the job will be kept alive as long as the network is up, where up is defined as at least one non-loopback interface being up and having IPv4 or IPv6
  #   addresses assigned to them.  If false, the job will be kept alive in the inverse condition.
  # 
  #   path_state <hash of booleans>
  #   Each key in this dictionary is a file-system path. If the value of the key is true, then the job will be kept alive as long as the path exists.  If false, the
  #   job will be kept alive in the inverse condition. The intent of this feature is that two or more jobs may create semaphores in the file-system namespace.
  # 
  #   other_job_enabled <hash of booleans>
  #   Each key in this dictionary is the label of another job. If the value of the key is true, then this job is kept alive as long as that other job is enabled.
  #   Otherwise, if the value is false, then this job is kept alive as long as the other job is disabled.  This feature should not be considered a substitute for
  #   the use of IPC.
  # 
  # end
  # 
  # Example:
  # 
  # keep_alive do
  #   successful_exit true
  #   network_state false
  # end
  # 
  def keep_alive value=nil, &blk
    key = "KeepAlive"
    
    case value
    when TrueCass, FalseClass
      @hash[key] = value
    when nil
      if blk
        @hash[key] ||= {}
        @hash[key] = ::LaunchdPlistStructs::KeepAlive.new(@hash[key],&blk).hash
      else
        @hash[key]
      end
    else
      raise "Invalid value: #{method_name} #{value.inspect}. Should be: #{method_name} true|false, or #{method_name} { block }"
    end
  end

  # :call-seq:
  #   environment_variables({"VAR1" => "VAL1", "VAR2" => "VAL2"})
  #   environment_variables -> hash or nil
  #
  # environment_variables <hash of strings>
  # This optional key is used to specify additional environmental variables to be set before running the job.
  def environment_variables value=nil, &blk
    key = "EnvironmentVariables"
    case value
    when Hash
      value.each do |k,v|
        unless k.class == String
          raise "Invalid key: #{method_name}[#{k.inspect}]. Should be of type String"
        end
        unless v.class == String
          raise "Invalid value: #{method_name}[#{k.inspect}] = #{v.inspect}. Should be of type String"
        end
      end
      @hash[key] = value
    when nil
      @hash[key]
    else
      raise "Invalid value: #{method_name} #{value.inspect}. Should be: #{method_name} { hash_of_bools }"
    end
  end

  class StartCalendarInterval < ArrayDict
    def valid_keys
      { :integer => %w[Minute Hour Day Weekday Month] }
    end
  end

  # :call-seq:
  #   start_calendar_interval(array_index=nil) { block_of_keys }
  #   start_calendar_interval -> array or nil
  #
  # start_calendar_interval <array_index=nil> <block of keys>
  # This optional key causes the job to be started every calendar interval as specified. Missing arguments are considered to be wildcard. The semantics are much like
  # crontab(5).  Unlike cron which skips job invocations when the computer is asleep, launchd will start the job the next time the computer wakes up.  If multiple
  # intervals transpire before the computer is woken, those events will be coalesced into one event upon wake from sleep.
  # 
  # start_calendar_interval index=nil do
  # 
  #   Minute <integer>
  #   The minute on which this job will be run.
  # 
  #   Hour <integer>
  #   The hour on which this job will be run.
  # 
  #   Day <integer>
  #   The day on which this job will be run.
  # 
  #   Weekday <integer>
  #   The weekday on which this job will be run (0 and 7 are Sunday).
  # 
  #   Month <integer>
  #   The month on which this job will be run.
  # 
  # end
  # 
  # Example:
  # 
  # start_calendar_interval 0 do
  #   hour   02
  #   minute 05
  #   day    06
  # end
  # 
  # start_calendar_interval 1 do
  #   hour   02
  #   minute 05
  #   day    06
  # end
  # 
  def start_calendar_interval index=nil, &blk
    key = "StartCalendarInterval"
    unless [Fixnum,NilClass].include? index
      raise "Invalid index: #{method_name} #{index.inspect}. Should be: #{method_name} <integer>"
    end
    if blk
      @hash[key] ||= []
      h = ::LaunchdPlistStructs::StartCalendarInterval.new(@hash[key],index,&blk).hash
      if index
        @hash[key][index] = h
      else
        @hash[key] << h
      end
    else
      @hash[key]
    end
  end

  class ResourceLimits < ArrayDict
    def valid_keys
      { :integer => %w[Core CPU Data FileSize MemoryLock NumberOfFiles NumberOfProcesses ResidentSetSize Stack] }
    end
  end
  
  # :call-seq:
  #   soft_resource_limits { block_of_keys }
  #   soft_resource_limits -> hash or nil
  #
  # soft_resource_limits <block of keys>
  # Resource limits to be imposed on the job. These adjust variables set with setrlimit(2).  The following keys apply:
  # 
  # soft_resource_limits do
  # 
  #   Core <integer>
  #   The largest size (in bytes) core file that may be created.
  # 
  #   CPU <integer>
  #   The maximum amount of cpu time (in seconds) to be used by each process.
  # 
  #   Data <integer>
  #   The maximum size (in bytes) of the data segment for a process; this defines how far a program may extend its break with the sbrk(2) system call.
  # 
  #   FileSize <integer>
  #   The largest size (in bytes) file that may be created.
  # 
  #   MemoryLock <integer>
  #   The maximum size (in bytes) which a process may lock into memory using the mlock(2) function.
  # 
  #   NumberOfFiles <integer>
  #   The maximum number of open files for this process.  Setting this value in a system wide daemon will set the sysctl(3) kern.maxfiles (SoftResourceLimits) or
  #   kern.maxfilesperproc (HardResourceLimits) value in addition to the setrlimit(2) values.
  # 
  #   NumberOfProcesses <integer>
  #   The maximum number of simultaneous processes for this user id.  Setting this value in a system wide daemon will set the sysctl(3) kern.maxproc (SoftResource-
  #   Limits) or kern.maxprocperuid (HardResourceLimits) value in addition to the setrlimit(2) values.
  # 
  #   ResidentSetSize <integer>
  #   The maximum size (in bytes) to which a process's resident set size may grow.  This imposes a limit on the amount of physical memory to be given to a process;
  #   if memory is tight, the system will prefer to take memory from processes that are exceeding their declared resident set size.
  # 
  #   Stack <integer>
  #   The maximum size (in bytes) of the stack segment for a process; this defines how far a program's stack segment may be extended.  Stack extension is performed
  #   automatically by the system.
  # 
  # end
  # 
  # Example:
  # 
  # soft_resource_limits do
  #   NumberOfProcesses 4
  #   NumberOfFiles 512
  # end
  # 
  def soft_resource_limits value=nil, &blk
    key = "SoftResourceLimits"
    if blk
      @hash[key] ||= {}
      @hash[key] = ::LaunchdPlistStructs::ResourceLimits.new(@hash[key],&blk).hash
    else
      @hash[key]
    end
  end

  # :call-seq:
  #   hard_resource_limits { block_of_keys }
  #   hard_resource_limits -> hash or nil
  #
  # hard_resource_limits <block of keys>
  # Resource limits to be imposed on the job. These adjust variables set with setrlimit(2).  The following keys apply:
  # 
  # hard_resource_limits do
  # 
  #   Core <integer>
  #   The largest size (in bytes) core file that may be created.
  # 
  #   CPU <integer>
  #   The maximum amount of cpu time (in seconds) to be used by each process.
  # 
  #   Data <integer>
  #   The maximum size (in bytes) of the data segment for a process; this defines how far a program may extend its break with the sbrk(2) system call.
  # 
  #   FileSize <integer>
  #   The largest size (in bytes) file that may be created.
  # 
  #   MemoryLock <integer>
  #   The maximum size (in bytes) which a process may lock into memory using the mlock(2) function.
  # 
  #   NumberOfFiles <integer>
  #   The maximum number of open files for this process.  Setting this value in a system wide daemon will set the sysctl(3) kern.maxfiles (SoftResourceLimits) or
  #   kern.maxfilesperproc (HardResourceLimits) value in addition to the setrlimit(2) values.
  # 
  #   NumberOfProcesses <integer>
  #   The maximum number of simultaneous processes for this user id.  Setting this value in a system wide daemon will set the sysctl(3) kern.maxproc (SoftResource-
  #   Limits) or kern.maxprocperuid (HardResourceLimits) value in addition to the setrlimit(2) values.
  # 
  #   ResidentSetSize <integer>
  #   The maximum size (in bytes) to which a process's resident set size may grow.  This imposes a limit on the amount of physical memory to be given to a process;
  #   if memory is tight, the system will prefer to take memory from processes that are exceeding their declared resident set size.
  # 
  #   Stack <integer>
  #   The maximum size (in bytes) of the stack segment for a process; this defines how far a program's stack segment may be extended.  Stack extension is performed
  #   automatically by the system.
  # 
  # end
  # 
  # Example:
  # 
  # hard_resource_limits do
  #   NumberOfProcesses 4
  #   NumberOfFiles 512
  # end
  # 
  def hard_resource_limits value=nil, &blk
    key = "HardResourceLimits"
    if blk
      @hash[key] ||= {}
      @hash[key] = ::LaunchdPlistStructs::ResourceLimits.new(@hash[key],&blk).hash
    else
      @hash[key]
    end
  end

	class MachServices < ArrayDict
  	class MachService < ArrayDict
  	  def valid_keys
        { :bool => %w[ResetAtClose HideUntilCheckIn] }
      end
    end

	  def add service, value=nil, &blk
      if value
  	    @hash[service] = value
        set_or_return :bool, service, value
      elsif blk
        @hash[service] = {}
        @hash[service] = ::LaunchdPlistStructs::MachServices::MachService.new(@hash[service],&blk).hash
      else
        @orig
      end
    end    
  end
  
  # :call-seq:
  #   mach_services { block }
  #   mach_services -> hash or nil
  #
  # mach_services <dictionary of booleans or a dictionary of dictionaries>
  # This optional key is used to specify Mach services to be registered with the Mach bootstrap sub-system.  Each key in this dictionary should be the name of service
  # to be advertised. The value of the key must be a boolean and set to true.  Alternatively, a dictionary can be used instead of a simple true value.
  # 
  #   ResetAtClose <boolean>
  #   If this boolean is false, the port is recycled, thus leaving clients to remain oblivious to the demand nature of job. If the value is set to true, clients
  #   receive port death notifications when the job lets go of the receive right. The port will be recreated atomically with respect to bootstrap_look_up() calls,
  #   so that clients can trust that after receiving a port death notification, the new port will have already been recreated. Setting the value to true should be
  #   done with care. Not all clients may be able to handle this behavior. The default value is false.
  # 
  #   HideUntilCheckIn <boolean>
  #   Reserve the name in the namespace, but cause bootstrap_look_up() to fail until the job has checked in with launchd.
  # 
  # Finally, for the job itself, the values will be replaced with Mach ports at the time of check-in with launchd.
  # 
  # Example:
  # 
  # mach_services do
  #   add "com.apple.afpfs_checkafp", true
  # end
  # 
  # mach_services do
  #   add "com.apple.AppleFileServer" do
  #     hide_until_check_in true
  #     reset_at_close false
  #   end
  # end
  # 
  def mach_services value=nil, &blk
    key = "MachServices"
    if blk
      @hash[key] ||= {}
      @hash[key] = ::LaunchdPlistStructs::MachServices.new(@hash[key],&blk).hash
    else
      @hash[key]
    end
  end

  class Socket < ArrayDict
    def valid_keys
      {
        :string => %w[SockType SockNodeName SockServiceName SockFamily SockProtocol SockPathName SecureSocketWithKey MulticastGroup],
        :bool => %w[SockPassive],
        :integer => %w[SockPathMode],
        :bool_or_string_or_array_of_strings => %w[Bonjour]
      }
    end

  end

  def sockets value=nil, &blk
    # :call-seq:
    #   sockets(array_index=nil) { block_of_keys }
    #   sockets -> array or nil
    #
    # sockets <array_index=nil> <block of keys>
    # Sockets <dictionary of dictionaries... OR dictionary of array of dictionaries...>
    # 
    # Please See: http://developer.apple.com/mac/library/documentation/MacOSX/Conceptual/BPSystemStartup/Articles/LaunchOnDemandDaemons.html
    # for more information about how to properly use the Sockets feature
    # 
    # This optional key is used to specify launch on demand sockets that can be used to let launchd know when to run the job. The job must check-in to get a copy of the
    # file descriptors using APIs outlined in launch(3).  The keys of the top level Sockets dictionary can be anything. They are meant for the application developer to
    # use to differentiate which descriptors correspond to which application level protocols (e.g. http vs. ftp vs. DNS...).  At check-in time, the value of each Sockets
    # dictionary key will be an array of descriptors. Daemon/Agent writers should consider all descriptors of a given key to be to be effectively equivalent, even though
    # each file descriptor likely represents a different networking protocol which conforms to the criteria specified in the job configuration file.
    # The parameters below are used as inputs to call getaddrinfo(3).
    # 
    # sockets index=nil do
    # 
    #   SockType <string>
    #   This optional key tells launchctl what type of socket to create. The default is "stream" and other valid values for this key are "dgram" and "seqpacket"
    #   respectively.
    # 
    #   SockPassive <boolean>
    #   This optional key specifies whether listen(2) or connect(2) should be called on the created file descriptor. The default is true ("to listen").
    # 
    #   SockNodeName <string>
    #   This optional key specifies the node to connect(2) or bind(2) to.
    # 
    #   SockServiceName <string>
    #   This optional key specifies the service on the node to connect(2) or bind(2) to.
    # 
    #   SockFamily <string>
    #   This optional key can be used to specifically request that "IPv4" or "IPv6" socket(s) be created.
    # 
    #   SockProtocol <string>
    #   This optional key specifies the protocol to be passed to socket(2).  The only value understood by this key at the moment is "TCP".
    # 
    #   SockPathName <string>
    #   This optional key implies SockFamily is set to "Unix". It specifies the path to connect(2) or bind(2) to.
    # 
    #   SecureSocketWithKey <string>
    #   This optional key is a variant of SockPathName. Instead of binding to a known path, a securely generated socket is created and the path is assigned to the
    #   environment variable that is inherited by all jobs spawned by launchd.
    # 
    #   SockPathMode <integer>
    #   This optional key specifies the mode of the socket. Known bug: Property lists don't support octal, so please convert the value to decimal.
    # 
    #   Bonjour <boolean or string or array of strings>
    #   This optional key can be used to request that the service be registered with the mDNSResponder(8).  If the value is boolean, the service name is inferred from
    #   the SockServiceName.
    # 
    #   MulticastGroup <string>
    #   This optional key can be used to request that the datagram socket join a multicast group.  If the value is a hostname, then getaddrinfo(3) will be used to
    #   join the correct multicast address for a given socket family.  If an explicit IPv4 or IPv6 address is given, it is required that the SockFamily family also be
    #   set, otherwise the results are undefined.
    # 
    # end
    # 
    # Example:
    # 
    # sockets 0 do
    #   sock_node_name "127.0.0.1"
    #   sock_service_name "ipp"
    # end
    # 
    # sockets 1 do
    #   sock_path_mode 49663
    #   sock_path_name "/private/var/run/cupsd"
    # end
    # 
    key = "Sockets"
    unless [Fixnum,NilClass].include? index
      raise "Invalid index: #{method_name} #{index.inspect}. Should be: #{method_name} <integer>"
    end
    if blk
      @hash[key] ||= []
      h = ::LaunchdPlistStructs::Socket.new(@hash[key],index,&blk).hash
      if index
        @hash[key][index] = h
      else
        @hash[key] << h
      end
    else
      @hash[key]
    end
  end
end

# LaunchdLibxmlPlistParser requires libxml-ruby, a substantial library
# http://rubyforge.org/frs/?group_id=494&release_id=4388
require 'libxml-bindings'
class LaunchdLibxmlPlistParser
  include ::BrewMixins
  include ::LaunchdPlistStructs

  def initialize filename, *args, &blk
    @filename = filename
    raise "Can't find filename: #{@filename}" unless File.exists? @filename
    validate
  end

  def validate
    system "plutil #{@filename}"
  end

  def tree_hash n
    hash = {}
    n_xml_keys = n.nodes["key"]
    n_xml_keys.each do |n|
      k = n.inner_xml
      vnode = n.next
      case vnode.name
      when "true", "false"
        hash[k] = eval(vnode.name)
      when "string"
        hash[k] = vnode.inner_xml
      when "integer"
        hash[k] = vnode.inner_xml.to_i
      when "array"
        hash[k] = tree_array(vnode)
      when "dict"
        hash[k] = tree_hash(vnode)
      else
        raise "Unsupported / not recognized plist key: #{vnode.name}"
      end
    end
    return hash
  end

  def tree_array n
    array = []
    n.children.each do |node|
      case node.name
      when "true", "false"
        array << eval(node.name)
      when "string"
        array << node.inner_xml
      when "integer"
        array << node.inner_xml.to_i
      when "array"
        array << tree_array(node)
      when "dict"
        array << tree_hash(node)
      else
        raise "Unsupported / not recognized plist key: #{vnode.name}"
      end
    end
    return array
  end

  def parse_launchd_plist
    ::LibXML::XML.default_keep_blanks = false
    @string = File.read(@filename)
    @doc = @string.to_xmldoc
    @doc.strip!
    @root = @doc.node["/plist/dict"]
    tree_hash @root
  end

  def filename
    @filename
  end

  def plist_struct
    @plist_struct ||= parse_launchd_plist
  end
end

class LaunchdPlist
  include ::BrewMixins
  include ::LaunchdPlistStructs
  
  def initialize path_prefix, plist_str, *program_args, &blk
    plist_str << ".plist" unless plist_str =~ /\.plist$/

    @filename = nil
    if plist_str =~ /^\//
      @filename = plist_str
    else
      @filename = "#{path_prefix}/#{plist_str}"
    end
    
    @label = @filename.match(/^.*\/(.*)\.plist$/)[1]
    @shortname = filename.match(/^.*\.(.*)$/)[1]

    if program_args
      program_args.each do |arg|
        raise "Program_arg: #{arg} is of type: #{arg.class}. Should be of type: String"
      end
      # split program_args into array if its just one long string
      program_args = program_args[0].split if program_args.size == 1 && !( prefix =~ /\s/ )
      @program_arguments = program_args
    end

    @block = blk
    eval_plist_block(&@block) if @block
    raise "Not enough information to generat plist: \"#{@filename}\" - No program arguments given" unless @program_arguments    
  end

  def eval_plist_block &blk
    instance_eval blk
  end

  def finalize
    if File.exists? @filename
      if override_plist_keys?
        @hash = @obj = ::LibxmlLaunchdPlistParser.new(@filename).plist_struct
        eval_plist_block(&@block) if @block
        write_plist
      end
    else
      write_plist
    end
    validate
  end
  
  def override_plist_keys?
    return true unless @label == @filename.match(/^.*\/(.*)\.plist$/)[1]
    vars = self.instance_variables - ["@filename","@label","@shortname","@block","@hash","@obj"]
    return true unless vars.empty?
  end

  def write_plist
    # require 'haml'
    require 'haml_embedded'
    engine = Haml::Engine.new File.read("launchd_plist.haml")
    rendered_xml_output = engine.render self
    File.open(@filename,'w') do |o|
      o << rendered_xml_output
    end
  end

  def validate
    system "plutil #{@filename}"
  end
end





