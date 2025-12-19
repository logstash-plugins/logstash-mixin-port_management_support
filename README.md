# Port Management Support Mixin

[![Build Status](https://travis-ci.com/logstash-plugins/logstash-mixin-port_management_support.svg?branch=main)](https://travis-ci.com/logstash-plugins/logstash-mixin-port_management_support)

This gem provides tooling for creating and using port reservations by plugins,
so that a plugin can ensure a port is available during `#register` and _remains_
available until `#run`.

## Usage (simple)

1. Add version `~>1.0` of this gem as a runtime dependency of your Logstash plugin's `gemspec`:

    ~~~ ruby
    Gem::Specification.new do |s|
      # ...

      s.add_runtime_dependency 'logstash-mixin-port_management_support', '~>1.0'
    end
    ~~~

2. In your plugin code, require this library and include it into your plugin class
   that already inherits `LogStash::Plugin`:

    ~~~ ruby
    require 'logstash/plugin_mixins/port_management_support'

    class LogStash::Inputs::Foo < Logstash::Inputs::Base
      include LogStash::PluginMixins::PortManagementSupport

      # ...
    end
    ~~~

3. Use the `port_management` method to get a `PortManagementSupport::Manager` instance, and then use
   that instance to reserve a port:

   ~~~ ruby
   class LogStash::Inputs::Foo < Logstash::Inputs::Base
     # ...

     def register
       @port_reservation = port_management.reserve(port: 1234)
     end
   end
   ~~~


4. Use the `Reservation#convert` method to release the reservation and replace it with your own
   service.

   ~~~ ruby
   class LogStash::Inputs::Foo < Logstash::Inputs::Base
     # ...

     def run(queue)
       # ...
       @port_reservation.convert do |addr, port|
         # this block is yielded *after* unbinding from the port,
         # while still holding the global PortManagementSupport lock.
       end
     end
   end
   ~~~

5. Be sure to hook `Reservation#release` into your plugin's cleanup code

## Development

This gem:
 - *MUST* remain API-stable at 1.x
 - *MUST NOT* introduce additional runtime dependencies
