# encoding: utf-8

require 'logstash-core'

require 'logstash/inputs/base'
require 'logstash/filters/base'
require 'logstash/codecs/base'
require 'logstash/outputs/base'

require "logstash/plugin_mixins/port_management_support"

describe LogStash::PluginMixins::PortManagementSupport do
  let(:port_management_support) { LogStash::PluginMixins::PortManagementSupport }

  context 'included into a class' do
    context 'that does not inherit from `LogStash::Plugin`' do
      let(:plugin_class) { Class.new }

      it 'fails with an ArgumentError' do
        expect do
          plugin_class.send(:include, port_management_support)
        end.to raise_error(ArgumentError, /LogStash::Plugin/)
      end
    end

    [
      LogStash::Inputs::Base,
      LogStash::Filters::Base,
      LogStash::Codecs::Base,
      LogStash::Outputs::Base
    ].each do |base_class|
      context "that inherits from `#{base_class}`" do

        let(:plugin_base_class) { base_class }

        subject(:plugin_class) do
          Class.new(plugin_base_class) do
            config_name 'test'
          end
        end

        context 'the result' do
          before(:each) { plugin_class.send(:include, port_management_support) }

          it 'has `port_management` method' do
            expect(plugin_class.method_defined?(:port_management)).to be true
            expect(plugin_class.new({}).port_management).to equal(port_management_support::Manager::INSTANCE)
          end
        end
      end
    end
  end

  ##
  # determine if the port is currently open by attempting to temporarily
  # bind a TCPServer to it
  # @return [Boolean]
  def port_available?(ip, port)
    TCPServer.new(ip, port).close
    return true
  rescue Errno::EADDRINUSE
    return false
  end

  ##
  # yield the block with a port that is available
  # @return [Integer]: a port that is available
  def find_available_port(ip)
    with_bound_port(ip, &:itself)
  end

  ##
  # Yields block with a port that is unavailable
  # @yieldparam port [Integer]
  # @yieldreturn [Object]
  # @return [Object]
  def with_bound_port(ip, &block)
    server = TCPServer.new(ip, 0)

    return yield(server.local_address.ip_port)
  ensure
    server.close
  end

  describe LogStash::PluginMixins::PortManagementSupport::Manager do
    subject(:manager) { described_class::INSTANCE }

    let(:default_ip) { '::' }

    describe '#reserve' do
      context 'port 0' do
        it 'reserves an available port and yields it' do
          reservation = nil
          expect { |b| reservation = manager.reserve(port: 0, &b) }.to yield_with_args(default_ip, a_value > 0)
          expect(reservation.addr).to eq(default_ip)
          expect(reservation.port).to be > 0

          expect(port_available?(reservation.addr, reservation.port)).to be_falsey
        end
      end
      context 'available port' do
        let(:available_port) { find_available_port(default_ip) }

        it 'reserves the port' do
          reservation = nil
          expect { |b| reservation = manager.reserve(port: available_port, &b) }.to yield_with_args(default_ip, available_port)
          expect(reservation.addr).to eq(default_ip)
          expect(reservation.port).to eq(available_port)

          expect(port_available?(reservation.addr, reservation.port)).to be_falsey
        end
      end

      context 'unavailable port' do
        it 'fails to reserve the port' do
          with_bound_port(default_ip) do |unavailable_port|
            expect { manager.reserve(port: unavailable_port) }.to raise_error(Errno::EADDRINUSE)
          end
        end
      end
    end
  end

  describe LogStash::PluginMixins::PortManagementSupport::Reservation do
    let(:reservation) { port_management_support::Manager::INSTANCE.reserve }

    describe '#convert' do
      it 'releases the reservation before yielding the block' do
        expect(port_available?(reservation.addr, reservation.port)).to be_falsey

        expect do |b|
          reservation.convert do |addr, port|
            b.to_proc.call(addr, port)
            expect(port_available?(addr, port)).to be_truthy
          end
        end.to yield_with_args(reservation.addr, reservation.port)
      end

      context 'when already released' do
        before(:each) { reservation.release }

        it 'warns, but does not error' do
          expect(port_available?(reservation.addr, reservation.port)).to be_truthy

          mock_logger = double('Logger').as_null_object
          allow(reservation).to receive(:logger).and_return(mock_logger)

          expect(mock_logger).to receive(:warn).with("converting-inactive[#{reservation.addr}:#{reservation.port}]")

          expect do |b|
            reservation.convert do |addr, port|
              b.to_proc.call(addr, port)
            end
          end.to yield_with_args(reservation.addr, reservation.port)
        end
      end
    end

    describe '#release' do
      it 'releases the reservation' do
        expect(port_available?(reservation.addr, reservation.port)).to be_falsey

        reservation.release

        expect(port_available?(reservation.addr, reservation.port)).to be_truthy
      end
    end
  end
end
