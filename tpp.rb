#!/usr/bin/env ruby
require 'io/console'
version_number = "1.3.1"

# Loads the ncurses-ruby module and imports "Ncurses" into the
# current namespace. It stops the program if loading the
# ncurses-ruby module fails.
def load_ncurses
  begin
    require "ncurses"
    include Ncurses
  rescue LoadError
    $stderr.print <<EOF
  There is no Ncurses-Ruby package installed which is needed by TPP.
  You can download it on: http://ncurses-ruby.berlios.de/
EOF
    Kernel.exit(1)
  end
end

# Maps color names to constants and indexes.
class ColorMap

  # Maps color name _color_ to a constant
  def ColorMap.get_color(color)
    colors = { "white" => COLOR_WHITE,
               "yellow" => COLOR_YELLOW,
               "red" => COLOR_RED,
               "green" => COLOR_GREEN,
               "blue" => COLOR_BLUE,
               "cyan" => COLOR_CYAN,
               "magenta" => COLOR_MAGENTA,
               "black" => COLOR_BLACK,
               "default" => -1 }
    colors[color]
  end

  # Maps color name to a color pair index
  def ColorMap.get_color_pair(color)
    colors = { "white" => 1,
               "yellow" => 2,
               "red" => 3,
               "green" => 4,
               "blue" => 5,
               "cyan" => 6,
               "magenta" => 7,
               "black" => 8,
               "default" =>-1}
    colors[color]
  end

end

# Opens a TPP source file, and splits it into the different pages.
class FileParser

  def initialize(filename)
    @filename = filename
    @pages = []
  end

  # Parses the specified file and returns an array of Page objects
  def get_pages
    begin
      f = File.open(@filename)
    rescue
      $stderr.puts "Error: couldn't open file: #{$!}"
      Kernel.exit(1)
    end

    number_pages = 0

    cur_page = Page.new("Title")

    f.each_line do |line|
      line.chomp!
      case line
        when /^--##/ # ignore comments
        when /^--newpage/
          @pages << cur_page
          number_pages += 1
          name = line.sub(/^--newpage/,"")
          if name == "" then
            name = "slide " + (number_pages+1).to_s
          else
            name.strip!
          end
          cur_page = Page.new(name)
        else
          cur_page.add_line(line)
      end # case
    end # each
    @pages << cur_page
  end
end # class FileParser


# Represents a page (aka `slide') in TPP. A page consists of a title and one or
# more lines.
class Page

  def initialize(title)
    @lines = []
    @title = title
    @cur_line = 0
    @eop = false
  end

  # Appends a line to the page, but only if _line_ is not null
  def add_line(line)
    @lines << line if line
    if line =~ /^\$\$/ or line =~ /^\$\%/
      prefix = ''
      prefix = '%' if line =~ /^\$\%/

      cmd = line[2..-1]
      begin
        op = IO.popen(cmd,"r")
        op.readlines.each do |out_line|
          @lines << prefix + out_line
        end
        op.close
      rescue => e
        @lines << e.to_s
      end
    end
  end

  # Returns the next line. In case the last line is hit, then the end-of-page marker is set.
  def next_line
    line = @lines[@cur_line]
    @cur_line += 1
    if @cur_line >= @lines.size then
      @eop = true
    end
    return line
  end

  # Returns whether end-of-page has been reached.
  def eop?
    @eop
  end

  # Resets the end-of-page marker and sets the current line marker to the first line
  def reset_eop
    @cur_line = 0
    @eop = false
  end

  # Returns all lines in the page.
  def lines
    @lines
  end

  # Returns the page's title
  def title
    @title
  end
end



