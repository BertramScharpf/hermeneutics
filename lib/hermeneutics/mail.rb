#
#  hermeneutics/mail.rb  --  A mail
#

require "hermeneutics/message"
require "hermeneutics/boxes"


module Hermeneutics

  class Mail < Message

    class <<self

      private :new

      def parse input, from = nil, created = nil
        parse_hb input do |h,b|
          new h, b, from, created
        end
      end

      def create
        new nil, nil, nil, nil
      end

    end

    def initialize headers, body, from, created
      super headers, body
      @from, @created = from, created
    end

    def from
      @from ||= find_from
    end

    def created
      @created ||= Time.now
    end

    def senders
      addresses_of :from, :sender, :return_path
    end

    def receivers
      addresses_of :to, :cc, :bcc
    end

    private

    def find_from
      addresses_of :from, :sender, :return_path do |e|
        return e.plain
      end
      require "etc"
      require "socket"
      "#{Etc.getlogin}@#{Socket.gethostname}"
    end

    def addresses_of *args
      if block_given? then
        l = args.map { |f| @headers.field f }
        a = AddrList.new *l
        a.each { |e| yield e }
      else
        r = []
        addresses_of *args do |e| r.push e end
        r
      end
    end



    @spooldir = "/var/mail"
    @maildir  = "Mail"
    @sendmail = "/usr/sbin/sendmail"
    @sysdir   = ".hermeneutics"

    LEVEL = %i(
      NON
      ERR
      INF
      DBG
    ).inject Hash.new do |h,k| h[k] = h.length ; h end

    class <<self

      attr_accessor :spooldir, :maildir, :sendmail, :sysdir
      attr_accessor :spoolfile, :default_format
      attr_accessor :logfile, :loglevel

      def box path = nil, default_format = nil
        @cache ||= {}
        @cache[ path] ||= find_box path, default_format
      end

      private

      def find_box path, default_format
        b = case path
          when Box then
            path
          when nil then
            @spoolfile ||= getuser
            m = File.expand_path @spoolfile, @spooldir
            MBox.new m
          else
            m = if path =~ /\A=/ then
              File.join expand_maildir, $'
            else
              File.expand_path path, "~"
            end
            Box.find m, default_format||@default_format
        end
        b.exists? or b.create
        b
      end

      public

      def log type, *message
        @logfile or return
        return if LEVEL[ type] > LEVEL[ @loglevel].to_i
        l = File.expand_path @logfile, expand_sysdir
        File.open l, "a" do |log|
          log.puts "[#{Time.new}] [#$$] [#{type}] #{message.join ' '}"
        end
        nil
      rescue Errno::ENOENT
        d = File.dirname l
        Dir.mkdir! d and retry
      end

      def expand_maildir
        File.expand_path @maildir, "~"
      end

      def expand_sysdir
        File.expand_path @sysdir, expand_maildir
      end

      private

      def getuser
        e = Etc.getpwuid Process.uid
        e.name
      rescue NameError
        require "etc" and retry
      end

    end

    # :call-seq:
    #   obj.save( path, default_format = nil)           -> mb
    #
    # Save into local mailbox.
    #
    def save mailbox = nil, default_format = nil
      b = cls.box mailbox, default_format
      log :INF, "Delivering to", b.path
      b.deliver self
    end

    # :call-seq:
    #   obj.pipe( cmd, *args)           -> status
    #
    # Pipe into an external program.  If a block is given, the programs
    # output will be yielded there.
    #
    def pipe cmd, *args
      log :INF, "Piping through:", cmd, *args
      ri, wi = IO.pipe
      ro, wo = IO.pipe
      child = fork do
        wi.close ; ro.close
        $stdout.reopen wo ; wo.close
        $stdin .reopen ri ; ri.close
        exec cmd, *args
      end
      ri.close ; wo.close
      t = Thread.new wi do |wi|
        begin
          wi.write to_s
        ensure
          wi.close
        end
      end
      begin
        r = ro.read
        yield r if block_given?
      ensure
        ro.close
      end
      t.join
      Process.wait child
      $?.success? or
        log :ERR, "Pipe failed with error code %d." % $?.exitstatus
      $?
    end

    # :call-seq:
    #   obj.sendmail( *tos)                -> status
    #
    # Send by sendmail; leave the +tos+ list empty to
    # use Sendmail's -t option.
    #
    def sendmail *tos
      if tos.empty? then
        pipe cls.sendmail, "-t"
      else
        tos.flatten!
        tos.map! { |t|
          case t
            when Addr then t.plain
            else           t.delete %q-,;"'<>(){}[]$&*?-   # security
          end
        }
        pipe cls.sendmail, *tos
      end
    end

    # :call-seq:
    #   obj.send!( smtp, *tos)                -> response
    #
    # Send by SMTP.
    #
    # Be aware that <code>#send</code> without bang is a
    # standard Ruby method.
    #
    def send! conn = nil, *tos
      if tos.empty? then
        tos = receivers.map { |t| t.plain }
      else
        tos.flatten!
      end
      f, m = true, ""
      to_s.each_line { |l|
        if f then
          f = false
          next if l =~ /^From /
        end
        m << l
      }
      open_smtp conn do |smtp|
        log :INF, "Sending to", *tos
        frs = headers.from.map { |f| f.plain }
        smtp.send_message m, frs.first, tos
      end
    rescue NoMethodError
      raise "Missing field: #{$!.name}."
    end

    private

    def net_smpt
      Net::SMTP
    rescue NameError
      require "net/smtp" and retry
    end

    def open_smtp arg, &block
      case arg
        when String then h, p = arg.split ":"
        when Array  then h, p = *arg
        when nil    then h, p = "localhost", nil
        else
          if arg.respond_to? :send_message then
            yield arg
            return
          else
            h, p = arg.host, arg.port
          end
      end
      net_smpt.start h, p, &block
    end

    def log level, *msg
      cls.log level, *msg
    end

  end

end

