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
  # methods for checking, validating, and creating
  # calenderintervals, watchpaths, listeners, socket, etc
  # and putting them into their nested hash structures

  inetdCompatibility
  KeepAlive
  EnvironmentVariables
  StartCalendarInterval
  SoftResourceLimits, HardResourceLimits
  MachServices
  Sockets

  def classes_for_key_type
    {
      :string => [String], :bool => [TrueClass, FalseClass], :integer => [Fixnum], :array_of_strings => [Array]
    }
  end

  def valid_keys
    {
      :string => %w[Label UserName GroupName LimitLoadToSessionType Program RootDirectory WorkingDirectory StandardInPath StandardOutPath StandardErrorPath],
      :bool => %w[Disabled EnableGlobbing EnableTransactions OnDemand RunAtLoad InitGroups StartOnMount Debug WaitForDebugger AbandonProcessGroup HopefullyExitsFirst HopefullyExitsLast LowPriorityIO LaunchOnlyOnce],
      :integer => %w[Umask TimeOut ExitTimeOut ThrottleInterval StartInterval Nice],
      :array_of_strings => %w[LimitLoadToHosts LimitLoadFromHosts ProgramArguments WatchPaths QueueDirectories]
    }
  end

  def method_missing method_symbol, *args, &block
    valid_keys.each do |key_type, valid_keys_of_those_type|
      if valid_keys_of_those_type.include?(method_symbol.to_s.camelcase)
        return eval("set_or_return #{key_type} method_symbol.to_s.camelcase, *args, &blk")
      end
    end
  end

  def validate_value key_type, key, value
    unless classes_for_key_type[key_type].include? value.class
      raise "Key: #{key}, value: #{value.inspect} is of type #{value.class}. Should be: #{classes_for_key_type[key_type].join ", "}"
    end
  end

  def set_or_return key_type, key, value
    if value
      validate_value key_type, key, value
      @xml_keys[key] = value
    else
      @xml_keys[key]
    end
  end
end

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
    eval_plist_block &@block if @block
    raise "Not enough information to generat plist: \"#{@filename}\" - No program arguments given" unless @program_arguments    
  end

  def eval_plist_block &blk
    # include methods for setting the filename, etc
    # read existing from @xml_keys, to load up any existing instance vars
    instance_eval blk
  end

  def finalize
    if File.exists? @filename
      if override_plist_keys?
        @xml_keys = ::LibxmlLaunchdPlistParser.new(@filename).plist_struct
        eval_plist_block &@block if @block
        write_plist
      end
    else
      write_plist
    end
    validate
  end
  
  def override_plist_keys?
    return true unless @label == @filename.match(/^.*\/(.*)\.plist$/)[1]
    vars = self.instance_variables - ["@filename","@label","@shortname","@block","@xml_keys"]
    return true unless vars.empty?
  end

  def write_plist
    require 'rubygems'
    system("gem install haml") unless Gem.available? "haml"
    require 'haml'
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





