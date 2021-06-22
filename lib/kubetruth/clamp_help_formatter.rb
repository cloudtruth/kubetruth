# Hack to make clamp usage less of a pain to get long lines to fit within a
# standard terminal width
class Clamp::Help::Builder

  def word_wrap(text, line_width: 80)
    text.split("\n").collect do |line|
      line.length > line_width ? line.gsub(/(.{1,#{line_width}})(\s+|$)/, "\\1\n").strip.split("\n") : line
    end.flatten
  end

  def string
    indent_size = 4
    indent = " " * indent_size
    StringIO.new.tap do |out|
      lines.each do |line|
        case line
          when Array
            out << indent
            out.puts(line[0])
            formatted_line = line[1].gsub(/\((default|required)/, "\n\\0")
            word_wrap(formatted_line, line_width: (80 - indent_size * 2)).each do |l|
              out << (indent * 2)
              out.puts(l)
            end
          else
            out.puts(line)
        end
      end
    end.string
  end

end
