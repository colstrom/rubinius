def bootstrap_rubinius(cmd, options=nil)
  gems_path = File.expand_path "../", BUILD_CONFIG[:bootstrap_gems_dir]
  ENV["RBX_GEMS_PATH"] = gems_path
  ENV["RBX_PREFIX_PATH"] = BUILD_CONFIG[:build_prefix]
  sh "#{BUILD_CONFIG[:build_exe]} #{cmd} #{options}"
ensure
  ENV.delete "RBX_GEMS_PATH"
  ENV.delete "RBX_PREFIX_PATH"
end

namespace :gems do
  desc 'Install the pre-installed gems'
  task :install do
    clean_environment

    cmd = "#{BUILD_CONFIG[:sourcedir]}/rakelib/preinstall_gems.rb"

    Dir.chdir BUILD_CONFIG[:gems_cache] do
      bootstrap_rubinius cmd
    end
  end

  task :melbourne do
    prefix = "#{BUILD_CONFIG[:build_prefix]}#{BUILD_CONFIG[:runtimedir]}"
    path = Dir["#{prefix}/gems/rubinius-melbourne-*/ext/rubinius/code/melbourne"].first
    Dir.chdir path do
      begin
        ENV["RBX_RUN_COMPILED"] = "1"
        bootstrap_rubinius "./extconf.rbc"
        sh "#{BUILD_CONFIG[:build_make]} && #{BUILD_CONFIG[:build_make]} install"
      ensure
        ENV.delete "RBX_RUN_COMPILED"
      end
    end
  end

  task :extensions do
    clean_environment

    gems_dir = BUILD_CONFIG[:bootstrap_gems_dir]
    build_gem_extconf = "extconf.rb"

    # Build the gems needed to run mkmf.rb
    names = FileList["#{gems_dir}/rubysl-{etc,fcntl}*/**/extconf.rb"]
    names.each do |name|
      Dir.chdir File.dirname(name) do
        bootstrap_rubinius build_gem_extconf
      end
    end

    # Build the rest of the gems
    names = FileList["#{gems_dir}/**/extconf.rb"].exclude(
      %r[.*/rubinius-melbourne-.*],
      %r[.*/rubysl-(etc|fcntl)-.*]
    )

    unless BUILD_CONFIG[:darwin] and
             ENV["TRAVIS_OS_NAME"] != "osx" and
             `which brew`.chomp.size > 0 and
             $?.success? and
             (openssl = `brew --prefix #{ENV["RBX_OPENSSL"] || "openssl"}`.chomp).size > 0
      openssl = false
    end

    re = %r[(.*)/(ext|lib)/[^/]+/(.*extconf.rb)]
    names.each do |name|
      next unless m = re.match(name)

      ext_name = "#{File.basename(File.dirname(name))}.#{$dlext}"
      dest_path = File.join m[1], "lib", File.dirname(m[3])
      next if File.exist? File.join(dest_path, ext_name)

      Dir.chdir File.dirname(name) do
        puts "Building #{m[1]}..."

        if m[1] =~ /openssl/ and openssl
          options = "--with-cppflags=-I#{openssl}/include --with-ldflags=-L#{openssl}/lib"
        else
          options = nil
        end

        bootstrap_rubinius build_gem_extconf, options unless File.exist? "Makefile"
        sh "#{BUILD_CONFIG[:build_make]}", :verbose => $verbose

        if File.exist? ext_name
          FileUtils.mkdir_p dest_path
          FileUtils.cp ext_name, dest_path
        end
      end
    end
  end
end
