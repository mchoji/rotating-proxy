#!/usr/bin/env ruby
require 'erb'
require 'excon'
require 'logger'
require 'uri'

# Add custom URI schemes
module URI
  class SOCKS4 < Generic
    DEFAULT_PORT = 9050
  end
  class SOCKS4A < Generic
    DEFAULT_PORT = 9050
  end
  class SOCKS5 < Generic
    DEFAULT_PORT = 9050
  end
  @@schemes['SOCKS4'] = SOCKS4
  @@schemes['SOCKS4A'] = SOCKS4A
  @@schemes['SOCKS5'] = SOCKS5
end

$logger = Logger.new(STDOUT, ENV['DEBUG'] ? Logger::DEBUG : Logger::INFO)

module Service
  class Base
    attr_reader :port

    def initialize(port)
      @port = port
    end

    def service_name
      self.class.name.downcase.split('::').last
    end

    def start
      ensure_directories
      $logger.info "starting #{service_name} on port #{port}"
    end

    def ensure_directories
      %w{lib run log}.each do |dir|
        path = "/var/#{dir}/#{service_name}"
        Dir.mkdir(path) unless Dir.exists?(path)
      end
    end

    def data_directory
      "/var/lib/#{service_name}"
    end

    def pid_file
      "/var/run/#{service_name}/#{port}.pid"
    end

    def executable
      self.class.which(service_name)
    end

    def stop
      $logger.info "stopping #{service_name} on port #{port}"
      if File.exists?(pid_file)
        pid = File.read(pid_file).strip
        begin
          self.class.kill(pid.to_i)
        rescue => e
          $logger.warn "couldn't kill #{service_name} on port #{port}: #{e.message}"
        end
      else
        $logger.info "#{service_name} on port #{port} was not running"
      end
    end

    def self.kill(pid, signal='SIGINT')
      Process.kill(signal, pid)
    end

    def self.fire_and_forget(*args)
      $logger.debug "running: #{args.join(' ')}"
      pid = Process.fork
      if pid.nil? then
        # In child
        exec args.join(" ")
      else
        # In parent
        Process.detach(pid)
      end
    end

    def self.which(executable)
      path = `which #{executable}`.strip
      if path == ""
        return nil
      else
        return path
      end
    end
  end


  class Tor < Base
    attr_reader :port, :control_port, :host, :scheme

    def initialize(port, control_port)
        @port = port
        @control_port = control_port
        @host = '127.0.0.1'
        @scheme = 'socks5'
    end

    def data_directory
      "#{super}/#{port}"
    end

    def start
      super
      self.class.fire_and_forget(executable,
        "--SocksPort #{port}",
	"--ControlPort #{control_port}",
        "--NewCircuitPeriod 15",
	"--MaxCircuitDirtiness 15",
	"--UseEntryGuards 0",
	"--UseEntryGuardsAsDirGuards 0",
	"--CircuitBuildTimeout 5",
	"--ExitRelay 0",
	"--RefuseUnknownExits 0",
	"--ClientOnly 1",
	"--AllowSingleHopCircuits 1",
        "--DataDirectory #{data_directory}",
        "--PidFile #{pid_file}",
        "--Log \"warn syslog\"",
        '--RunAsDaemon 1',
        "| logger -t 'tor' 2>&1")
    end

    def newnym
        self.class.fire_and_forget('/usr/local/bin/newnym.sh',
				   "#{control_port}",
				   "| logger -t 'newnym'")
    end
  end

  class Polipo < Base
    def initialize(port, upstream:)
      super(port)
      @upstream = upstream
    end

    def start
      super
      # https://gitweb.torproject.org/torbrowser.git/blob_plain/1ffcd9dafb9dd76c3a29dd686e05a71a95599fb5:/build-scripts/config/polipo.conf
      if File.exists?(pid_file)
        File.delete(pid_file)
      end

      if ["socks4", "socks4a", "socks5"].include?(upstream_scheme)
        self.class.fire_and_forget(executable,
          "proxyPort=#{port}",
          "socksParentProxy=#{upstream_host}:#{upstream_port}",
          "socksProxyType=#{upstream_scheme}",
          "diskCacheRoot=''",
          "disableLocalInterface=true",
          "allowedClients=127.0.0.1",
          "localDocumentRoot=''",
          "disableConfiguration=true",
          "dnsUseGethostbyname='yes'",
          "logSyslog=true",
          "daemonise=true",
          "pidFile=#{pid_file}",
          "disableVia=true",
          "allowedPorts='1-65535'",
          "tunnelAllowedPorts='1-65535'",
          "| logger -t 'polipo' 2>&1")
      elsif upstream_scheme == "http"
        self.class.fire_and_forget(executable,
          "proxyPort=#{port}",
          "parentProxy=#{upstream_host}:#{upstream_port}",
          "diskCacheRoot=''",
          "disableLocalInterface=true",
          "allowedClients=127.0.0.1",
          "localDocumentRoot=''",
          "disableConfiguration=true",
          "dnsUseGethostbyname='yes'",
          "logSyslog=true",
          "daemonise=true",
          "pidFile=#{pid_file}",
          "disableVia=true",
          "allowedPorts='1-65535'",
          "tunnelAllowedPorts='1-65535'",
          "| logger -t 'polipo' 2>&1")
      end
    end

    def upstream_port
      @upstream.port
    end

    def upstream_scheme
      @upstream.scheme == "socks4"? "socks4a" : @upstream.scheme
    end

    def upstream_host
      @upstream.host
    end

  end


  class Proxy
    attr_reader :id
    attr_reader :polipo

    def initialize(id)
      @id = id
      Excon.defaults[:ssl_verify_peer] = ssl_verify
    end

    def polipo_port
      20000 + id
    end
    alias_method :port, :polipo_port

    def test_url
      ENV['test_url'] || 'http://icanhazip.com'
    end

    def ssl_verify
      ENV['ssl_verify'] || true
    end

    def working?
      Excon.get(test_url, proxy: "http://127.0.0.1:#{port}", :read_timeout => 20).status == 200
    rescue
      false
    end
  end


  class TorProxy < Proxy
    attr_reader :tor

    def initialize(id)
      super
      @tor = Tor.new(tor_port, tor_control_port)
      @polipo = Polipo.new(polipo_port, upstream: tor)
    end

    def start
      $logger.info "starting proxy id #{id}"
      @tor.start
      @polipo.start
    end

    def stop
      $logger.info "stopping proxy id #{id}"
      @tor.stop
      @polipo.stop
    end

    def restart
      stop
      sleep 5
      start
    end

    def tor_port
      10000 + id
    end

    def tor_control_port
      30000 + id
    end
  end


  class PubProxy < Proxy
    attr_reader :proxy
    def initialize(id, uri_str)
      super(id)
      @proxy = URI.parse(uri_str)
      @polipo = Polipo.new(polipo_port, upstream: proxy)
    end

    def start
      $logger.info "starting proxy id #{id}"
      @polipo.start
    end

    def stop
      $logger.info "stopping proxy id #{id}"
      @polipo.stop
    end

    def restart
      stop
      sleep 5
      start
    end
  end

  class Haproxy < Base
    attr_reader :backends

    def initialize(port = 5566)
      @config_erb_path = "/usr/local/etc/haproxy.cfg.erb"
      @config_path = "/usr/local/etc/haproxy.cfg"
      @backends = []
      super(port)
    end

    def start
      super
      compile_config
      self.class.fire_and_forget(executable,
        "-f #{@config_path}",
        "| logger 2>&1")
    end

    def soft_reload
      self.class.fire_and_forget(executable,
        "-f #{@config_path}",
        "-p #{pid_file}",
        "-sf #{File.read(pid_file)}",
        "| logger 2>&1")
    end

    def add_backend(backend)
      @backends << {:name => 'proxy', :addr => '127.0.0.1', :port => backend.port}
    end

    private
    def compile_config
      File.write(@config_path, ERB.new(File.read(@config_erb_path)).result(binding))
    end
  end
