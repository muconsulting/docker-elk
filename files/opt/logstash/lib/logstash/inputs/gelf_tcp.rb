# encoding: utf-8
require "date"
require "logstash/inputs/base"
require "logstash/namespace"
require "logstash/util/socket_peer"
require "socket"

# This input will read GELF messages as events over the network via TCP,
# making it a good choice if you already use Graylog2 today.
#
# The main use case for this input is to leverage existing GELF
# logging libraries supporting TCP.
#
class LogStash::Inputs::GelfTcp < LogStash::Inputs::Base
  class Interrupted < StandardError; end
  config_name "gelf_tcp"
  milestone 2

  # The IP address or hostname to listen on.
  config :host, :validate => :string, :default => "0.0.0.0"

  # The port to listen on. Remember that ports less than 1024 (privileged
  # ports) may require root to use.
  config :port, :validate => :number, :default => 12201

  # Whether or not to remap the GELF message fields to Logstash event fields or
  # leave them intact.
  #
  # Remapping converts the following GELF fields to Logstash equivalents:
  #
  # * `full\_message` becomes event["message"].
  # * if there is no `full\_message`, `short\_message` becomes event["message"].
  config :remap, :validate => :boolean, :default => true

  # Whether or not to remove the leading '\_' in GELF fields or leave them
  # in place. (Logstash < 1.2 did not remove them by default.). Note that
  # GELF version 1.1 format now requires all non-standard fields to be added
  # as an "additional" field, beginning with an underscore.
  #
  # e.g. `\_foo` becomes `foo`
  #
  config :strip_leading_underscore, :validate => :boolean, :default => true

  public
  def initialize(params)
    super
    BasicSocket.do_not_reverse_lookup = true
  end # def initialize

  public
  def register
    require 'gelfd'

    @logger.info("Starting tcp input listener", :address => "#{@host}:#{@port}")
    begin
      @server_socket = TCPServer.new(@host, @port)
    rescue Errno::EADDRINUSE
      @logger.error("Could not start TCP server: Address in use",
                    :host => @host, :port => @port)
      raise
    end
  end # def register

  public
  def run(output_queue)
    begin
      # tcp server
      run_server(output_queue)
    rescue => e
      @logger.warn("gelf listener died", :exception => e, :backtrace => e.backtrace)
      sleep(5)
      retry
    end # begin
  end # def run

  def run_server(output_queue)
    @thread = Thread.current
    @client_threads = []
    loop do
      # Start a new thread for each connection.
      begin
        @client_threads << Thread.start(@server_socket.accept) do |s|
          # monkeypatch a 'peer' method onto the socket.
          s.instance_eval { class << self; include ::LogStash::Util::SocketPeer end }
          @logger.debug("Accepted connection", :client => s.peer,
                        :server => "#{@host}:#{@port}")
          begin
            handle_socket(s, output_queue)
          rescue Interrupted
            s.close rescue nil
          end
        end # Thread.start
      rescue IOError, LogStash::ShutdownSignal
        if @interrupted
          # Intended shutdown, get out of the loop
          @server_socket.close
          @client_threads.each do |thread|
            thread.raise(LogStash::ShutdownSignal)
          end
          break
        else
          # Else it was a genuine IOError caused by something else, so propagate it up..
          raise
        end
      end
    end # loop
  rescue LogStash::ShutdownSignal
    # nothing to do
  ensure
    @server_socket.close rescue nil
  end # def run_server

  private
  def handle_socket(socket, output_queue)
    while true
      json_event = socket.readline(sep="\x00").chomp("\x00")
      @logger.debug("Got Gelf JSON event", :json => json_event)
      begin
        event = LogStash::Event.new(JSON.parse(json_event))
        event["source_host"] = socket.peeraddr[3]
        if event["timestamp"].is_a?(Numeric)
          event["@timestamp"] = Time.at(event["timestamp"]).gmtime
          event.remove("timestamp")
        end
        remap_gelf(event) if @remap
        strip_leading_underscore(event) if @strip_leading_underscore
        decorate(event)
        output_queue << event
      rescue => ex
        @logger.warn("Could not parse Gelf JSON message, skipping", :exception => ex, :backtrace => ex.backtrace)
        next
      end
    end
  rescue EOFError
    @logger.debug("Connection closed", :client => socket.peer)
  rescue => e
    @logger.debug("An error occurred. Closing connection",
                  :client => socket.peer, :exception => e, :backtrace => e.backtrace)
  ensure
    socket.close rescue IOError nil
  end

  private
  def remap_gelf(event)
    if event["full_message"]
      event["message"] = event["full_message"].dup
      event.remove("full_message")
      if event["short_message"] == event["message"]
        event.remove("short_message")
      end
    elsif event["short_message"]
      event["message"] = event["short_message"].dup
      event.remove("short_message")
    end
  end # def remap_gelf

  private
  def strip_leading_underscore(event)
    # Map all '_foo' fields to simply 'foo'
    event.to_hash.keys.each do |key|
      next unless key[0,1] == "_"
      event[key[1..-1]] = event[key]
      event.remove(key)
    end
  end # deef removing_leading_underscores

  public
  def teardown
    if server?
      @interrupted = true
    end
  end # def teardown
end # class LogStash::Inputs::Gelf