# Implements a generic visualizer from which all other visualizers need to be
# derived. If Ruby supported abstract methods, all the do_* methods would be
# abstract.
class TppVisualizer

  def initialize
    # nothing
  end

  # Splits a line into several lines, where each of the result lines is at most
  # _width_ characters long, caring about word boundaries, and returns an array
  # of strings.
  def split_lines(text,width)
    lines = []
    if text then
      begin
        i = width
        if text.length <= i then # text length is OK -> add it to array and stop splitting
          lines << text
          text = ""
        else
          # search for word boundary (space actually)
          while i > 0 and text[i] != ' '[0] do
            i -= 1
          end
          # if we can't find any space character, simply cut it off at the maximum width
          if i == 0 then
            i = width
          end
          # extract line
          x = text[0..i-1]
          # remove extracted line
          text = text[i+1..-1]
          # added line to array
          lines << x
        end
      end while text.length > 0
    end
    return lines
  end

  # Tokenizes inline formatting markers within a line. Returns an array of tokens:
  # [:text, "literal"], [:style, :bold/:underline/:reverse, true/false],
  # [:color, "red"], [:color_pop].
  def scan_inline_tokens(text)
    return [] if text == nil
    tokens = []
    buffer = ""
    i = 0
    while i < text.length
      if text[i,1] == "\\" && text[i+1,2] == "--"
        buffer << "--"
        i += 3
        next
      end
      if text[i,2] == "--"
        token_info = parse_inline_token_at(text, i)
        if token_info
          tokens << [:text, buffer] if buffer.length > 0
          buffer = ""
          tokens << token_info[0]
          i += token_info[1]
          next
        end
      end
      buffer << text[i,1]
      i += 1
    end
    tokens << [:text, buffer] if buffer.length > 0
    tokens
  end

  # Removes inline tokens and returns the plain text. Escaped tokens (\--b) are kept.
  def strip_inline_tokens(text)
    return "" if text == nil
    out = ""
    scan_inline_tokens(text).each do |token|
      if token[0] == :text
        out << token[1]
      end
    end
    out
  end

  def parse_inline_token_at(text, index)
    return [[:style, :bold, false], 4] if text[index,4] == "--/b"
    return [[:style, :bold, true], 3] if text[index,3] == "--b"
    return [[:style, :underline, false], 4] if text[index,4] == "--/u"
    return [[:style, :underline, true], 3] if text[index,3] == "--u"
    return [[:style, :reverse, false], 6] if text[index,6] == "--/rev"
    return [[:style, :reverse, true], 5] if text[index,5] == "--rev"
    return [[:color_pop], 4] if text[index,4] == "--/c"

    if text[index,3] == "--c"
      next_char = text[index + 3, 1]
      return nil if next_char == nil || next_char !~ /\s/
      j = index + 3
      while text[j,1] =~ /\s/
        j += 1
      end
      k = j
      while k < text.length && text[k,1] =~ /[A-Za-z]/
        k += 1
      end
      if k > j
        color = text[j...k]
        if valid_inline_color?(color)
          return [[:color, color], k - index]
        end
      end
    end
    nil
  end

  def valid_inline_color?(color)
    color == "white" || color == "yellow" || color == "red" ||
      color == "green" || color == "blue" || color == "cyan" ||
      color == "magenta" || color == "black" || color == "default"
  end

  def do_footer(footer_text)
    $stderr.puts "Error: TppVisualizer#do_footer has been called directly."
    Kernel.exit(1)
  end

  def do_header(header_text)
    $stderr.puts "Error: TppVisualizer#do_header has been called directly."
    Kernel.exit(1)
  end


  def do_refresh
    $stderr.puts "Error: TppVisualizer#do_refresh has been called directly."
    Kernel.exit(1)
  end

  def new_page
    $stderr.puts "Error: TppVisualizer#new_page has been called directly."
    Kernel.exit(1)
  end

  def do_heading(text)
    $stderr.puts "Error: TppVisualizer#do_heading has been called directly."
    Kernel.exit(1)
  end

  def do_withborder
    $stderr.puts "Error: TppVisualizer#do_withborder has been called directly."
    Kernel.exit(1)
  end

  def do_horline
    $stderr.puts "Error: TppVisualizer#do_horline has been called directly."
    Kernel.exit(1)
  end

  def do_color(text)
    $stderr.puts "Error: TppVisualizer#do_color has been called directly."
    Kernel.exit(1)
  end

  def do_center(text)
    $stderr.puts "Error: TppVisualizer#do_center has been called directly."
    Kernel.exit(1)
  end

  def do_right(text)
    $stderr.puts "Error: TppVisualizer#do_right has been called directly."
    Kernel.exit(1)
  end

  def do_exec(cmdline)
    $stderr.puts "Error: TppVisualizer#do_exec has been called directly."
    Kernel.exit(1)
  end

  def do_wait
    $stderr.puts "Error: TppVisualizer#do_wait has been called directly."
    Kernel.exit(1)
  end

  def do_beginoutput
    $stderr.puts "Error: TppVisualizer#do_beginoutput has been called directly."
    Kernel.exit(1)
  end

  def do_beginshelloutput
    $stderr.puts "Error: TppVisualizer#do_beginshelloutput has been called directly."
    Kernel.exit(1)
  end

  def do_endoutput
    $stderr.puts "Error: TppVisualizer#do_endoutput has been called directly."
    Kernel.exit(1)
  end

  def do_endshelloutput
    $stderr.puts "Error: TppVisualizer#do_endshelloutput has been called directly."
    Kernel.exit(1)
  end

  def do_sleep(time2sleep)
    $stderr.puts "Error: TppVisualizer#do_sleep has been called directly."
    Kernel.exit(1)
  end

  def do_boldon
    $stderr.puts "Error: TppVisualizer#do_boldon has been called directly."
    Kernel.exit(1)
  end

  def do_boldoff
    $stderr.puts "Error: TppVisualizer#do_boldoff has been called directly."
    Kernel.exit(1)
  end

  def do_revon
    $stderr.puts "Error: TppVisualizer#do_revon has been called directly."
    Kernel.exit(1)
  end

  def do_revoff
    $stderr.puts "Error: TppVisualizer#do_revoff has been called directly."
    Kernel.exit(1)
  end

  def do_ulon
    $stderr.puts "Error: TppVisualizer#do_ulon has been called directly."
    Kernel.exit(1)
  end

  def do_uloff
    $stderr.puts "Error: TppVisualizer#do_uloff has been called directly."
    Kernel.exit(1)
  end

  def do_beginslideleft
    $stderr.puts "Error: TppVisualizer#do_beginslideleft has been called directly."
    Kernel.exit(1)
  end

  def do_endslide
    $stderr.puts "Error: TppVisualizer#do_endslide has been called directly."
    Kernel.exit(1)
  end

  def do_beginslideright
    $stderr.puts "Error: TppVisualizer#do_beginslideright has been called directly."
    Kernel.exit(1)
  end

  def do_beginslidetop
    $stderr.puts "Error: TppVisualizer#do_beginslidetop has been called directly."
    Kernel.exit(1)
  end

  def do_beginslidebottom
    $stderr.puts "Error: TppVisualizer#do_beginslidebottom has been called directly."
    Kernel.exit(1)
  end

  def do_sethugefont
    $stderr.puts "Error: TppVisualizer#do_sethugefont has been called directly."
    Kernel.exit(1)
  end

  def do_huge(text)
    $stderr.puts "Error: TppVisualizer#do_huge has been called directly."
    Kernel.exit(1)
  end

  def print_line(line)
    $stderr.puts "Error: TppVisualizer#print_line has been called directly."
    Kernel.exit(1)
  end

  def do_title(title)
    $stderr.puts "Error: TppVisualizer#do_title has been called directly."
    Kernel.exit(1)
  end

  def do_author(author)
    $stderr.puts "Error: TppVisualizer#do_author has been called directly."
    Kernel.exit(1)
  end

  def do_date(date)
    $stderr.puts "Error: TppVisualizer#do_date has been called directly."
    Kernel.exit(1)
  end

  def do_bgcolor(color)
    $stderr.puts "Error: TppVisualizer#do_bgcolor has been called directly."
    Kernel.exit(1)
  end

  def do_fgcolor(color)
    $stderr.puts "Error: TppVisualizer#do_fgcolor has been called directly."
    Kernel.exit(1)
  end

  def do_color(color)
    $stderr.puts "Error: TppVisualizer#do_color has been called directly."
    Kernel.exit(1)
  end

  # Receives a _line_, parses it if necessary, and dispatches it
  # to the correct method which then does the correct processing.
  # It returns whether the controller shall wait for input.
  def visualize(line)
    case line
      when /^--heading /
        text = line.sub(/^--heading /,"")
        do_heading(text)
      when /^--withborder/
        do_withborder
      when /^--horline/
        do_horline
      when /^--color /
        text = line.sub(/^--color /,"")
        text.strip!
        do_color(text)
      when /^--center /
        text = line.sub(/^--center /,"")
        do_center(text)
      when /^--right /
        text = line.sub(/^--right /,"")
        do_right(text)
      when /^--exec /
        cmdline = line.sub(/^--exec /,"")
        do_exec(cmdline)
      when /^---/
        do_wait
        return true
      when /^--beginoutput/
        do_beginoutput
      when /^--beginshelloutput/
        do_beginshelloutput
      when /^--endoutput/
        do_endoutput
      when /^--endshelloutput/
        do_endshelloutput
      when /^--sleep /
        time2sleep = line.sub(/^--sleep /,"")
        do_sleep(time2sleep)
      when /^--boldon/
        do_boldon
      when /^--boldoff/
        do_boldoff
      when /^--revon/
        do_revon
      when /^--revoff/
        do_revoff
      when /^--ulon/
        do_ulon
      when /^--uloff/
        do_uloff
      when /^--beginslideleft/
        do_beginslideleft
      when /^--endslideleft/, /^--endslideright/, /^--endslidetop/, /^--endslidebottom/
        do_endslide
      when /^--beginslideright/
        do_beginslideright
      when /^--beginslidetop/
        do_beginslidetop
      when /^--beginslidebottom/
        do_beginslidebottom
      when /^--sethugefont /
        params = line.sub(/^--sethugefont /,"")
        do_sethugefont(params.strip)
      when /^--huge /
        figlet_text = line.sub(/^--huge /,"")
        do_huge(figlet_text)
      when /^--footer /
        @footer_txt = line.sub(/^--footer /,"")
        do_footer(@footer_txt)
      when /^--header /
        @header_txt = line.sub(/^--header /,"")
        do_header(@header_txt)
      when /^--title /
        title = line.sub(/^--title /,"")
        do_title(title)
      when /^--author /
        author = line.sub(/^--author /,"")
        do_author(author)
      when /^--date /
        date = line.sub(/^--date /,"")
        if date == "today" then
          date = Time.now.strftime("%b %d %Y")
        elsif date =~ /^today / then
          date = Time.now.strftime(date.sub(/^today /,""))
        end
        do_date(date)
      when /^--bgcolor /
        color = line.sub(/^--bgcolor /,"").strip
        do_bgcolor(color)
      when /^--fgcolor /
        color = line.sub(/^--fgcolor /,"").strip
        do_fgcolor(color)
      when /^--color /
        color = line.sub(/^--color /,"").strip
        do_color(color)
      when /^--include-file /
        @lastFileName = line.sub(/^--include-file /,"").strip
        do_beginoutput
        print_line(@lastFileName)
        f = File.open(@lastFileName)
        f.each_line do |fileLine|
          fileLine.chomp!
          if fileLine
            print_line(fileLine)
          end
        end
        do_endoutput
    else
      print_line(line)
    end

    return false
  end

  def close
    # nothing
  end