end

# validate configuration
abort "Invalid mode #{ENV['mode']}" unless ["tor", "list"].include?(ENV['mode'])
abort "Pool size should be greater than 0!" unless ENV['pool_size'].to_i > 0
ha_template = '/usr/local/etc/haproxy.cfg.erb'
abort "Missing template config file at #{ha_template}" unless File.exists?(ha_template)
proxy_list = '/usr/local/etc/proxy.lst'
if ENV['mode'] == 'list'
  abort "Mode is set to 'list' but #{proxy_list} was not found!" unless File.exists?(proxy_list)
end


haproxy = Service::Haproxy.new
proxies = []

if ENV['mode'] == 'tor'
  tor_instances = ENV['pool_size'] || 10
  tor_instances.to_i.times.each do |id|
    proxy = Service::TorProxy.new(id)
    haproxy.add_backend(proxy)
    proxy.start
    proxies << proxy
  end
else
  file = File.open(proxy_list)
  file_data = file.readlines.map(&:chomp)
  if ENV['pool_size'].to_i > file_data.length()
    $logger.warn "Supplied pool_size is greater than supplied proxy list. pool_size will be adjusted to #{file_data.length()}"
  end
  proxy_instances = [ENV['pool_size'].to_i, file_data.length()].min
  proxy_instances.times.each do |id|
    proxy = Service::PubProxy.new(id, file_data[id])
    haproxy.add_backend(proxy)
    proxy.start
    proxies << proxy
  end
end

haproxy.start

sleep 90

loop do
  if ENV['mode'] == 'tor'
    $logger.info "resetting circuits"
    proxies.each do |proxy|
      $logger.info "reset nym for #{proxy.id} (port #{proxy.port})"
      proxy.tor.newnym
    end
  end

  $logger.info "testing proxies"
  proxies.each do |proxy|
    $logger.info "testing proxy #{proxy.id} (port #{proxy.port})"
    proxy.restart unless proxy.working?
  end

  $logger.info "sleeping for 90 seconds"
  sleep 90
end
