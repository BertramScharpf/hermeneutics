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
require "supplement/locked"
require "date"


module Hermeneutics

  # Mailboxes
  class Box

    @boxes = []

    class <<self

      # :call-seq:
      #   Box.find( path, default = nil)          -> box
      #
      # Create a Box object (some subclass of Box), depending on
      # what type the box is found at <code>path</code>.
      #
      def find path, default_format = nil
        b = @boxes.find { |b| b.check path }
        b ||= default_format
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

    # :stopdoc:
    class Region
      class <<self
        private :new
        def open file, start, stop
          t = file.tell
          begin
            i = new file, start, stop
            yield i
          ensure
            file.seek t
          end
        end
      end
      def initialize file, start, stop
        @file, @start, @stop = file, start, stop
        rewind
      end
      def rewind ; @file.seek @start ; end
      def read n = nil
        m = @stop - @file.tell
        n = m if not n or n > m
        @file.read n
      end
      def to_s
        rewind
        read
      end
      def each_line
        @file.each_line { |l|
          break if @file.tell > @stop
          yield l
        }
      end
      alias eat_lines each_line
    end
    # :startdoc:

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
    #   mbox.deliver( msg)     -> nil
    #
    # Store the mail into the local <code>MBox</code>.
    #
    def deliver msg
      pos = nil
      LockedFile.open @mailbox, "r+", encoding: Encoding::ASCII_8BIT do |f|
        f.seek [ f.size - 4, 0].max
        last = ""
        f.read.each_line { |l| last = l }
        f.puts unless last =~ /^$/
        pos = f.size
        m = msg.to_s
        i = 1
        while (i = m.index RE_F, i rescue nil) do m.insert i, ">" end
        f.write m
        f.puts
      end
      pos
    end

    # :call-seq:
    #   mbox.each { |mail| ... }    -> nil
    #
    # Iterate through <code>MBox</code>.
    #
    def each &block
      File.open @mailbox, encoding: Encoding::ASCII_8BIT do |f|
        m, e = nil, true
        s, t = t, f.tell
        f.each_line { |l|
          s, t = t, f.tell
          if is_from_line? l and e then
            begin
              m and Region.open f, m, e, &block
            ensure
              m, e = s, nil
            end
          else
            m or raise "#@mailbox does not seem to be a mailbox."
            e = l =~ RE_N && s
          end
        }
        # Treat it gracefully when there is no empty last line.
        e ||= f.tell
        m and Region.open f, m, e, &block
      end
    end
    include Enumerable

    private

    def is_from_line? l
      l =~ RE_F or return
      addr, time = $'.split nil, 2
      DateTime.parse time
      addr =~ /@/
    rescue ArgumentError, TypeError
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
    #   maildir.deliver( msg)     -> nil
    #
    # Store the mail into the local <code>Maildir</code>.
    #
    def deliver msg
      tmp = mkfilename TMP
      File.open tmp, "w" do |f|
        f.write msg
      end
      new = mkfilename NEW
      File.rename tmp, new
      new
    end

    # :call-seq:
    #   mbox.each { |mail| ... }    -> nil
    #
    # Iterate through <code>MBox</code>.
    #
    def each
      p = File.join @mailbox, CUR
      d = Dir.new p
      d.each { |f|
        next if f.starts_with? "."
        File.open f, encoding: Encoding::ASCII_8BIT do |f|
          yield f
        end
      }
    end
    include Enumerable

    private

    autoload :Socket, "socket"

    def mkfilename d
      dir = File.join @mailbox, d
      c = 0
      begin
        n = "%.4f.%d_%d.%s" % [ Time.now.to_f, $$, c, Socket.gethostname]
        path = File.join dir, n
        File.open path, File::CREAT|File::EXCL do |f| end
        path
      rescue Errno::EEXIST
        c += 1
        retry
      end
    end

  end

end

