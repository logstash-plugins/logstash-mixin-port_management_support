# encoding: utf-8

require 'logstash/namespace'
require 'logstash/plugin'

module LogStash
  module PluginMixins
    module PortManagementSupport

      def self.included(base)
        fail(ArgumentError, "`#{base}` must inherit LogStash::Plugin") unless base < LogStash::Plugin

        base.define_method(:port_management) { Manager::INSTANCE }
      end

      class Manager
        INSTANCE=new

        ##
        # Reserve a port on the provided addr, binding a dummy TCP server to the
        # port to ensure that nothing else can bind to it.
        # @param addr [String]: the ip address to bind to (default: "0.0.0.0")
        # @param port [Integer]: the port to bind to (default: 0 "any")
        # @yieldparam addr [String]: the actual ip address that was bound
        # @yieldparam port [Integer]: the actual ip address that was bound
        # @yieldreturn [Void]: the returned value is ignored/discarded
        # @return [Reservation]
        def reserve(addr: '::', port: 0, &handler)
          Reservation.new(addr: addr, port: port, &handler)
        end
      end

      ##
      # A `Reservation` is a TCP server bound to the reserved port on the provided address, preventing
      # anything else in the OS from binding to the same port on that address.
      class Reservation
        PORT_MANAGEMENT_GLOBAL_MUTEX = Monitor.new
        private_constant(:PORT_MANAGEMENT_GLOBAL_MUTEX)

        attr_reader :addr
        attr_reader :port

        include LogStash::Util::Loggable

        ##
        # Creates a port reservation by binding a temporary TCP server
        # @param addr [String]: the address to bind to
        # @param port [Integer]: the port to bind to (note: 0 means "any available")
        # @return [self]
        # @overload initialize(addr:, port:, &handler)
        #   If a handler is provided, the actual addr and port will be yielded to it *outside*
        #   of the global lock
        #   @yieldparam addr [String]: the *actual* address that was bound
        #   @yieldparam port [Integer]: the *actual* port that was bound
        #   @yieldreturn [void]
        def initialize(addr:, port:, &handler)
          PORT_MANAGEMENT_GLOBAL_MUTEX.synchronize do
            @hold = TCPServer.new(addr, port)
            @addr, @port = @hold.local_address.ip_unpack

            logger.debug("RESERVED[#{addr}:#{port}]=>[#{@addr}:#{@port}]")
          end

          ObjectSpace.define_finalizer(self, self.class._server_close_proc(@hold))

          if block_given?
            begin
              yield(@addr, @port)
            rescue => e
              release
              raise
            end
          end
        end

        ##
        # Convert the reservation.
        # In a global lock, the reservation is released and the block is yielded, ensuring that no other plugin
        # using this tooling can make a reservation until the block completes (presumably with your server bound to
        # the port in place of the dummy server that was closed)
        # @yieldparam addr [String]: the reserved-and-released ip address
        # @yieldparam port [Integer]: the reserved-and-released ip port
        # @yieldreturn [Object]: the value emitted by the block is returned by the method
        # @return [Object]: the result of the provided block
        def convert(&block)
          fail(ArgumentError) unless block_given?

          PORT_MANAGEMENT_GLOBAL_MUTEX.synchronize do
            if active?
              logger.trace("converting-active[#{@addr}:#{@port}]")
              release
            else
              logger.warn("converting-inactive[#{@addr}:#{@port}]")
            end

            yield(@addr, @port).tap do
              logger.debug("CONVERTED[#{@addr}:#{@port}]")
            end
          end
        end

        ##
        # Release the reservation *without* replacing it
        def release
          PORT_MANAGEMENT_GLOBAL_MUTEX.synchronize do
            logger.trace("releasing[#{@addr}:#{@port}]")

            fail("hold is nil") if @hold.nil?
            fail("hold is already closed") if @hold.closed?

            @hold.close
            @hold = nil

            logger.trace("RELEASED[#{@addr}:#{@port}]")
          end
        end

        ##
        # Determine if the reservation is still active and eligible for conversion
        # @return [Boolean]: true if-and-only-if the dummy TCP server is still open
        def active?
          PORT_MANAGEMENT_GLOBAL_MUTEX.synchronize do
            @hold && !@hold.closed?
          end
        end

        # returns a proc to close the provided server without holding any other refs
        # https://www.mikeperham.com/2010/02/24/the-trouble-with-ruby-finalizers/
        def self._server_close_proc(server)
          proc do
            unless server.closed?
              logger.trace("ObjectSpace::closing(#{server})")
              server.close
            end
          end
        end
      end
    end
  end
end