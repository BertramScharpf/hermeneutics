#
#  hermeneutics/boxes.rb  --  Mailboxes
#

=begin rdoc

:section: Classes definied here

Hermeneutics::Box is a general Mailbox.

Hermeneutics::MBox is the traditional mbox format (text file, separated by a
blank line).

Hermeneutics::Maildir is the maildir format.


=end


require "supplement"
require "date"


module Hermeneutics

  # Mailboxes
  class Box

    @boxes = []

    class <<self

      attr_accessor :default_format

      # :call-seq:
      #   Box.find( path, default = nil)          -> box
      #
      # Create a Box object (some subclass of Box), depending on
      # what type the box is found at <code>path</code>.
      #
      def find path, default_format = nil
        b = @boxes.find { |b| b.check path }
        b ||= default_format
        b ||= @default_format
        b ||= if File.directory? path then
          Maildir
        elsif File.file? path then
          MBox
        else
          # If still nothing was found use Postfix convention:
          path =~ /\/$/ ? Maildir : MBox
        end
        b.new path
      end

      # :call-seq:
      #   Box.check( path)     -> nil
      #
      # By default, subclass mailboxes do not exist. You should overwrite
      # this behaviour.
      #
      def check path
      end

      protected
      attr_reader :boxes
      def inherited cls
        Box.boxes.push cls
      end

    end

    # :call-seq:
    #   Box.new( path)          -> box
    #
    # Instantiate a Box object, just store the <code>path</code>.
    #
    def initialize mailbox
      @mailbox = mailbox
    end

    def to_s ; path ; end

    def path ; @mailbox ; end

    # :call-seq:
    #   box.exists?     -> true or false
    #
    # Test whether the <code>Box</code> exists.
    #
    def exists?
      self.class.check @mailbox
    end

    # :call-seq:
    #   mbox.store( msg)     -> nil
    #
    # Store the mail to the local <code>MBox</code>.
    #
    def store msg
      store_raw msg.to_s, msg.plain_from, msg.created
    end

    # :call-seq:
    #   mbox.each { |mail| ... }    -> nil
    #
    # Iterate through <code>MBox</code>.
    # Alias for <code>MBox#each_mail</code>.
    #
    def each &block ; each_mail &block ; end
    include Enumerable

    private

    def local_from
      require "etc"
      require "socket"
      s = File.stat @mailbox
      lfrom = "#{(Etc.getpwuid s.uid).name}@#{Socket.gethostname}"
    end

  end

  class MBox < Box

    RE_F = /^From\s+/      # :nodoc:
    RE_N = /^$/            # :nodoc:

    class <<self

      # :call-seq:
      #   MBox.check( path)     -> true or false
      #
      # Check whether path is a <code>MBox</code>.
      #
      def check path
        if File.file? path then
          File.open path, encoding: Encoding::ASCII_8BIT do |f|
            f.size.zero? or f.readline =~ RE_F
          end
        end
      end

    end

    # :call-seq:
    #   mbox.create     -> self
    #
    # Create the <code>MBox</code>.
    #
    def create
      d = File.dirname @mailbox
      Dir.mkdir! d
      File.open @mailbox, File::CREAT do |f| end
      self
    end

    # :call-seq:
    #   mbox.store_raw( text, from, created)     -> nil
    #
    # Store some text that appears like a mail to the local <code>MBox</code>.
    #
    def store_raw text, from, created
      from ||= local_from
      created ||= Time.now
      File.open @mailbox, "r+", encoding: Encoding::ASCII_8BIT do |f|
        f.seek [ f.size - 4, 0].max
        last = nil
        f.read.each_line { |l| last = l }
        f.puts if last and not last =~ RE_N

        f.puts "From #{from.gsub ' ', '_'} #{created.to_time.gmtime.asctime}"
        text.each_line { |l|
          l.chomp!
          f.print ">" if l =~ RE_F
          f.puts l
        }
        f.puts
      end
      nil
    end

    # :call-seq:
    #   mbox.each_mail { |mail| ... }    -> nil
    #
    # Iterate through <code>MBox</code>.
    #
    def each_mail
      File.open @mailbox, encoding: Encoding::ASCII_8BIT do |f|
        nl_seen = false
        from, created, text = nil, nil, nil
        f.each_line { |l|
          l.chomp!
          if l =~ RE_F then
            l = $'
            yield text, from, created if text
            length_tried = false
            from, created = l.split nil, 2
            begin
              created = DateTime.parse created
            rescue Date::Error
              unless length_tried then
                from = $'
                created = from.slice! from.length-Time.now.ctime.length, from.length
                from.strip!
                length_tried = true
                retry
              end
              raise "#@mailbox does not seem to be a mailbox: From line '#{l}'."
            end
            text, nl_seen = "", false
          else
            from or raise "#@mailbox does not seem to be a mailbox. No 'From' line."
            text << "\n" if nl_seen
            nl_seen = l =~ RE_N
            nl_seen or text << l << "\n"
          end
        }
        yield text, from, created
      end
    end

  end

  class Maildir < Box

    DIRS = %w(cur tmp new)
    CUR, TMP, NEW = *DIRS

    class <<self

      # :call-seq:
      #   Maildir.check( path)     -> true or false
      #
      # Check whether path is a <code>Maildir</code>.
      #
      def check mailbox
        if File.directory? mailbox then
          DIRS.each do |d|
            s = File.join mailbox, d
            File.directory? s or return false
          end
          true
        end
      end

    end

    # :call-seq:
    #   maildir.create     -> self
    #
    # Create the <code>Maildir</code>.
    #
    def create
      Dir.mkdir! @mailbox
      DIRS.each do |d|
        s = File.join @mailbox, d
        Dir.mkdir s
      end
      self
    end

    # :call-seq:
    #   maildir.store_raw( text, from, created)     -> nil
    #
    # Store some text that appears like a mail to the local <code>MBox</code>.
    #
    def store_raw text, from, created
      begin
        filename = mkfilename from, created
        tpath = File.join @mailbox, TMP, filename
        File.open tpath, File::CREAT|File::EXCL|File::WRONLY do |f| f.puts text end
        cpath = File.join @mailbox, NEW, filename
        File.link tpath, cpath
      rescue Errno::EEXIST
        File.unlink tpath rescue nil
        retry
      ensure
        File.unlink tpath
      end
      nil
    end

    # :call-seq:
    #   mbox.each_file { |filename| ... }    -> nil
    #
    # Iterate through <code>Maildir</code>.
    #
    def each_file new = nil
      p = File.join @mailbox, new ? NEW : CUR
      (Dir.new p).sort.each { |fn|
        next if fn.starts_with? "."
        path = File.join p, fn
        yield path
      }
    end

    # :call-seq:
    #   mbox.each { |mail| ... }    -> nil
    #
    # Iterate through <code>Maildir</code>.
    #
    def each_mail new = nil
      lfrom = local_from
      each_file new do |fn|
        created = Time.at fn[ /\A(\d+)/, 1].to_i + fn[ /M(\d+)/, 1].to_i*0.000001
        File.open fn, encoding: Encoding::ASCII_8BIT do |f|
          from_host = fn[ /\.([.a-z0-9_+-]+)/, 1]
          text = f.read
          from = text[ /[a-z0-9.+-]+@#{Regexp.quote from_host}/]
          yield text, from||lfrom, created
        end
      end
    end

    private

    @seq = 0
    class <<self
      def seq! ; @seq += 1 ; end
    end

    def mkfilename from, created
      host = if from =~ /@/ then
        $'
      else
        require "socket"
        Socket.gethostname
      end
      created ||= Time.now
      created = created.to_time
      "#{created.to_i}M#{created.usec}P#$$Q#{self.class.seq!}.#{host}"
    end

  end

end

