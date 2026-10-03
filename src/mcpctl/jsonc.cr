module Mcpctl
  # Minimal JSONC handling for Zed's settings.json: comments (`//`, `/* */`)
  # and trailing commas. Works on bytes — every structural character is ASCII,
  # so multi-byte UTF-8 sequences are copied through untouched.
  module Jsonc
    # Replaces the value of a member of the root object, leaving every other
    # byte of the file — comments included — exactly as it was.
    def self.replace_member(text : String, key : String, value : String) : String
      range = member_value_range(text, key) || raise Error.new(%(top-level member "#{key}" not found))
      text.byte_slice(0, range.begin) + value + text.byte_slice(range.end, text.bytesize - range.end)
    end

    # Replaces the member, or appends it as the last member of the root object
    # (a fresh Zed settings.json has no context_servers yet). The comma goes
    # right after the last value, so a comment that follows it stays in place.
    def self.set_member(text : String, key : String, value : String) : String
      return replace_member(text, key, value) if member_value_range(text, key)

      bytes = text.to_slice
      open = skip_blank(bytes, 0)
      raise Error.new("the root of the file is not an object") unless open < bytes.size && bytes[open] == '{'.ord
      close = container_end(bytes, open) - 1
      last = last_token(bytes, open + 1, close) || open

      comma = bytes[last] == '{'.ord || bytes[last] == ','.ord ? "" : ","
      line_start = indent_start(bytes, close, floor: last + 1)
      newline = line_start > 0 && bytes[line_start - 1] == '\n'.ord ? "" : "\n"

      String.build do |io|
        io.write(bytes[0, last + 1])
        io << comma
        io.write(bytes[last + 1, line_start - last - 1])
        io << newline << "  " << key.to_json << ": " << value << "\n"
        io.write(bytes[close, bytes.size - close])
      end
    end

    def self.parse(text : String) : JSON::Any
      JSON.parse(strip(text))
    end

    # Comments become blanks, trailing commas are dropped, strings are kept verbatim.
    def self.strip(text : String) : String
      bytes = text.to_slice
      out = IO::Memory.new(bytes.size)
      i = 0
      while i < bytes.size
        c = bytes[i]
        if c == '"'.ord
          j = string_end(bytes, i)
          out.write(bytes[i, j - i])
          i = j
        elsif comment_start?(bytes, i)
          i = comment_end(bytes, i)
          out << ' '
        elsif c == ','.ord && closer?(bytes, skip_blank(bytes, i + 1))
          i += 1
        else
          out.write_byte(c)
          i += 1
        end
      end
      out.to_s
    end

    private def self.member_value_range(text : String, key : String) : Range(Int32, Int32)?
      bytes = text.to_slice
      depth = 0
      i = 0
      while i < bytes.size
        c = bytes[i]
        if c == '"'.ord
          start = i
          i = string_end(bytes, i)
          next unless depth == 1

          colon = skip_blank(bytes, i)
          next unless colon < bytes.size && bytes[colon] == ':'.ord
          next unless text.byte_slice(start + 1, i - start - 2) == key

          value_start = skip_blank(bytes, colon + 1)
          return value_start...value_end(bytes, value_start)
        elsif comment_start?(bytes, i)
          i = comment_end(bytes, i)
        else
          depth += 1 if c == '{'.ord || c == '['.ord
          depth -= 1 if c == '}'.ord || c == ']'.ord
          i += 1
        end
      end
      nil
    end

    # Index just past the closing quote of the string starting at `i`.
    private def self.string_end(bytes : Bytes, i : Int32) : Int32
      i += 1
      while i < bytes.size
        case bytes[i]
        when '\\'.ord then i += 2
        when '"'.ord  then return i + 1
        else               i += 1
        end
      end
      raise Error.new("unterminated string")
    end

    private def self.comment_start?(bytes : Bytes, i : Int32) : Bool
      bytes[i] == '/'.ord && i + 1 < bytes.size && (bytes[i + 1] == '/'.ord || bytes[i + 1] == '*'.ord)
    end

    private def self.comment_end(bytes : Bytes, i : Int32) : Int32
      if bytes[i + 1] == '/'.ord
        i += 2
        while i < bytes.size && bytes[i] != '\n'.ord
          i += 1
        end
        i
      else
        i += 2
        while i + 1 < bytes.size && !(bytes[i] == '*'.ord && bytes[i + 1] == '/'.ord)
          i += 1
        end
        raise Error.new("unterminated block comment") if i + 1 >= bytes.size
        i + 2
      end
    end

    # Skips whitespace and comments.
    private def self.skip_blank(bytes : Bytes, i : Int32) : Int32
      while i < bytes.size
        if bytes[i].unsafe_chr.ascii_whitespace?
          i += 1
        elsif comment_start?(bytes, i)
          i = comment_end(bytes, i)
        else
          break
        end
      end
      i
    end

    # Start of the spaces and tabs that precede `i`, never before `floor`: where
    # a line inserted before the closing brace begins.
    private def self.indent_start(bytes : Bytes, i : Int32, floor : Int32) : Int32
      while i > floor && (bytes[i - 1] == ' '.ord || bytes[i - 1] == '\t'.ord)
        i -= 1
      end
      i
    end

    # Index of the last byte of the last token in `from...to`, comments and
    # blanks skipped; nil when there is none.
    private def self.last_token(bytes : Bytes, from : Int32, to : Int32) : Int32?
      last = nil
      i = from
      while i < to
        c = bytes[i]
        if c == '"'.ord
          i = string_end(bytes, i)
          last = i - 1
        elsif comment_start?(bytes, i)
          i = comment_end(bytes, i)
        elsif c == '{'.ord || c == '['.ord
          i = container_end(bytes, i)
          last = i - 1
        elsif c.unsafe_chr.ascii_whitespace?
          i += 1
        else
          last = i
          i += 1
        end
      end
      last
    end

    private def self.closer?(bytes : Bytes, i : Int32) : Bool
      i < bytes.size && (bytes[i] == '}'.ord || bytes[i] == ']'.ord)
    end

    # Index just past the value starting at `i`: a string, a nested object or
    # array, or a scalar running up to the next separator.
    private def self.value_end(bytes : Bytes, i : Int32) : Int32
      c = bytes[i]
      return string_end(bytes, i) if c == '"'.ord
      return container_end(bytes, i) if c == '{'.ord || c == '['.ord

      while i < bytes.size && !scalar_end?(bytes[i])
        i += 1
      end
      i
    end

    # Index just past the object or array opening at `i`, strings and comments skipped.
    private def self.container_end(bytes : Bytes, i : Int32) : Int32
      depth = 0
      while i < bytes.size
        b = bytes[i]
        if b == '"'.ord
          i = string_end(bytes, i)
        elsif comment_start?(bytes, i)
          i = comment_end(bytes, i)
        else
          depth += 1 if b == '{'.ord || b == '['.ord
          depth -= 1 if b == '}'.ord || b == ']'.ord
          i += 1
          return i if depth == 0
        end
      end
      raise Error.new("unterminated value")
    end

    private def self.scalar_end?(byte : UInt8) : Bool
      {',', '}', ']'}.includes?(byte.unsafe_chr) || byte.unsafe_chr.ascii_whitespace?
    end
  end
end
