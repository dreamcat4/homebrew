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
class String
  def camelcase
    str = self.dup.capitalize.gsub(/[-_.\s]([a-zA-Z0-9])/) { $1.upcase } \
                  .gsub('+', 'x')
  end

  def snake_case
    str = self.dup.gsub!(/[A-Z]/) {|s| "_" + s}
    str.downcase!.sub!(/^\_/, "")
    str
  end
end

class LaunchdPlist < Object

  def initialize path_prefix, plist_str, program_args*, &blk
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

  def method_missing(symbol, *args)
    # Set an attribute based on the missing method.  If you pass an argument, we'll use that
    # to set the attribute values.  Otherwise, we'll wind up just returning the attribute
    attrs = Chef::Node::Attribute.new(@attribute, @default_attrs, @override_attrs)
    attrs.send(symbol, *args)
  end
  def method_missing(method_symbol, *args, &block)
      # resource call route.
      method_name = method_symbol.to_s
      rname = convert_to_class_name(method_name)
      resource.instance_eval(&block) if block
    end
  end

  def validate
    # replace this with homebrew's system() call
    `plutil #{PLIST_FILENAME}`
    # capture stdout, stderr
    unless $?.exitstatus == 0
      # raise plutil error with the stdout, stderr from above
    end
  end

  class LaunchdPlistStructs
    # methods for checking, validating, and creating 
    # calenderintervals, watchpaths, listeners, socket, etc
    # and putting them into their nested hash structures
  end

  def eval_plist_block &blk
    # include methods for setting the filename, etc
    instance_eval blk
  end

  def override_plist_keys?
    return true unless @label == @filename.match(/^.*\/(.*)\.plist$/)[1]
    vars = self.instance_variables - ["@filename","@label","@shortname","@block","@xml_keys"]
    return true unless vars.empty?
  end

  class LibxmlPlistParser
    # implement plist loading here
  end

  def finalize
    if File.exists? @filename
      if override_plist_keys?
        require 'rubygems'
        system("gem install libxml-bindings") unless Gem.available? "libxml-bindings"
        require 'libxml-bindings'
        #     parse plist xml -> complete nested Hash of @xml_keys
        #     override any keys which were set by our formula
        #     generate xml, write out (overwriting current file)
      end
    else
      write_plist
    end
    validate
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
end