end

# Implements an interactive visualizer which builds on top of ncurses.
class NcursesVisualizer < TppVisualizer

  StyleState = Struct.new(:bold, :underline, :reverse, :color)

  def initialize
    @figletfont = "standard"
    Ncurses.initscr
    Ncurses.curs_set(0)
    Ncurses.cbreak # unbuffered input
    Ncurses.noecho # turn off input echoing
    Ncurses.stdscr.intrflush(false)
    Ncurses.stdscr.keypad(true)
    @screen = Ncurses.stdscr
    @lastFileName = nil
    setsizes
    Ncurses.start_color()
    Ncurses.use_default_colors()
    @fgcolor = ColorMap.get_color_pair("white")
    @voffset = 5
    @indent = 3
    @cur_line = @voffset
    @output = @shelloutput = false
    @slideoutput = false
    @style_state = StyleState.new(false, false, false, @fgcolor)
    @active_style = StyleState.new(false, false, false, nil)
    @last_status_len = 0
    @style_support = { :bold => true, :underline => true, :reverse => true }
    do_bgcolor("black")
    #do_fgcolor("white")
    apply_style(@style_state)
  end

  def copy_style(state)
    StyleState.new(state.bold, state.underline, state.reverse, state.color)
  end

  def apply_style(state)
    if state.bold != @active_style.bold
      if state.bold then
        safe_attron(:bold)
      else
        safe_attroff(:bold)
      end
      @active_style.bold = state.bold
    end
    if state.underline != @active_style.underline
      if state.underline then
        safe_attron(:underline)
      else
        safe_attroff(:underline)
      end
      @active_style.underline = state.underline
    end
    if state.reverse != @active_style.reverse
      if state.reverse then
        safe_attron(:reverse)
      else
        safe_attroff(:reverse)
      end
      @active_style.reverse = state.reverse
    end
    if state.color && state.color != @active_style.color
      @screen.attron(Ncurses.COLOR_PAIR(state.color))
      @active_style.color = state.color
    end
  end

  def ncurses_attr(kind)
    return Ncurses::A_BOLD if kind == :bold
    return Ncurses::A_UNDERLINE if kind == :underline
    return Ncurses::A_REVERSE if kind == :reverse
    nil
  end

  def safe_attron(kind)
    return unless @style_support[kind]
    attr = ncurses_attr(kind)
    return unless attr
    begin
      @screen.attron(attr)
    rescue
      @style_support[kind] = false
    end
  end

  def safe_attroff(kind)
    return unless @style_support[kind]
    attr = ncurses_attr(kind)
    return unless attr
    begin
      @screen.attroff(attr)
    rescue
      @style_support[kind] = false
    end
  end

  def with_style(overrides)
    saved = copy_style(@style_state)
    overrides.each do |key, value|
      @style_state.send("#{key}=", value)
    end
    apply_style(@style_state)
    yield
  ensure
    @style_state = saved
    apply_style(@style_state)
  end

  def build_inline_units(text, base_state)
    tokens = scan_inline_tokens(text)
    units = []
    state = copy_style(base_state)
    color_stack = []
    tokens.each do |token|
      case token[0]
      when :text
        s = token[1]
        i = 0
        while i < s.length
          units << [s[i,1], state]
          i += 1
        end
      when :style
        state = copy_style(state)
        if token[1] == :bold
          state.bold = token[2]
        elsif token[1] == :underline
          state.underline = token[2]
        elsif token[1] == :reverse
          state.reverse = token[2]
        end
      when :color
        color_pair = ColorMap.get_color_pair(token[1])
        if color_pair
          color_stack << state.color
          state = copy_style(state)
          state.color = color_pair
        end
      when :color_pop
        if color_stack.length > 0
          state = copy_style(state)
          state.color = color_stack.pop
        end
      end
    end
    units
  end

  def wrap_units(units, width)
    width = 1 if width < 1
    return [[]] if units.length == 0
    lines = []
    idx = 0
    while idx < units.length
      remaining = units.length - idx
      if remaining <= width
        lines << units[idx..-1]
        break
      end
      break_idx = nil
      i = idx + width - 1
      while i >= idx
        if units[i][0] == " "
          break_idx = i
          break
        end
        i -= 1
      end
      if break_idx == nil || break_idx == idx
        lines << units[idx, width]
        idx += width
      else
        lines << units[idx...break_idx]
        idx = break_idx + 1
      end
    end
    lines
  end

  def units_to_segments(units)
    segments = []
    cur_state = nil
    buffer = ""
    units.each do |unit|
      ch = unit[0]
      state = unit[1]
      if cur_state && state.equal?(cur_state)
        buffer << ch
      else
        segments << [cur_state, buffer] if buffer.length > 0
        cur_state = state
        buffer = ch
      end
    end
    segments << [cur_state, buffer] if buffer.length > 0
    segments
  end

  def alignment_x(visible_length, align)
    if align == :center
      (@termwidth - visible_length) / 2
    elsif align == :right
      @termwidth - @indent - visible_length
    else
      @indent
    end
  end

  def right_align_x(visible_length)
    padding = (@output || @shelloutput) ? 2 : 0
    x = @termwidth - @indent - padding - visible_length
    x = @indent if x < @indent
    x
  end

  def render_plain_lines(text, width, align, allow_shell, allow_slide)
    lines = split_lines(text, width)
    lines << "" if lines.length == 0
    lines.each do |line|
      @screen.move(@cur_line, @indent)
      if (@output or @shelloutput) and ! @slideoutput
        @screen.addstr("| ")
      end
      if align == :center
        x = (@termwidth - line.length) / 2
        @screen.move(@cur_line, x)
        @screen.addstr(line)
      elsif align == :right
        x = right_align_x(line.length)
        @screen.move(@cur_line, x)
        @screen.addstr(line)
      else
        if allow_shell and @shelloutput and (line =~ /^\$/ or line =~ /^%/ or line =~ /^#/)
          type_line(line)
        elsif allow_slide
          slide_text(line)
        else
          @screen.addstr(line)
        end
      end
      if (@output or @shelloutput) and ! @slideoutput
        @screen.move(@cur_line, @termwidth - @indent - 2)
        @screen.addstr(" |")
      end
      @cur_line += 1
    end
  end

  def render_inline_lines(text, width, align)
    units = build_inline_units(text, @style_state)
    lines = wrap_units(units, width)
    lines.each do |line_units|
      visible_length = line_units.length
      x = alignment_x(visible_length, align)
      @screen.move(@cur_line, x)
      if line_units.length > 0
        units_to_segments(line_units).each do |segment|
          apply_style(segment[0])
          @screen.addstr(segment[1])
        end
        apply_style(@style_state)
      end
      @cur_line += 1
    end
  end

  def render_text(text, align)
    return if text == nil
    width = @termwidth - 2*@indent
    width -= 2 if @output or @shelloutput
    width = 1 if width < 1
    if @output or @shelloutput
      render_plain_lines(text, width, align, align == :left, false)
    elsif align == :left && @slideoutput
      render_plain_lines(strip_inline_tokens(text), width, align, false, true)
    else
      render_inline_lines(text, width, align)
    end
  end

  def get_key
    ch = Ncurses.getch
    case ch
      when 100, #d
        68, #D
        106, #j
        74, #J
        108, #l
        76, #L
        Ncurses::KEY_DOWN,
        Ncurses::KEY_RIGHT
        return :keyright
      when 97, #a
        65, #A
        98, #b
        66, #B
        104, #h
        72, #h
        107, #k
        75, #k
        Ncurses::KEY_UP,
        Ncurses::KEY_LEFT
        return :keyleft
      when 122, #z
        90 #Z
        return :keyresize
      when 114, #r
        82 #R
        return :reload
      when 113, #q
        81 #Q
        return :quit
      when 115, #s
        83 #S
        return :firstpage
      when 101, #e
        69 #E
        return :edit
      when 103, #g
        71 #g
        return :jumptoslide
      when 63 #?
        return :help

      else
        return :keyright
    end
  end

  def clear
    @screen.clear
    @screen.refresh
  end


  def setsizes
    @termwidth = Ncurses.getmaxx(@screen)
    @termheight = Ncurses.getmaxy(@screen)
  end

  def do_refresh
    @screen.refresh
  end

  def do_withborder
    @withborder = true
    draw_border
  end

  def draw_border
    @screen.move(0,0)
    @screen.addstr(".")
    (@termwidth-2).times { @screen.addstr("-") }; @screen.addstr(".")
    @screen.move(@termheight-2,0)
    @screen.addstr("`")
    (@termwidth-2).times { @screen.addstr("-") }; @screen.addstr("'")
    1.upto(@termheight-3) do |y|
      @screen.move(y,0)
      @screen.addstr("|")
    end
    1.upto(@termheight-3) do |y|
      @screen.move(y,@termwidth-1)
      @screen.addstr("|")
    end
  end

  def new_page
    @cur_line = @voffset
    @output = @shelloutput = false
    setsizes
    @screen.clear
  end

  def do_heading(line)
    with_style(:bold => true) do
      render_text(line, :center)
    end
  end

  def do_horline
    with_style(:bold => true) do
      @termwidth.times do |x|
        @screen.move(@cur_line,x)
        @screen.addstr("-")
      end
    end
  end

  def print_heading(text)
    width = @termwidth - 2*@indent
    lines = split_lines(text,width)
    lines.each do |l|
      @screen.move(@cur_line,@indent)
      x = (@termwidth - l.length)/2
      @screen.move(@cur_line,x)
      @screen.addstr(l)
      @cur_line += 1
    end
  end

  def do_center(text)
    render_text(text, :center)
  end

  def do_right(text)
    render_text(text, :right)
  end

  def show_help_page
    help_text = [ "tpp help",
                  "",
                  "space bar ............................... display next entry within page",
                  "space bar, cursor-down, cursor-right .... display next page",
                  "b, cursor-up, cursor-left ............... display previous page",
                  "q, Q .................................... quit tpp",
                  "j, J .................................... jump directly to page",
                  "l, L .................................... reload current file",
                  "s, S .................................... jump to the first page",
                  "e, E .................................... jump to the last page",
                  "c, C .................................... start command line",
                  "?, h .................................... this help screen" ]
    @screen.clear
    y = @voffset
    help_text.each do |line|
      @screen.move(y,@indent)
      @screen.addstr(line)
      y += 1
    end
    @screen.move(@termheight - 2, @indent)
    @screen.addstr("Press any key to return to slide")
    @screen.refresh
  end

  def do_exec(cmdline)
    rc = Kernel.system(cmdline)
    if not rc then
      # @todo: add error message
    end
  end

  def do_wait
    # nothing
  end

  def do_beginoutput
    @screen.move(@cur_line,@indent)
    @screen.addstr(".")
    (@termwidth - @indent*2 - 2).times { @screen.addstr("-") }
    @screen.addstr(".")
    @output = true
    @cur_line += 1
  end

  def do_beginshelloutput
    @screen.move(@cur_line,@indent)
    @screen.addstr(".")
    (@termwidth - @indent*2 - 2).times { @screen.addstr("-") }
    @screen.addstr(".")
    @shelloutput = true
    @cur_line += 1
  end

  def do_endoutput
    if @output then
      @screen.move(@cur_line,@indent)
      @screen.addstr("`")
      (@termwidth - @indent*2 - 2).times { @screen.addstr("-") }
      @screen.addstr("'")
      @output = false
      @cur_line += 1
    end
  end

  def do_title(title)
    do_boldon
    do_center(title)
    do_boldoff
    do_center("")
  end

  def do_footer(footer_txt)
    @screen.move(@termheight - 3, (@termwidth - footer_txt.length)/2)
    @screen.addstr(footer_txt)
  end

 def do_header(header_txt)
    @screen.move(@termheight - @termheight+1, (@termwidth - header_txt.length)/2)
    @screen.addstr(header_txt)
 end

  def do_author(author)
    do_center(author)
    do_center("")
  end

  def do_date(date)
    do_center(date)
    do_center("")
  end

  def do_endshelloutput
    if @shelloutput then
      @screen.move(@cur_line,@indent)
      @screen.addstr("`")
      (@termwidth - @indent*2 - 2).times { @screen.addstr("-") }
      @screen.addstr("'")
      @shelloutput = false
      @cur_line += 1
    end
  end

  def do_sleep(time2sleep)
    Kernel.sleep(time2sleep.to_i)
  end

  def do_boldon
    @style_state.bold = true
    apply_style(@style_state)
  end

  def do_boldoff
    @style_state.bold = false
    apply_style(@style_state)
  end

  def do_revon
    @style_state.reverse = true
    apply_style(@style_state)
  end

  def do_revoff
    @style_state.reverse = false
    apply_style(@style_state)
  end

  def do_ulon
    @style_state.underline = true
    apply_style(@style_state)
  end

  def do_uloff
    @style_state.underline = false
    apply_style(@style_state)
  end

  def do_beginslideleft
    @slideoutput = true
    @slidedir = "left"
  end

  def do_endslide
    @slideoutput = false
  end

  def do_beginslideright
    @slideoutput = true
    @slidedir = "right"
  end

  def do_beginslidetop
    @slideoutput = true
    @slidedir = "top"
  end

  def do_beginslidebottom
    @slideoutput = true
    @slidedir = "bottom"
  end

  def do_sethugefont(params)
    @figletfont = params
  end

  def do_huge(figlet_text)
    output_width = @termwidth - @indent
    output_width -= 2 if @output or @shelloutput
    op = IO.popen("figlet -f #{@figletfont} -w #{output_width} -k \"#{figlet_text}\"","r")
    op.readlines.each do |line|
      print_line(line)
    end
    op.close
  end

  def do_bgcolor(color)
    bgcolor = ColorMap.get_color(color) or COLOR_BLACK
    Ncurses.init_pair(1, COLOR_WHITE, bgcolor)
    Ncurses.init_pair(2, COLOR_YELLOW, bgcolor)
    Ncurses.init_pair(3, COLOR_RED, bgcolor)
    Ncurses.init_pair(4, COLOR_GREEN, bgcolor)
    Ncurses.init_pair(5, COLOR_BLUE, bgcolor)
    Ncurses.init_pair(6, COLOR_CYAN, bgcolor)
    Ncurses.init_pair(7, COLOR_MAGENTA, bgcolor)
    Ncurses.init_pair(8, COLOR_BLACK, bgcolor)
    if @fgcolor then
      Ncurses.bkgd(Ncurses.COLOR_PAIR(@fgcolor))
    else
      Ncurses.bkgd(Ncurses.COLOR_PAIR(1))
    end
    apply_style(@style_state)
  end

  def do_fgcolor(color)
    @fgcolor = ColorMap.get_color_pair(color)
    @style_state.color = @fgcolor
    apply_style(@style_state)
  end

  def do_color(color)
    num = ColorMap.get_color_pair(color)
    if num
      @style_state.color = num
      apply_style(@style_state)
    end
  end

  def type_line(l)
    l.each_byte do |x|
      @screen.addstr(x.chr)
      @screen.refresh()
      r = rand(20)
      time_to_sleep = (5 + r).to_f / 250;
      # puts "#{time_to_sleep} #{r}"
      Kernel.sleep(time_to_sleep)
    end
  end

  def slide_text(l)
    return if l == ""
    case @slidedir
    when "left"
      xcount = l.length-1
      while xcount >= 0
        @screen.move(@cur_line,@indent)
        @screen.addstr(l[xcount..l.length-1])
        @screen.refresh()
        time_to_sleep = 1.to_f / 20
        Kernel.sleep(time_to_sleep)
        xcount -= 1
      end
    when "right"
      (@termwidth - @indent).times do |pos|
        @screen.move(@cur_line,@termwidth - pos - 1)
        @screen.clrtoeol()
        @screen.addstr(l[0..pos])
        @screen.refresh()
        time_to_sleep = 1.to_f / 20
        Kernel.sleep(time_to_sleep)
      end # do
    when "top"
      # ycount = @cur_line
      new_scr = @screen.dupwin
      1.upto(@cur_line) do |i|
        Ncurses.overwrite(new_scr,@screen) # overwrite @screen with new_scr
        @screen.move(i,@indent)
        @screen.addstr(l)
        @screen.refresh()
        Kernel.sleep(1.to_f / 10)
      end
    when "bottom"
      new_scr = @screen.dupwin
      (@termheight-1).downto(@cur_line) do |i|
        Ncurses.overwrite(new_scr,@screen)
        @screen.move(i,@indent)
        @screen.addstr(l)
        @screen.refresh()
        Kernel.sleep(1.to_f / 10)
      end
    end
  end

  def print_line(line)
    render_text(line, :left)
  end

  def close
    Ncurses.nocbreak
    Ncurses.endwin
  end

  def read_newpage(pages,current_page)
    page = []
    @screen.clear()
    col = 0
    line = 2
    pages.each_index do |i|
      @screen.move(line,col*15 + 2)
      if current_page == i then
        @screen.printw("%2d %s <=",i+1,pages[i].title[0..80])
      else
        @screen.printw("%2d %s",i+1,pages[i].title[0..80])
      end
      line += 1
      if line >= @termheight - 3 then
        line = 2
        col += 1
      end
    end
    prompt = "jump to slide: "
    prompt_indent = 12
    @screen.move(@termheight - 2, @indent + prompt_indent)
    @screen.addstr(prompt)
    # @screen.refresh();
    Ncurses.echo
    @screen.scanw("%d",page)
    Ncurses.noecho
    @screen.move(@termheight - 2, @indent + prompt_indent)
    (prompt.length + page[0].to_s.length).times { @screen.addstr(" ") }
    if page[0] then
      return page[0] - 1
    end
    return -1 # invalid page
  end

  def store_screen
    @screen.dupwin
  end

  def getLastFile
    @lastFileName
  end

  def restore_screen(s)
    Ncurses.overwrite(s,@screen)
  end

  def draw_slidenum(cur_page,max_pages,eop,title = nil)
    with_style(:bold => false) do
      status = "[slide #{cur_page}/#{max_pages}]"
      max_width = @termwidth - @indent
      if title and title.length > 0
        available = max_width - status.length - 1
        if available > 0
          status = status + " " + title[0, available]
        end
      end
      if status.length > max_width
        status = status[0, max_width]
      end
      if @last_status_len > status.length
        status = status + (" " * (@last_status_len - status.length))
      end
      @last_status_len = status.length
      @screen.move(@termheight - 2, @indent)
      @screen.addstr(status)
    end
    if @footer_txt.to_s.length > 0 then
      do_footer(@footer_txt)
    end
    if @header_txt.to_s.length > 0 then
      do_header(@header_txt)
    end

    if eop then
      draw_eop_marker
    end
  end

  def draw_eop_marker
    with_style(:bold => true) do
      @screen.move(@termheight - 2, @indent - 1)
      @screen.addstr("*")
    end
  end

end


# Implements a visualizer which converts TPP source to LaTeX-beamer source (http://latex-beamer.sf.net/
class LatexVisualizer < TppVisualizer

  def initialize(outputfile)
    @filename = outputfile
    begin
      @f = File.open(@filename,"w+")
    rescue
      $stderr.print "Error: couldn't open file: #{$!}"
      Kernel.exit(1)
    end
    @slide_open = false
    @verbatim_open = false
    @width = 50
    @title = @date = @author = false
    @begindoc = false
    @f.puts '% Filename:      tpp.tex
% Purpose:       template file for tpp latex export
% Authors:       (c) Andreas Gredler, Michael Prokop http://grml.org/
% License:       This file is licensed under the GPL v2.
% Latest change: Fre Apr 15 20:34:37 CEST 2005
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

\documentclass{beamer}

\mode<presentation>
{
  \usetheme{Montpellier}
  \setbeamercovered{transparent}
}

\usepackage[german]{babel}
\usepackage{umlaut}
\usepackage[latin1]{inputenc}
\usepackage{times}
\usepackage[T1]{fontenc}

'
  end

  def do_footer(footer_text)
  end

  def do_header(header_text)
  end

  def do_refresh
  end

  def try_close
    if @verbatim_open then
      @f.puts '\end{verbatim}'
      @verbatim_open = false
    end
    if @slide_open then
      @f.puts '\end{frame}'
      @slide_open = false
    end
  end

  def new_page
    try_close
  end

  def do_heading(text)
    try_close
    @f.puts "\\section{#{strip_inline_tokens(text)}}"
  end

  def do_withborder
  end

  def do_horline
  end

  def do_color(text)
  end

  def do_center(text)
    print_line(text)
  end

  def do_right(text)
    print_line(text)
  end

  def do_exec(cmdline)
  end

  def do_wait
  end

  def do_beginoutput
    # TODO: implement output stuff
  end

  def do_beginshelloutput
  end

  def do_endoutput
  end

  def do_endshelloutput
  end

  def do_sleep(time2sleep)
  end

  def do_boldon
  end

  def do_boldoff
  end

  def do_revon
  end

  def do_revoff
  end

  def do_ulon
  end

  def do_uloff
  end

  def do_beginslideleft
  end

  def do_endslide
  end

  def do_beginslideright
  end

  def do_beginslidetop
  end

  def do_beginslidebottom
  end

  def do_sethugefont(text)
  end

  def do_huge(text)
  end

  def try_open
    if not @begindoc then
      @f.puts '\begin{document}'
      @begindoc = true
    end
    if not @slide_open then
      @f.puts '\begin{frame}[fragile]'
      @slide_open = true
    end
    if not @verbatim_open then
      @f.puts '\begin{verbatim}'
      @verbatim_open = true
    end
  end

  def try_intro
    if @author and @title and @date and not @begindoc then
      @f.puts '\begin{document}'
      @begindoc = true
    end
    if @author and @title and @date then
      @f.puts '\begin{frame}
        \titlepage
      \end{frame}'
    end
  end

  def print_line(line)
    line = strip_inline_tokens(line)
    try_open
    split_lines(line,@width).each do |l|
      @f.puts "#{l}"
    end
  end

  def do_title(title)
    title = strip_inline_tokens(title)
    @f.puts "\\title[#{title}]{#{title}}"
    @title = true
    try_intro
  end

  def do_author(author)
    @f.puts "\\author{#{strip_inline_tokens(author)}}"
    @author = true
    try_intro
  end

  def do_date(date)
    @f.puts "\\date{#{strip_inline_tokens(date)}}"
    @date = true
    try_intro
  end

  def do_bgcolor(color)
  end

  def do_fgcolor(color)
  end

  def do_color(color)
  end

  def close
    try_close
    @f.puts '\end{document}
    %%%%% END OF FILE %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%'
    @f.close
  end

end


# Implements a generic controller from which all other controllers need to be derived.
class TppController

  def initialize
    $stderr.puts "Error: TppController.initialize has been called directly!"
    Kernel.exit(1)
  end

  def close
    $stderr.puts "Error: TppController.close has been called directly!"
    Kernel.exit(1)
  end

  def run
    $stderr.puts "Error: TppController.run has been called directly!"
    Kernel.exit(1)
  end

end

# Implements a non-interactive controller for ncurses. Useful for displaying
# unattended presentation.
class AutoplayController < TppController

  def initialize(filename,secs,visualizer_class)
    @filename = filename
    @vis = visualizer_class.new
    @seconds = secs
    @cur_page = 0
  end

  def close
    @vis.close
  end

  def run
    begin
      @reload_file = false
      parser = FileParser.new(@filename)
      @pages = parser.get_pages
      if @cur_page >= @pages.size then
        @cur_page = @pages.size - 1
      end
      @vis.clear
      @vis.new_page
      do_run
    end while @reload_file
  end

  def do_run
    loop do
      wait = false
      @vis.draw_slidenum(@cur_page + 1, @pages.size, false, @pages[@cur_page].title)
      # read and visualize lines until the visualizer says "stop" or we reached end of page
      begin
        line = @pages[@cur_page].next_line
        eop = @pages[@cur_page].eop?
        wait = @vis.visualize(line)
      end while not wait and not eop
      # draw slide number on the bottom left and redraw:
      @vis.draw_slidenum(@cur_page + 1, @pages.size, eop, @pages[@cur_page].title)
      @vis.do_refresh

      if eop then
        if @cur_page + 1 < @pages.size then
          @cur_page += 1
        else
          @cur_page = 0
        end
        @pages[@cur_page].reset_eop
        @vis.new_page
      end

      Kernel.sleep(@seconds)
    end # loop
  end

end

# Implements an interactive controller which feeds the visualizer until it is
# told to stop, and then reads a key press and executes the appropriate action.
class InteractiveController < TppController

  def initialize(filename,visualizer_class)
    @filename = filename
    @vis = visualizer_class.new
    @cur_page = 0
  end

  def close
    @vis.close
  end

  def run
    begin
      @reload_file = false
      parser = FileParser.new(@filename)
      @pages = parser.get_pages
      if @cur_page >= @pages.size then
        @cur_page = @pages.size - 1
      end
      @vis.clear
      @vis.new_page
      do_run
    end while @reload_file
  end

  def do_run
    loop do
      wait = false
      @vis.draw_slidenum(@cur_page + 1, @pages.size, false, @pages[@cur_page].title)
      # read and visualize lines until the visualizer says "stop" or we reached end of page
      begin
        line = @pages[@cur_page].next_line
        eop = @pages[@cur_page].eop?
        wait = @vis.visualize(line)
      end while not wait and not eop
      # draw slide number on the bottom left and redraw:
      @vis.draw_slidenum(@cur_page + 1, @pages.size, eop, @pages[@cur_page].title)
      @vis.do_refresh

      # read a character from the keyboard
      # a "break" in the when means that it breaks the loop, i.e. goes on with visualizing lines
      loop do
        ch = @vis.get_key
        case ch
          when :quit
            return
          when :redraw
            # @todo: actually implement redraw
          when :lastpage
            @cur_page = @pages.size - 1
            break
          when :edit
            if @vis.getLastFile
              screen = @vis.store_screen
              Kernel.system("vim " + @vis.getLastFile)
              @vis.restore_screen(screen)
            end
            break
          when :firstpage
            @cur_page = 0
            break
          when :jumptoslide
            screen = @vis.store_screen
            p = @vis.read_newpage(@pages,@cur_page)
            if p >= 0 and p < @pages.size
              @cur_page = p
              @pages[@cur_page].reset_eop
              @vis.new_page
            else
              @vis.restore_screen(screen)
            end
            break
          when :reload
            @reload_file = true
            return
          when :help
            screen = @vis.store_screen
            @vis.show_help_page
            ch = @vis.get_key
            @vis.clear
            @vis.restore_screen(screen)
          when :keyright
            if @cur_page + 1 < @pages.size and eop then
              @cur_page += 1
              @pages[@cur_page].reset_eop
              @vis.new_page
            end
            break
          when :keyleft
            if @cur_page > 0 then
              @cur_page -= 1
              @pages[@cur_page].reset_eop
              @vis.new_page
            end
            break
          when :keyresize
            @vis.setsizes
        end
      end
    end # loop
  end

end


# Implements a visualizer which converts TPP source to a nicely formatted text
# file which can e.g. be used as handout.
class TextVisualizer < TppVisualizer

  def initialize(outputfile)
    @filename = outputfile
    begin
      @f = File.open(@filename,"w+")
    rescue
      $stderr.print "Error: couldn't open file: #{$!}"
      Kernel.exit(1)
    end
    @output_env = false
    @title = @author = @date = false
    @figletfont = "small"
    @width = 80
  end

  def do_footer(footer_text)
  end

  def do_header(header_text)
  end

  def do_refresh
  end

  def new_page
    @f.puts "--------------------------------------------"
  end

  def do_heading(text)
    @f.puts "\n"
    split_lines(strip_inline_tokens(text),@width).each do |l|
      @f.puts "#{l}\n"
    end
    @f.puts "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  end

  def do_withborder
  end

  def do_horline
    @f.puts "********************************************"
  end

  def do_color(text)
  end

  def do_exec(cmdline)
  end

  def do_wait
  end

  def do_beginoutput
    @f.puts ".---------------------------"
    @output_env = true
  end

  def do_beginshelloutput
    do_beginoutput
  end

  def do_endoutput
    @f.puts "`---------------------------"
    @output_env = false
  end

  def do_endshelloutput
    do_endoutput
  end

  def do_sleep(time2sleep)
  end

  def do_boldon
  end

  def do_boldoff
  end

  def do_revon
  end

  def do_revoff
  end

  def do_ulon
  end

  def do_uloff
  end

  def do_beginslideleft
  end

  def do_endslide
  end

  def do_beginslideright
  end

  def do_beginslidetop
  end

  def do_beginslidebottom
  end

  def do_sethugefont(text)
    @figletfont = text
  end

  def do_huge(text)
    output_width = @width
    output_width -= 2 if @output_env
    op = IO.popen("figlet -f #{@figletfont} -w #{output_width} -k \"#{text}\"","r")
    op.readlines.each do |line|
      print_line(line)
    end
    op.close
  end

  def print_line(line)
    lines = split_lines(strip_inline_tokens(line),@width)
    lines.each do |l|
      if @output_env then
        @f.puts "| #{l}"
      else
        @f.puts "#{l}"
      end
    end
  end

  def do_center(text)
    lines = split_lines(strip_inline_tokens(text),@width)
    lines.each do |line|
      spaces = (@width - line.length) / 2
      spaces = 0 if spaces < 0
      spaces.times { line = " " + line }
      print_line(line)
    end
  end

  def do_right(text)
    lines = split_lines(strip_inline_tokens(text),@width)
    lines.each do |line|
      spaces = @width - line.length
      spaces = 0 if spaces < 0
      spaces.times { line = " " + line }
      print_line(line)
    end
  end

  def do_title(title)
    @f.puts "Title: #{strip_inline_tokens(title)}"
    @title = true
    if @title and @author and @date then
      @f.puts "\n\n"
    end
  end

  def do_author(author)
    @f.puts "Author: #{strip_inline_tokens(author)}"
    @author = true
    if @title and @author and @date then
      @f.puts "\n\n"
    end
  end

  def do_date(date)
    @f.puts "Date: #{strip_inline_tokens(date)}"
    @date = true
    if @title and @author and @date then
      @f.puts "\n\n"
    end
  end

  def do_bgcolor(color)
  end

  def do_fgcolor(color)
  end

  def do_color(color)
  end

  def close
    @f.close
  end

end

# Implements a non-interactive controller to control non-interactive
# visualizers (i.e. those that are used for converting TPP source code into
# another format)
class ConversionController < TppController

  def initialize(input,output,visualizer_class)
    parser = FileParser.new(input)
    @pages = parser.get_pages
    @vis = visualizer_class.new(output)
  end

  def run
    @pages.each do |p|
      begin
        line = p.next_line
        eop = p.eop?
        @vis.visualize(line)
      end while not eop
    end
  end

  def close
    @vis.close
  end

end

# Prints a nicely formatted usage message.
def usage
  $stderr.puts "usage: #{$0} [-t <type> -o <file>] <file>\n"
  $stderr.puts "\t -t <type>\tset filetype <type> as output format"
  $stderr.puts "\t -o <file>\twrite output to file <file>"
  $stderr.puts "\t -s <seconds>\twait <seconds> seconds between slides (with -t autoplay)"
  $stderr.puts "\t --version\tprint the version"
  $stderr.puts "\t --help\t\tprint this help"
  $stderr.puts "\n\t currently available types: ncurses (default), autoplay, latex, txt"
  Kernel.exit(1)
end



################################
# Here starts the main program #
################################

input = nil
output = nil
type = "ncurses"
time = 1

skip_next = false

ARGV.each_index do |i|
  if skip_next then
    skip_next = false
  else
    if ARGV[i] == '-v' or ARGV[i] == '--version' then
      printf "tpp - text presentation program %s\n", version_number
      Kernel.exit(1)
    elsif ARGV[i] == '-h' or ARGV[i] == '--help' then
      usage
    elsif ARGV[i] == '-t' then
      type = ARGV[i+1]
      skip_next = true
    elsif ARGV[i] == '-o' then
      output = ARGV[i+1]
      skip_next = true
    elsif ARGV[i] == "-s" then
      time = ARGV[i+1].to_i
      skip_next = true
    elsif input == nil then
      input = ARGV[i]
    end
    if output!=nil and output==input then
      $stderr.puts "Don't use the input file name as the output filename to prevent overwriting it. \n"
      Kernel.exit(1)
    end
  end
end

if input == nil then
  usage
end

ctrl = nil

case type
  when "ncurses"
    load_ncurses
    ctrl = InteractiveController.new(input,NcursesVisualizer)
  when "autoplay"
    load_ncurses
    ctrl = AutoplayController.new(input,time,NcursesVisualizer)
  when "txt"
    if output == nil then
      usage
    else
      ctrl = ConversionController.new(input,output,TextVisualizer)
    end
  when "latex"
    if output == nil then
      usage
    else
      ctrl = ConversionController.new(input,output,LatexVisualizer)
    end
else
  usage
end # case

begin
  ctrl.run
ensure
  ctrl.close
end
