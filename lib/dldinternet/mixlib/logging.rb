unless defined? ::DLDInternet::Mixlib::Logging::ClassMethods

  require 'dldinternet/mixlib/logging/version'

  module DLDInternet
    module Mixlib
      module Logging

        require "rubygems"
        require 'rubygems/gem_runner'
        require 'rubygems/exceptions'
        require 'logging'

        module ::Logging
          class << self

            # call-seq:
            #    Logging.logger( device, age = 7, size = 1048576 )
            #    Logging.logger( device, age = 'weekly' )
            #
            # This convenience method returns a Logger instance configured to behave
            # similarly to a core Ruby Logger instance.
            #
            # The _device_ is the logging destination. This can be a filename
            # (String) or an IO object (STDERR, STDOUT, an open File, etc.). The
            # _age_ is the number of old log files to keep or the frequency of
            # rotation (+daily+, +weekly+, or +monthly+). The _size_ is the maximum
            # logfile size and is only used when _age_ is a number.
            #
            # Using the same _device_ twice will result in the same Logger instance
            # being returned. For example, if a Logger is created using STDOUT then
            # the same Logger instance will be returned the next time STDOUT is
            # used. A new Logger instance can be obtained by closing the previous
            # logger instance.
            #
            #    log1 = Logging.logger(STDOUT)
            #    log2 = Logging.logger(STDOUT)
            #    log1.object_id == log2.object_id  #=> true
            #
            #    log1.close
            #    log2 = Logging.logger(STDOUT)
            #    log1.object_id == log2.object_id  #=> false
            #
            # The format of the log messages can be changed using a few optional
            # parameters. The <tt>:pattern</tt> can be used to change the log
            # message format. The <tt>:date_pattern</tt> can be used to change how
            # timestamps are formatted.
            #
            #    log = Logging.logger(STDOUT,
            #              :pattern => "[%d] %-5l : %m\n",
            #              :date_pattern => "%Y-%m-%d %H:%M:%S.%s")
            #
            # See the documentation for the Logging::Layouts::Pattern class for a
            # full description of the :pattern and :date_pattern formatting strings.
            #
            def logger( *args )
              return ::Logging::Logger if args.empty?

              opts = args.pop if args.last.instance_of?(Hash)
              opts ||= Hash.new

              dev = args.shift
              keep = age = args.shift
              size = args.shift

              name = case dev
                       when String; dev
                       when File; dev.path
                       else dev.object_id.to_s end

              repo = ::Logging::Repository.instance
              return repo[name] if repo.has_logger? name

              l_opts = {
                  :pattern => "%.1l, [%d #%p] %#{::Logging::MAX_LEVEL_LENGTH}l : %m\n",
                  :date_pattern => '%Y-%m-%dT%H:%M:%S.%s'
              }
              [:pattern, :date_pattern, :date_method].each do |o|
                l_opts[o] = opts.delete(o) if opts.has_key? o
              end
              layout = ::Logging::Layouts::Pattern.new(l_opts)

              a_opts = Hash.new
              a_opts[:size] = size if size.instance_of?(Fixnum)
              a_opts[:age]  = age  if age.instance_of?(String)
              a_opts[:keep] = keep if keep.instance_of?(Fixnum)
              a_opts[:filename] = dev if dev.instance_of?(String)
              a_opts[:layout] = layout
              a_opts.merge! opts

              appender =
                  case dev
                    when String
                      ::Logging::Appenders::RollingFile.new(name, a_opts)
                    else
                      ::Logging::Appenders::IO.new(name, dev, a_opts)
                  end

              logger = ::Logging::Logger.new(name, opts)
              logger.add_appenders appender
              logger.additive = false

              class << logger
                def close
                  @appenders.each {|a| a.close}
                  h = ::Logging::Repository.instance.instance_variable_get :@h
                  h.delete(@name)
                  class << self; undef :close; end
                end
              end

              logger
            end

          end

        end

        class ::Logging::ColorScheme
          def scheme(s=nil)
            @scheme = s if s
            @scheme
          end
        end

        class ::Logging::Logger
          class << self
            def define_log_methods( logger )
              ::Logging::LEVELS.each do |name,num|
                code =  "undef :#{name}  if method_defined? :#{name}\n"
                code << "undef :#{name}? if method_defined? :#{name}?\n"

                unless logger.level.is_a?(Fixnum)
                  puts "logger.level for #{logger.name} is a #{logger.level.class} instead of a Fixnum!!!"
                  exit -1
                end
                if logger.level > num
                  code << <<-CODE
                  def #{name}?( ) false end
                  def #{name}( data = nil, trace = false ) false end
                  CODE
                else
                  code << <<-CODE
                  def #{name}?( ) true end
                  def #{name}( data = nil, trace = nil )
                    caller = Kernel.caller[3]
                    num = #{num}
                    level =  #{logger.level}
                    if num >= level
                      data = yield if block_given?
                      #log_event(::Logging::LogEvent.new(@name, num, caller, true))
                      log_event(::Logging::LogEvent.new(@name, num, data, trace.nil? ? @trace : trace))
                    end
                    true
                  end
                  CODE
                end

                logger._meta_eval(code, __FILE__, __LINE__)
              end
              logger
            end

            # Overrides the new method such that only one Logger will be created
            # for any given logger name.
            #
            def new( *args )
              return super if args.empty?

              repo = ::Logging::Repository.instance
              name = repo.to_key(args.shift)
              opts = args.last.instance_of?(Hash) ? args.pop : {}

              @mutex.synchronize do
                logger = repo[name]
                if logger.nil?

                  master = repo.master_for(name)
                  if master
                    if repo.has_logger?(master)
                      logger = repo[master]
                    else
                      logger = super(master)
                      repo[master] = logger
                      repo.children(master).each {|c| c.__send__(:parent=, logger)}
                    end
                    repo[name] = logger
                  else
                    logger = super(name, opts)
                    repo[name] = logger
                    repo.children(name).each {|c| c.__send__(:parent=, logger)}
                  end
                end
                logger
              end
            end

          end

          # call-seq:
          #    Logger.new( name )
          #    Logger[name]
          #
          # Returns the logger identified by _name_.
          #
          # When _name_ is a +String+ or a +Symbol+ it will be used "as is" to
          # retrieve the logger. When _name_ is a +Class+ the class name will be
          # used to retrieve the logger. When _name_ is an object the name of the
          # object's class will be used to retrieve the logger.
          #
          # Example:
          #
          #   obj = MyClass.new
          #
          #   log1 = Logger.new(obj)
          #   log2 = Logger.new(MyClass)
          #   log3 = Logger['MyClass']
          #
          #   log1.object_id == log2.object_id         # => true
          #   log2.object_id == log3.object_id         # => true
          #
          def initialize( name, *args )
            case name
              when String
                raise(ArgumentError, "logger must have a name") if name.empty?
              else raise(ArgumentError, "logger name must be a String") end

            repo = ::Logging::Repository.instance
            opts = args.last.instance_of?(Hash) ? args.pop : {}
            _setup(name, opts.merge({:parent => repo.parent(name)}))
          end


          def logEvent(evt)
            log_event evt
          end

          def get_trace
            @trace
          end
        end

        class ::Logging::Layouts::Pattern
          # Arguments to sprintf keyed to directive letters
          verbose, $VERBOSE = $VERBOSE, nil
          # noinspection RubyStringKeysInHashInspection,RubyExpressionInStringInspection
          DIRECTIVE_TABLE = {
              'C' => 'event.file != "" ? "(\e[38;5;25m#{event.file}::#{event.line}\e[0m)" : ""',
              'c' => 'event.logger'.freeze,
              'd' => 'format_date(event.time)'.freeze,
              'F' => 'event.file'.freeze,
              'f' => 'File.basename(event.file)'.freeze,
              'g' => 'event.file != "" ? "(\e[38;5;25m#{File.join(File.dirname(event.file).split(File::SEPARATOR)[-2..-1],File.basename(event.file))}::#{event.line}\e[0m)" : ""',
              'l' => '::Logging::LNAMES[event.level]'.freeze,
              'L' => 'event.line'.freeze,
              'M' => 'event.method'.freeze,
              'm' => 'format_obj(event.data)'.freeze,
              'p' => 'Process.pid'.freeze,
              'r' => 'Integer((event.time-@created_at)*1000).to_s'.freeze,
              't' => 'Thread.current.object_id.to_s'.freeze,
              'T' => 'Thread.current[:name]'.freeze,
              '%' => :placeholder
          }.freeze

          # Human name aliases for directives - used for colorization of tokens
          # noinspection RubyStringKeysInHashInspection
          COLOR_ALIAS_TABLE = {
              'C' => :file_line,
              'c' => :logger,
              'd' => :date,
              'F' => :file,
              'f' => :file,
              'g' => :file,
              'L' => :line,
              'l' => :logger,
              'M' => :method,
              'm' => :message,
              'p' => :pid,
              'r' => :time,
              'T' => :thread,
              't' => :thread_id,
              'X' => :mdc,
              'x' => :ndc,
          }.freeze

        ensure
          $VERBOSE = verbose
        end

        class FakeLogger
          def method_missing(m, *args, &block)
            puts args[0]
          end
        end

        module ClassMethods

        end

        attr        :logger
        attr_reader :logger_args
        attr_reader :step
        attr_reader :TODO

        # --------------------------------------------------------------------------------
        def logTodo(msg)

          # Regular expression used to parse out caller information
          #
          # * $1 == filename
          # * $2 == line number
          # * $3 == method name (might be nil)
          caller_rgxp = %r/([-\.\/\(\)\w]+):(\d+)(?::in `(\w+)')?/o
          #CALLER_INDEX = 2
          caller_index = ((defined? JRUBY_VERSION and JRUBY_VERSION[%r/^1.6/]) or (defined? RUBY_ENGINE and RUBY_ENGINE[%r/^rbx/i])) ? 0 : 0
          stack = Kernel.caller
          return if stack.nil?

          match = caller_rgxp.match(stack[caller_index])
          file = match[1]
          line = Integer(match[2])
          modl = match[3] unless match[3].nil?

          # Unless we've already logged this TODO ...
          unless @TODO["#{file}::#{line}"]
            le = ::Logging::LogEvent.new(@logger, ::Logging::LEVELS['todo'], msg, false)
            @logger.logEvent(le)
            @TODO["#{file}::#{line}"] = msg
          end
        end

        module ::Logging

          # This class defines a logging event.
          #
          remove_const :LogEvent if defined? :LogEvent
          LogEvent = Struct.new( :logger, :level, :data, :time, :file, :line, :method ) {
            # :stopdoc:
            class << self
              attr_accessor :caller_index
            end

            # Regular expression used to parse out caller information
            #
            # * $1 == filename
            # * $2 == line number
            # * $3 == method name (might be nil)
            # CALLER_RGXP = %r/([-\.\/\(\)\w]+):(\d+)(?::in `(\w+)')?/o
            # CALLER_INDEX = ((defined? JRUBY_VERSION and JRUBY_VERSION > '1.6') or (defined? RUBY_ENGINE and RUBY_ENGINE[%r/^rbx/i])) ? 1 : 2
            # :startdoc:

            # call-seq:
            #    LogEvent.new( logger, level, [data], trace )
            #
            # Creates a new log event with the given _logger_ name, numeric _level_,
            # array of _data_ from the user to be logged, and boolean _trace_ flag.
            # If the _trace_ flag is set to +true+ then Kernel::caller will be
            # invoked to get the execution trace of the logging method.
            #
            def initialize( logger, level, data, trace )
              f = l = m = ''

              if trace
                stack = Kernel.caller[::Logging::LogEvent.caller_index]
                return if stack.nil?

                match = CALLER_RGXP.match(stack)
                f = match[1]
                l = Integer(match[2])
                m = match[3] unless match[3].nil?
              end

              super(logger, level, data, Time.now, f, l, m)
            end
          }
          ::Logging::LogEvent.caller_index = CALLER_INDEX
        end  # module Logging

        # -----------------------------------------------------------------------------
        def logStep(msg,cat='Step')
          logger = getLogger(@logger_args, 'logStep')
          if logger
            if logger.get_trace
              ::Logging::LogEvent.caller_index += 1
            end
            logger.step "#{cat} #{@step+=1}: #{msg} ..."
            if logger.get_trace
              ::Logging::LogEvent.caller_index -= 1
            end
          end
        end

        # -----------------------------------------------------------------------------
        # Set up logger

        def setLogger(logger)
          @logger = logger
        end

        def getLogger(args,from='',alogger=nil)
          logger = alogger || @logger
          unless logger
            unless from==''
              from = "#{from} - "
            end
            @step = 0
            if args
              if args.key?(:log_file) and args[:log_file]
                args[:log_path] = File.dirname(args[:log_file])
              elsif args[:my_name]
                if args[:log_path]
                  args[:log_file] = "#{args[:log_path]}/#{args[:my_name]}.log"
                else
                  args[:log_file] = "/tmp/#{args[:my_name]}.log"
                end
              end

              begin
                ::Logging.init :trace, :debug, :info, :step, :warn, :error, :fatal, :todo unless defined? ::Logging::MAX_LEVEL_LENGTH
                if args[:origins] and args[:origins][:log_level]
                  if ::Logging::LEVELS[args[:log_level].to_s] and ::Logging::LEVELS[args[:log_level].to_s] < 2
                    puts "#{args[:origins][:log_level]} says #{args[:log_level]}".light_yellow
                  else
                    from = ''
                  end
                end
                l_opts = args[:log_opts].call(::Logging::MAX_LEVEL_LENGTH) || {
                    :pattern      => "#{from}%d %#{::Logging::MAX_LEVEL_LENGTH}l: %m\n",
                    :date_pattern => '%Y-%m-%d %H:%M:%S',
                }
                logger = ::Logging.logger( STDOUT, l_opts)
                l_opts = args[:log_opts].call(::Logging::MAX_LEVEL_LENGTH) || {
                    :pattern      => "#{from}%d %#{::Logging::MAX_LEVEL_LENGTH}l: %m %C\n",
                    :date_pattern => '%Y-%m-%d %H:%M:%S',
                }
                layout = ::Logging::Layouts::Pattern.new(l_opts)

                if args[:log_file] and args[:log_file].instance_of?(String)
                  dev = args[:log_file]
                  a_opts = Hash.new
                  a_opts[:filename] = dev
                  a_opts[:layout] = layout
                  a_opts.merge! l_opts

                  name = case dev
                           when String; dev
                           when File; dev.path
                           else dev.object_id.to_s end

                  appender =
                      case dev
                        when String
                          ::Logging::Appenders::RollingFile.new(name, a_opts)
                        else
                          ::Logging::Appenders::IO.new(name, dev, a_opts)
                      end
                  logger.add_appenders appender
                end

                # Create the default scheme if none given ...
                unless l_opts.has_key? :color_scheme
                  lcs = ::Logging::ColorScheme.new( 'dldinternet', :levels => {
                      :trace => :blue,
                      :debug => :cyan,
                      :info  => :green,
                      :step  => :green,
                      :warn  => :yellow,
                      :error => :red,
                      :fatal => :red,
                      :todo  => :purple,
                  })
                  scheme = lcs.scheme
                  scheme['trace'] = "\e[38;5;89m"
                  scheme['fatal'] = "\e[38;5;33m"
                  scheme['todo']  = "\e[38;5;55m"
                  lcs.scheme scheme
                  l_opts[:color_scheme] = 'dldinternet'
                end
                layout = ::Logging::Layouts::Pattern.new(l_opts)

                appender = logger.appenders[0]
                appender.layout = layout
                logger.remove_appenders appender
                logger.add_appenders appender

                logger.level = args[:log_level] ? args[:log_level] : :warn
                logger.trace = true if args[:trace]
                @logger_args = args
              rescue Gem::LoadError
                logger = FakeLogger.new
              rescue Exception => e
                puts e
                # not installed
                logger = FakeLogger.new
              end
              @TODO = {} if @TODO.nil?
            end # if args
            @logger = alogger || logger
          end # unless logger
          logger
        end # getLogger

        def included(includer)
          includer.extend(ClassMethods)
        end
      end
    end
  end

end # unless defined?
