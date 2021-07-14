require 'yaml'
require 'open-uri'

APP = YAML.load(File.read(".app.yml"), filename: ".app.yml", symbolize_names: true)
TMP_DIR = "tmp"
HELMV2_DIR = "#{TMP_DIR}/helmv2"
HELM_PKG_DIR = "#{TMP_DIR}/packaged-chart"
CLIENT_DIR = "client"

require 'rake/clean'
CLEAN << TMP_DIR << CLIENT_DIR

def get_var(name, env_name: name.to_s.upcase, yml_name: name.to_s.downcase.to_sym, default: nil, prompt: true, required: true)
  value = ENV[env_name]
  value ||= APP[yml_name]
  value ||= default

  if value.nil? && $stdin.tty? && prompt
    print "Enter '#{name}': "
    value = $stdin.gets
  end

  fail "'#{name}' is required" if value.nil? && required
  value
end

def gsub_file(file, pattern, replace)
  File.write(file, File.read(file).gsub(pattern, replace))
end

def confirm_execute(*cmds)
  puts "Will execute:"
  cmds.each {|c| puts c}
  print "\nProceed (y/n)? "
  if $stdin.gets =~ /^y/i
    cmds.each { |c| sh c }
  else
    puts "Aborted"
  end
end

directory HELMV2_DIR

file "#{HELMV2_DIR}/#{APP[:name]}/Chart.yaml" => [HELMV2_DIR] do
  cp_r "helm/#{APP[:name]}", HELMV2_DIR, preserve: true
  cp_r "helm/helmv2/.", "#{HELMV2_DIR}/#{APP[:name]}/", preserve: true
  chart = File.read("#{HELMV2_DIR}/#{APP[:name]}/Chart.yaml")
  chart = chart.gsub(/apiVersion: v2/, "apiVersion: v1")
  chart = chart.gsub(/version: ([0-9.]*)/, 'version: \1-helmv2')
  File.write("#{HELMV2_DIR}/#{APP[:name]}/Chart.yaml", chart)
end

task :generate_helmv2 => ["#{HELMV2_DIR}/#{APP[:name]}/Chart.yaml"]

directory HELM_PKG_DIR

HELM_SRC_DIR = "helm/#{APP[:name]}"
task :helm_build_package => [HELM_PKG_DIR] do
  sh "helm package #{HELM_SRC_DIR}", chdir: HELM_PKG_DIR
end

HELMV2_SRC_DIR = "#{HELMV2_DIR}/#{APP[:name]}"
task :helmv2_build_package => [HELM_PKG_DIR, :generate_helmv2] do
  sh "helm package #{HELMV2_SRC_DIR}", chdir: HELM_PKG_DIR
end

task :helm_index => [:helm_build_package, :helmv2_build_package] do
  helm_repo_url = get_var('HELM_REPO_URL')

  maybe_merge=""
  begin
    File.write("#{TMP_DIR}/old-index.yaml", IO.read("#{helm_repo_url}/index.yaml"))
    maybe_merge="--merge #{TMP_DIR}/old-index.yaml"
  rescue
    puts "No pre-existing helm index at #{helm_repo_url}"
  end

  sh "helm repo index #{maybe_merge} --url #{helm_repo_url} #{TMP_DIR}/packaged-chart/"

end

task :helm_package => [:helm_index]

task :build_development => [:client] do
  image_name = get_var(:image_name, default: "#{APP[:name]}-development", prompt: false, required: false)
  sh "docker build --target development -t #{image_name} ."
end

task :test => [:build_development] do
  image_name = get_var(:image_name, default: "#{APP[:name]}-development", prompt: false, required: false)
  if ENV['CI'] && ENV['CODECOV_TOKEN']
    sh "set -e && ci_env=$(curl -s https://codecov.io/env | bash) && docker run -e CI -e CODECOV_TOKEN ${ci_env} #{image_name} test"
  else
    sh "docker run -e CI -e CODECOV_TOKEN #{image_name} test"
  end
end

task :rspec do
  require "rspec/core/rake_task"
  RSpec::Core::RakeTask.new(:spec)
  Rake::Task[:spec].invoke
end

task :build_release => [:client] do
  image_name = get_var(:image_name, default: "#{APP[:name]}", prompt: false, required: false)
  sh "docker build --target release -t #{image_name} ."
end

