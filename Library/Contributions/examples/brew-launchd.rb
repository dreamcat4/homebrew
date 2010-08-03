# `brew launchd` is an extension to homebrew to start/stop launchd services
# `brew launchd --help` or `man brew-launchd` for more information.

argv = ARGV.dup
ARGV.clear

require 'formula'
@formula = Formula.factory("brew-launchd")

if @formula
  if not @formula.installed?
    ohai "Installing brew-launchd extensions",
    "This should only take a moment", "Please read the Caveats"
    require 'formula_installer'
    installer = FormulaInstaller.new
    installer.install @formula
    puts ""
  end

  Object.send(:remove_const, :BrewLaunchd)
  cmd = Pathname.new(__FILE__).basename

  ARGV.replace argv
  require "#{@formula.prefix}/bin/#{cmd}"
else
  raise FormulaUnspecifiedError
end

