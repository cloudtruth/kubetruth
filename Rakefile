require 'yaml'
require 'open-uri'

APP = YAML.load(File.read(".app.yml"), symbolize_names: true)
ROOT_DIR = File.expand_path(__dir__)
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

  if (prompt || value.nil?) && $stdin.tty?
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
  sh "helm package '#{ROOT_DIR}/#{HELM_SRC_DIR}'", chdir: HELM_PKG_DIR
end

HELMV2_SRC_DIR = "#{HELMV2_DIR}/#{APP[:name]}"
task :helmv2_build_package => [HELM_PKG_DIR, :generate_helmv2] do
  sh "helm package '#{ROOT_DIR}/#{HELMV2_SRC_DIR}'", chdir: HELM_PKG_DIR
end

task :helm_index => [:helm_build_package, :helmv2_build_package] do
  helm_repo_url = get_var('HELM_REPO_URL')

  maybe_merge=""
  begin
    existing_yaml = URI.parse("https://packages.cloudtruth.com/charts/index.yaml").read
    File.write("#{TMP_DIR}/old-index.yaml", existing_yaml)
    maybe_merge="--merge #{TMP_DIR}/old-index.yaml"
  rescue => e
    puts "No pre-existing helm index at #{helm_repo_url}: #{e}"
  end

  sh "helm repo index #{maybe_merge} --url #{helm_repo_url} #{TMP_DIR}/packaged-chart/"

end

task :helm_package => [:helm_index]

task :build_development => [:client] do
  image_name = get_var(:image_name, default: "#{APP[:name]}", prompt: false, required: false)
  sh "docker build --target development -t #{image_name}:latest -t #{image_name}:development ."
end

task :test => [:build_development] do
  if ENV['CI'] && ENV['CODECOV_TOKEN']
    sh "set -e && ci_env=$(curl -s https://codecov.io/env | bash) && docker run -e CI -e CODECOV_TOKEN ${ci_env} #{APP[:name]} test"
  else
    sh "docker run -e CI -e CODECOV_TOKEN #{APP[:name]} test"
  end
end

task :rspec do
  require "rspec/core/rake_task"
  RSpec::Core::RakeTask.new(:spec)
  Rake::Task[:spec].invoke
end

task :build_release => [:client] do
  image_name = get_var(:image_name, default: "#{APP[:name]}", prompt: false, required: false)
  sh "docker build --target release -t #{image_name}:latest -t #{image_name}:release ."
end

task :docker_push do
  tags = get_var(:tags, default: "latest #{APP[:version]}")
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
      l =~ /^fix(ed)? tests?/i ||
      l =~ /^version bump/i ||
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
  local = get_var(:local, prompt: false, required: false, default: false)
  image_name = get_var(:image_name, default: "#{APP[:name]}", prompt: false, required: false)

  if local
    $LOAD_PATH.unshift File.expand_path("lib", __dir__)
    require "bundler/setup"
    require APP[:name]
    require "pry"
    Pry.start
  else
    Rake::Task["build_development"].invoke
    sh "docker run -it #{image_name}:development console"
  end
end

file "#{CLIENT_DIR}/openapi.yml" do
  mkdir_p "client"
  File.write("#{CLIENT_DIR}/openapi.yml",  URI.parse("https://api.cloudtruth.io/api/schema/").read)
end

file "#{CLIENT_DIR}/Gemfile" => "#{CLIENT_DIR}/openapi.yml" do

  if ENV['MINIKUBE_ACTIVE_DOCKERD']
    puts "Cannot generate the rest client in the minikube docker environment"
    puts "Run in a shell without 'eval $(minikube docker-env)'"
    exit 1
  end

  # may need --user #{Process.uid}:#{Process.gid} for some Hosts
  sh *%W[
    docker run --rm
      -v #{Dir.pwd}:/data
      openapitools/openapi-generator-cli generate
        -i /data/client/openapi.yml
        -g ruby
        -o /data/client
        --library faraday
        --additional-properties=gemName=cloudtruth-client
  ]
end

task :client => "#{CLIENT_DIR}/Gemfile"

task :install do
  build_type = get_var(:build_type, prompt: false, required: false, default: "development")
  namespace = get_var(:namespace, prompt: false, required: false)
  values_file = get_var(:values_file, prompt: false, required: false)
  helm_args = get_var(:helm_args, prompt: false, required: false)

  system("minikube version", [:out, :err] => "/dev/null") || fail("dev dependency not installed - minikube")
  system("minikube status", [:out, :err] => "/dev/null") || fail("dev dependency not running - minikube")

  Rake::Task["client"].invoke

  minikube_env = Hash[`minikube docker-env --shell bash`.scan(/([^ ]*)="(.*)"/)]
  orig_env = ENV.to_hash
  minikube_env.each {|k, v| ENV[k] = v }
  begin
    Rake::Task["build_#{build_type}"].invoke
  ensure
    (minikube_env.keys - orig_env.keys).each {|k| ENV.delete(k) }
    (minikube_env.keys & orig_env.keys).each {|k, v| ENV[k] = orig_env[k] }
  end

  cmd = "helm install"
  cmd << " --create-namespace --namespace #{namespace}" if namespace
  cmd << " --set image.repository=kubetruth --set image.tag=#{build_type} --set image.pullPolicy=Never"
  cmd << " --values #{values_file}" if values_file && File.exist?(values_file)
  cmd << " #{helm_args}"
  cmd << " kubetruth helm/kubetruth/"
  sh cmd
end

task :clean_install do
  namespace = get_var(:namespace, prompt: false, required: false)
  cmd = "helm delete"
  cmd << " --namespace #{namespace}" if namespace
  cmd << " kubetruth"
  sh cmd
  sh "kubectl delete customresourcedefinition projectmappings.kubetruth.cloudtruth.com"
end