task :docker_push do
  tags = get_var(:tags)
  tags = tags.split
  tags.each do |tag|
    puts "Pushing version '#{tag}' to docker hub"
    sh "docker tag #{APP[:name]} #{APP[:org]}/#{APP[:name]}:#{tag}"
    sh "docker push #{APP[:org]}/#{APP[:name]}:#{tag}"
  end
end

task :set_version do
  version = get_var('VERSION')

  gsub_file("helm/#{APP[:name]}/Chart.yaml",
            /^version:.*/, "version: #{version}")
  gsub_file("helm/#{APP[:name]}/Chart.yaml",
            /^appVersion:.*/, "appVersion: #{version}")
  gsub_file(".app.yml",
            /version:.*/, "version: #{version}")
end

task :tag_version do
  raise "The git tree is dirty, a clean tree is required to tag version" unless `git diff --stat`.empty?

  version = get_var('VERSION')

  cmds = []
  cmds << "git tag -f \"v#{version}\""
  cmds << 'git push -f --tags'
  confirm_execute(*cmds)
end

task :changelog do
  changelog_file = Dir['CHANGELOG*'].first
  entries = ""
  sha_url_format = "../../commit/%h"

  current_version = get_var('CURRENT_VERSION', prompt: false, yml_name: :version)

  starting_version = nil
  ending_version = nil, ending_version_name = nil

  version_range = get_var('VERSION_RANGE', prompt: false, required: false)
  if version_range
    first_ver, second_ver = version_range.split("..")
    starting_version = "v#{first_ver.gsub(/^[^\d]*/, '')}" if ! first_ver.nil? && first_ver.size > 0
    ending_version = "v#{second_ver.gsub(/^[^\d]*/, '')}" if ! second_ver.nil? && second_ver.size > 0
    ending_version_name = ending_version if ending_version
  end

  # If we already have a changelog, make the starting_version be the
  # last one in the changelog
  #
  if ! starting_version && File.exist?(changelog_file)
    entries = File.read(changelog_file)
    head = entries.split.first
    if head =~ /(\d+\.\d+\.\d+).*/
      starting_version = "v#{$1}"

      if current_version == starting_version
        puts "WARN: current_version is the same as most recent changelog: #{current_version}"
      end
    end
  end

  # Get a list of current tags
  tags = `git tag -l`.split
  tags = tags.sort_by {|t| t[1..-1].split(".").collect {|s| s.to_i } }
  newest_tag = tags[-1]

  if current_version == newest_tag
    # When generating CHANGELOG after release, we want the last tag as the ending version
    ending_version = newest_tag
    ending_version_name = newest_tag
  else
    # When generating CHANGELOG before release, we want the current ver as the ending version
    ending_version = "HEAD"
    ending_version_name = current_version
  end

  if starting_version
    version_selector = "#{starting_version}..#{ending_version}"
  else
    puts "WARN: No starting version, dumping entire history, try: rake changelog VERSION=v1.2.3"
    version_selector = ""
  end

  # Generate changelog from repo
  puts "Generating a changelog for #{version_selector}"
  log=`git log --pretty='format:%s [%h](#{sha_url_format})' #{version_selector}`.lines.to_a

  # Strip out maintenance entries
  log = log.delete_if do |l|
    l =~ /^Regenerated? gemspec/ ||
      l =~ /^version bump/i ||
      l =~ /^bump version/i ||
      l =~ /^updated? changelog/i ||
      l =~ /^merged? branch/i
  end

  # Write out changelog file
  File.open(changelog_file, 'w') do |out|
    ver_title = ending_version_name.gsub(/^v/, '') + " (#{Time.now.strftime("%m/%d/%Y")})"
    out.puts ver_title
    out.puts "-" * ver_title.size
    out.puts "\n"
    log.each { |l| out.print "* #{l}" }
    out.puts "\n\n"
    out.puts entries
  end
end

task :console do
  $LOAD_PATH.unshift File.expand_path("lib", __dir__)
  require "bundler/setup"
  require APP[:name]
  require "pry"
  Pry.start
end

file "#{CLIENT_DIR}/Gemfile" => "openapi.yml" do
  rm_rf "client"
  sh *%W[
    docker run --rm
      -v #{Dir.pwd}:/data
      --user #{Process.uid}:#{Process.gid}
      openapitools/openapi-generator-cli generate
        -i /data/openapi.yml
        -g ruby
        -o /data/client
        --library faraday
        --additional-properties=gemName=cloudtruth-client
  ]
end

task :client => "#{CLIENT_DIR}/Gemfile"
