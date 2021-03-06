class Caveats
  attr_reader :f

  def initialize(f)
    @f = f
  end

  def caveats
    caveats = []
    caveats << f.caveats if f.caveats.to_s.length > 0
    caveats << f.keg_only_text if f.keg_only? && f.respond_to?(:keg_only_text)
    caveats << bash_completion_caveats
    caveats << zsh_completion_caveats
    caveats << plist_caveats
    caveats << python_caveats
    caveats << app_caveats
    caveats.compact.join("\n")
  end

  def empty?
    caveats.empty?
  end

  private

  def keg
    @keg ||= [f.prefix, f.opt_prefix, f.linked_keg].map do |d|
      Keg.new(d.resolved_path) rescue nil
    end.compact.first
  end

  def bash_completion_caveats
    if keg and keg.completion_installed? :bash then <<-EOS.undent
      Bash completion has been installed to:
        #{HOMEBREW_PREFIX}/etc/bash_completion.d
      EOS
    end
  end

  def zsh_completion_caveats
    if keg and keg.completion_installed? :zsh then <<-EOS.undent
      zsh completion has been installed to:
        #{HOMEBREW_PREFIX}/share/zsh/site-functions
      EOS
    end
  end

  def python_caveats
    return unless keg
    return unless keg.python_site_packages_installed?
    return if Formula["python"].installed?
    site_packages = if f.keg_only?
      "#{f.opt_prefix}/lib/python2.7/site-packages"
    else
      "#{HOMEBREW_PREFIX}/lib/python2.7/site-packages"
    end
    dir = "~/Library/Python/2.7/lib/python/site-packages"
    dir_path = Pathname.new(dir).expand_path
    file = "#{dir}/homebrew.pth"
    file_path = Pathname.new(file).expand_path
    if !file_path.readable? || !file_path.read.include?(site_packages)
      s = "If you need Python to find the installed site-packages:\n"
      s += "  mkdir -p #{dir}\n" unless dir_path.exist?
      s += "  echo '#{site_packages}' > #{file}"
    end
  end

  def app_caveats
    if keg and keg.app_installed?
      <<-EOS.undent
        .app bundles were installed.
        Run `brew linkapps` to symlink these to /Applications.
      EOS
    end
  end

  def plist_caveats
    s = []
    if f.plist or (keg and keg.plist_installed?)
      destination = f.plist_startup ? '/Library/LaunchDaemons' \
                                    : '~/Library/LaunchAgents'

      plist_filename = f.plist_path.basename
      plist_link = "#{destination}/#{plist_filename}"
      plist_domain = f.plist_path.basename('.plist')
      destination_path = Pathname.new File.expand_path destination
      plist_path = destination_path/plist_filename

      # we readlink because this path probably doesn't exist since caveats
      # occurs before the link step of installation
      if !plist_path.file? || !plist_path.symlink?
        if f.plist_startup
          s << "To have launchd start #{f.name} at startup:"
          s << "    sudo mkdir -p #{destination}" unless destination_path.directory?
          s << "    sudo cp -fv #{f.opt_prefix}/*.plist #{destination}"
        else
          s << "To have launchd start #{f.name} at login:"
          s << "    mkdir -p #{destination}" unless destination_path.directory?
          s << "    ln -sfv #{f.opt_prefix}/*.plist #{destination}"
        end
        s << "Then to load #{f.name} now:"
        if f.plist_startup
          s << "    sudo launchctl load #{plist_link}"
        else
          s << "    launchctl load #{plist_link}"
        end
      # For startup plists, we cannot tell whether it's running on launchd,
      # as it requires for `sudo launchctl list` to get real result.
      elsif f.plist_startup
          s << "To reload #{f.name} after an upgrade:"
          s << "    sudo launchctl unload #{plist_link}"
          s << "    sudo cp -fv #{f.opt_prefix}/*.plist #{destination}"
          s << "    sudo launchctl load #{plist_link}"
      elsif Kernel.system "/bin/launchctl list #{plist_domain} &>/dev/null"
          s << "To reload #{f.name} after an upgrade:"
          s << "    launchctl unload #{plist_link}"
          s << "    launchctl load #{plist_link}"
      else
          s << "To load #{f.name}:"
          s << "    launchctl load #{plist_link}"
      end

      if f.plist_manual
        s << "Or, if you don't want/need launchctl, you can just run:"
        s << "    #{f.plist_manual}"
      end

      s << "" << "WARNING: launchctl will fail when run under tmux." if ENV['TMUX']
    end
    s.join("\n") unless s.empty?
  end
end
