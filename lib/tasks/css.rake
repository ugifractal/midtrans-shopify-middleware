namespace :css do
  desc "Build Tailwind CSS"
  task :build do
    unless system("bun run build:css")
      raise "css:build failed, ensure `bun run build:css` runs without errors"
    end
  end

  desc "Remove CSS builds"
  task :clobber do
    rm_rf Dir["app/assets/builds/**/*.css"], verbose: false
  end
end

if Rake::Task.task_defined?("assets:precompile")
  Rake::Task["assets:precompile"].enhance([ "css:build" ])
end

if Rake::Task.task_defined?("assets:clobber")
  Rake::Task["assets:clobber"].enhance([ "css:clobber" ])
end
