# Copyright (C) 2014 Dave Smith
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of this
# software and associated documentation files (the "Software"), to deal in the Software
# without restriction, including without limitation the rights to use, copy, modify,
# merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit
# persons to whom the Software is furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all copies
# or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
# INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
# PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE
# FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
# OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
# DEALINGS IN THE SOFTWARE.

require 'zip'

##
# Class to parse an APK's resources.arsc data and retrieve resource
# data associated with a given R.id value
class ApkResources

  DEBUG = false # :nodoc:

  ##
  # Structure defining the type and size of each resource chunk
  #
  # ChunkHeader = Struct.new(:type, :size, :chunk_size)
  ChunkHeader = Struct.new(:type, :size, :chunk_size)

  ##
  # Structure that houses a group of strings
  #
  # StringPool = Struct.new(:header, :string_count, :style_count, :values)
  #
  # * +header+ = ChunkHeader
  # * +string_count+ = Number of normal strings in the pool
  # * +style_count+ = Number of styled strings in the pool
  # * +values+ = Array of the string values
  StringPool = Struct.new(:header, :string_count, :style_count, :values)

  ##
  # Structure defining the data inside of the package chunk
  #
  # PackageHeader = Struct.new(:header, :id, :name, :type_strings, :key_strings)
  #
  # * +header+ = ChunkHeader
  # * +id+ = Package id; usually 0x7F for application resources
  # * +name+ = Package name (e.g. "com.example.application")
  # * +type_strings+ = Array of the type string values present (e.g. "drawable")
  # * +key_strings+ = Array of the key string values present (e.g. "ic_launcher")
  PackageHeader = Struct.new(:header, :id, :name, :type_strings, :key_strings)

  ##
  # Structure defining the resource contents for a package chunk
  #
  # Package = Struct.new(:header, :stringpool_typestrings, :stringpool_keystrings, :type_data)
  #
  # * +package_header+ = PackageHeader
  # * +stringpool_typestrings+ = StringPool containing all type strings in the package
  # * +stringpool_keystrings+ = StringPool containing all key strings in the package
  # * +type_data+ = Array of ResTypeSpec chunks in the package
  Package = Struct.new(:package_header, :stringpool_typestrings, :stringpool_keystrings, :type_data)

  ##
  # Structure defining the flags for a block of common resources
  #
  # ResTypeSpec = Struct.new(:header, :id, :entry_count, :entries, :types)
  #
  # * +header+ = ChunkHeader
  # * +id+ = String value of the referenced type (e.g. "drawable")
  # * +entry_count+ = Number of type entries in this chunk
  # * +entries+ = Array of config flags for each type entry
  # * +types+ = The ResType associated with this spec
  ResTypeSpec = Struct.new(:header, :id, :entry_count, :entries, :types)

  ##
  # Structure that houses all the resources for a given type
  #
  # ResType = Struct.new(:header, :id, :config, :entry_count, :entries)
  #
  # * +header+ = ChunkHeader
  # * +id+ = String value of the referenced type (e.g. "drawable")
  # * +config+ = ResTypeConfig defining the configuration for this type
  # * +entry_count+ = Number of entries in this chunk
  # * +entries+ = Array of Hashes of [ResTypeConfig, ResTypeEntry] in this chunk
  ResType = Struct.new(:header, :id, :config, :entry_count, :entries)

  ##
  # Structure that houses the configuration flags for a given resource.
  #
  # ResTypeConfig = Struct.new(:imsi, :locale, :screen_type, :input, :screen_size, :version, :screen_config, :screen_size_dp)
  #
  # * +imsi+ = Flags marking country code and network code
  # * +locale+ = Flags marking locale requirements (language)
  # * +screen_type+ = Flags/values for screen density
  # * +input+ = Flags marking input types and visibility status
  # * +screen_size+ = Flags marking screen size and length
  # * +version+ = Minimum API version
  # * +screen_config+ = Flags marking screen configuration (like orientation)
  # * +screen_size_dp+ = Flags marking smallest width constraints
  #
  # A default configuration is defined as ResTypeConfig.new(0, 0, 0, 0, 0, 0, 0, 0)
  ResTypeConfig = Struct.new(:imsi, :locale, :screen_type, :input, :screen_size, :version, :screen_config, :screen_size_dp)

  ##
  # Structure that houses the data for a given resource entry
  #
  # ResTypeEntry = Struct.new(:flags, :key, :data_type, :data)
  #
  # * +flags+ = Flags marking if the resource is complex or public
  # * +key+ = Key string for the resource (e.g. "ic_launcher" of R.drawable.ic_launcher")
  # * +data_type+ = Type identifier.  The meaning of this value varies with the type of resource
  # * +data+ = Resource value (e.g. "res/drawable/ic_launcher" for R.drawable.ic_launcher")
  #
  # A single resource key can have multiple entries depending on configuration, so these structs
  # are often returned in groups, keyed by a ResTypeConfig
  ResTypeEntry = Struct.new(:flags, :key, :data_type, :data)

  # PackageHeader containing information about all the type and key strings in the package
  attr_reader :package_header
  # StringPool containing all value strings in the package
  attr_reader :stringpool_main
  # Hash of Package chunks, keyed by package id
  attr_reader :packages

  ##
  # Create a new ApkResources instance from the specified +apk_file+
  #
  # This opens and parses the contents of the APK's resources.arsc file.
  def initialize(apk_file)
    data = nil
    Zip.warn_invalid_date = false

    # Get resources.arsc from the APK file
    Zip::File.foreach(apk_file) do |f|
      if f.name.match(/resources.arsc/)
        data = f.get_input_stream.read.force_encoding('BINARY')
      end
    end

    # Parse the Table Chunk
    ## Header
    header_type = read_short(data, HEADER_START)
    header_size = read_short(data, HEADER_START+2)
    header_chunk_size = read_word(data, HEADER_START+4)
    header_package_count = read_word(data, HEADER_START+8)
    puts "Resource Package Count = #{header_package_count}" if DEBUG

    # Parse the StringPool Chunk
    ## Header
    startoffset_pool = HEADER_START + header_size
    puts "Parse Main StringPool Chunk" if DEBUG
    @stringpool_main = parse_stringpool(data, startoffset_pool)
    puts "#{@stringpool_main.values.length} strings found" if DEBUG

    # Parse the Package Chunk
    ## Header
    startoffset_package = startoffset_pool + @stringpool_main.header.chunk_size
    @packages = Hash.new()
    i = 0
    while i < header_package_count
      package_element = parse_package(data, startoffset_package)
      puts "Package #{package_element.package_header.id}" if DEBUG
      startoffset_package = startoffset_package + package_element.package_header.header.chunk_size
      @packages[package_element.package_header.id] = package_element

      i += 1
    end

  end #initalize

  ##
  # Return array of all string values in the file

  def get_all_strings
    return @stringpool_main.values
  end

  ##
  # Return hash of all the type values in the file
  # keyed by package id

  def get_all_types
    types = Hash.new()
    @packages.each do |key, value|
      types[key] = value.stringpool_typestrings.values
    end

    return types
  end

  ##
  # Return hash of all the key values in the file
  # keyed by package id

  def get_all_keys
    keys = Hash.new()
    @packages.each do |key, value|
      keys[key] = value.stringpool_keystrings.values
    end

    return keys
  end

  ##
  # Obtain the key value for a given resource id
  #
  # res_id: ID value of a resource as a FixNum or String representation (i.e. 0x7F060001)
  # xml_format: Optionally format return string for XML files.
  #
  # If xml_format is true, return value will be @<type>/<key>
  # If xml_format is false or missing, return value will be R.<type>.<key>
  # If the resource id does not exist, return value will be nil

  def get_resource_key(res_id, xml_format=false)
    if res_id.is_a? String
      res_id = res_id.hex
    end

    # R.id integers are a concatenation of package_id, type_id, and entry index
    res_package = (res_id >> 24) & 0xFF
    res_type = (res_id >> 16) & 0xFF
    res_index = res_id & 0xFFFF

    package_element = @packages[res_package]
    if package_element == nil
      # This is not a resource we can parse
      return nil
    end

    res_spec = package_element.type_data[res_type-1]
    if res_spec == nil
      puts "Could not find ResTypeSpec for #{res_package} #{res_type}" if DEBUG
      return nil
    end

    entry = res_spec.types.entries[res_index]
    if entry == nil
      # There is no entry in our table for this resource
      puts "Could not find #{res_spec.types.id} ResType chunk" if DEBUG
      return nil
    end

    if xml_format
      return "@#{res_spec.id}/#{entry.values[0].key}"
    else
      return "R.#{res_spec.id}.#{entry.values[0].key}"
    end
  end

  ##
  # Obtain the default value for a given resource id
  #
  # res_id: ID values of a resources as a FixNum or String representation (i.e. 0x7F060001)
  #
  # Returns: The default ResTypeEntry to the given id, or nil if no default exists

  def get_default_resource_value(res_id)
    if res_id.is_a? String
      res_id = res_id.hex
    end

    entries = get_resource_value(res_id)
    if entries != nil
      default = ResTypeConfig.new(0, 0, 0, 0, 0, 0, 0, 0)
      default_entry = entries[default]
      return default_entry
    else
      return nil
    end
  end

  ##
  # Obtain the value(s) for a given resource id.
  # A default resource is one defined in an unqualified directory.
  #
  # res_id: ID value of a resource as a FixNum or String representation (i.e. 0x7F060001)
  #
  # Returns: Hash of all entries matching this id, keyed by their matching ResTypeConfig
  # or nil if the resource id cannot be found.

  def get_resource_value(res_id)
    if res_id.is_a? String
      res_id = res_id.hex
    end

    # R.id integers are a concatenation of package_id, type_id, and entry index
    res_package = (res_id >> 24) & 0xFF
    res_type = (res_id >> 16) & 0xFF
    res_index = res_id & 0xFFFF

    package_element = @packages[res_package]
    if package_element == nil
      # This is not a resource we can parse
      return nil
    end

    res_spec = package_element.type_data[res_type-1]
    if res_spec == nil
      puts "Could not find ResTypeSpec for #{res_package} #{res_type}" if DEBUG
      return nil
    end

    entries = res_spec.types.entries[res_index]
    if entries == nil
      puts "Could not find #{res_spec.types.id} ResType chunk" if DEBUG
      return nil
    end

    return entries
  end

  private # Private Helper Methods

  # Type Constants
  TYPENAME_ARRAY = "array" # :nodoc:
  TYPENAME_ATTRIBUTE = "attr" # :nodoc:
  TYPENAME_BOOLEAN = "bool" # :nodoc:
  TYPENAME_COLOR = "color" # :nodoc:
  TYPENAME_DIMENSION = "dimen" # :nodoc:
  TYPENAME_DRAWABLE = "drawable" # :nodoc:
  TYPENAME_FRACTION = "fraction" # :nodoc:
  TYPENAME_INTEGER = "integer" # :nodoc:
  TYPENAME_LAYOUT = "layout" # :nodoc:
  TYPENAME_PLURALS = "plurals" # :nodoc:
  TYPENAME_STRING = "string" # :nodoc:
  TYPENAME_STYLE = "style" # :nodoc:

  # Data Type Constants (mirrors ResourceTypes.h)
  TYPE_NULL = 0x0 # :nodoc:
  TYPE_REFERENCE = 0x1 # :nodoc:
  TYPE_ATTRIBUTE = 0x2 # :nodoc:
  TYPE_STRING = 0x3 # :nodoc:
  TYPE_FLOAT = 0x4 # :nodoc:
  TYPE_DIMENSION = 0x5 # :nodoc:
  TYPE_FRACTION = 0x6 # :nodoc:
  TYPE_DYNAMIC_DIMEN = 0x7 # :nodoc:
  TYPE_INT_DEC = 0x10 # :nodoc:
  TYPE_INT_HEX = 0x11 # :nodoc:
  TYPE_BOOL = 0x12 # :nodoc:

  TYPE_INT_COLOR_ARGB8 = 0x1C # :nodoc:
  TYPE_INT_COLOR_RGB8 = 0x1D # :nodoc:
  TYPE_INT_COLOR_ARGB4 = 0x1E # :nodoc:
  TYPE_INT_COLOR_RGB4 = 0x1F # :nodoc:

  COMPLEX_UNIT_PX = 0x0 # :nodoc:
  COMPLEX_UNIT_DIP = 0x1 # :nodoc:
  COMPLEX_UNIT_SP = 0x2 # :nodoc:
  COMPLEX_UNIT_PT = 0x3 # :nodoc:
  COMPLEX_UNIT_IN = 0x4 # :nodoc:
  COMPLEX_UNIT_MM = 0x5 # :nodoc:

  COMPLEX_UNIT_FRACTION = 0x0 # :nodoc:
  COMPLEX_UNIT_FRACTION_PARENT = 0x1 # :nodoc:

  # Data Constants
  TYPE_BOOL_TRUE = 0xFFFFFFFF # :nodoc:
  TYPE_BOOL_FALSE = 0x00000000 # :nodoc:

  # Header Constants
  CHUNKTYPE_TYPESPEC = 0x202 # :nodoc:
  CHUNKTYPE_TYPE = 0x201 # :nodoc:
  CHUNKTYPE_PACKAGE = 0x200 # :nodoc:

  #Flag Constants
  FLAG_UTF8 = 0x100 # :nodoc:
  FLAG_COMPLEX = 0x0001 # :nodoc:
  FLAG_PUBLIC = 0x0002 # :nodoc:

  OFFSET_NO_ENTRY = 0xFFFFFFFF # :nodoc:
  HEADER_START = 0 # :nodoc:

  # Read a 32-bit word from a specific location in the data
  def read_word(data, offset)
    out = data[offset,4].unpack('V').first rescue 0
    return out
  end

  # Read a 16-bit short from a specific location in the data
  def read_short(data, offset)
    out = data[offset,2].unpack('v').first rescue 0
    return out
  end

  # Read a 8-bit byte from a specific location in the data
  def read_byte(data, offset)
    out = data[offset,1].unpack('C').first rescue 0
    return out
  end

  # Read in length bytes in as a String
  def read_string(data, offset, length, encoding)
    if "UTF-16".casecmp(encoding) == 0
      out = data[offset, length].unpack('v*').pack('U*')
    else
      out = data[offset, length].unpack('C*').pack('U*')
    end
    return out
  end

  # Return id as a hex string
  def res_id_to_s(res_id)
    return "0x#{res_id.to_s(16)}"
  end

  # Parse out a StringPool chunk
  def parse_stringpool(data, offset)
    pool_header = ChunkHeader.new( read_short(data, offset),
        read_short(data, offset+2),
        read_word(data, offset+4) )

    pool_string_count = read_word(data, offset+8)
    pool_style_count = read_word(data, offset+12)
    pool_flags = read_word(data, offset+16)
    format_utf8 = (pool_flags & FLAG_UTF8) != 0
    puts 'StringPool format is %s' % [format_utf8 ? "UTF-8" : "UTF-16"] if DEBUG

    pool_string_offset = read_word(data, offset+20)
    pool_style_offset = read_word(data, offset+24)

    values = Array.new()
    i = 0
    while i < pool_string_count
      # Read the string value
      index = i * 4 + (offset+28)
      offset_addr = pool_string_offset + offset + read_word(data, index)
      if format_utf8
        length = read_byte(data, offset_addr)
        if (length & 0x80) != 0
          length = ((length & 0x7F) << 8) + read_byte(data, offset_addr+1)
        end

        values << read_string(data, offset_addr + 2, length, "UTF-8")
      else
        length = read_short(data, offset_addr)
        if (length & 0x8000) != 0
          #There is one more length value before the data
          length = ((length & 0x7FFF) << 16) + read_short(data, offset_addr+2)
          values << read_string(data, offset_addr + 4, length * 2, "UTF-16")
        else
          # Read the data
          values << read_string(data, offset_addr + 2, length * 2, "UTF-16")
        end
      end

      i += 1
    end

    return StringPool.new(pool_header, pool_string_count, pool_style_count, values)
  end

  # Parse out a Package Chunk
  def parse_package(data, offset)
    header = ChunkHeader.new( read_short(data, offset),
        read_short(data, offset+2),
        read_word(data, offset+4) )

    package_id = read_word(data, offset+8)
    package_name = read_string(data, offset+12, 256, "UTF-8")
    package_type_strings = read_word(data, offset+268)
    package_last_type = read_word(data, offset+272)
    package_key_strings = read_word(data, offset+276)
    package_last_key = read_word(data, offset+280)

    package_header = PackageHeader.new(header, package_id, package_name, package_type_strings, package_key_strings)

    ## typeStrings StringPool
    startoffset_typestrings = offset + package_type_strings
    puts "Parse typeStrings StringPool Chunk" if DEBUG
    stringpool_typestrings = parse_stringpool(data, startoffset_typestrings)

    ## keyStrings StringPool
    startoffset_keystrings = offset + package_key_strings
    puts "Parse keyStrings StringPool Chunk" if DEBUG
    stringpool_keystrings = parse_stringpool(data, startoffset_keystrings)

    ## typeSpec/type Chunks
    type_data = Array.new()
    current_spec = nil

    current = startoffset_keystrings + stringpool_keystrings.header.chunk_size
    puts "Parse Type/TypeSpec Chunks" if DEBUG
    while current < data.length
      ## Parse Header
      header = ChunkHeader.new( read_short(data, current),
          read_short(data, current+2),
          read_word(data, current+4) )
      ## Check Type
      if header.type == CHUNKTYPE_TYPESPEC
        typespec_id = read_byte(data, current+8)
        typespec_entrycount = read_word(data, current+12)

        ## Parse the config flags for each entry
        typespec_entries = Array.new()
        i=0
        while i < typespec_entrycount
          offset = i * 4 + (current+16)
          typespec_entries << read_word(data, offset)

          i += 1
        end

        typespec_name = stringpool_typestrings.values[typespec_id - 1]
        current_spec = ResTypeSpec.new(header, typespec_name, typespec_entrycount, typespec_entries, nil)

        type_data << current_spec
        current += header.chunk_size
      elsif header.type == CHUNKTYPE_TYPE
        type_id = read_byte(data, current+8)
        type_entrycount = read_word(data, current+12)
        type_entryoffset = read_word(data, current+16)

        ## The config flags set for this type chunk
        ## TODO: Vary the size of the config structure based on size to accomodate for new flags
        config_start = current+20
        config_size = read_word(data, config_start) # Number of bytes in structure
        type_config = ResTypeConfig.new( read_word(data, config_start+4),
            read_word(data, config_start+8),
            read_word(data, config_start+12),
            read_word(data, config_start+16 ),
            read_word(data, config_start+20),
            read_word(data, config_start+24),
            read_word(data, config_start+28),
            read_word(data, config_start+32) )
        ## TODO: This config structure is outdated. Update to latest aapt specs.

        ## The end of the config structure marks the offsets table
        offset_table_start = config_start + config_size
        ## The remainder of the chunk is a list of the entry values for that type/configuration
        type_name = stringpool_typestrings.values[type_id - 1]
        if current_spec.types == nil
          current_spec.types = ResType.new(header, type_name, type_config, type_entrycount, Array.new())
        end

        i=0
        while i < type_entrycount
          ## Ensure a hash exists for each type
          if current_spec.types.entries[i] == nil
            current_spec.types.entries[i] = Hash.new()
          end
          current_entry = current_spec.types.entries[i]

          ## Get the start of the type from the offsets table
          index_offset = i * 4 + offset_table_start
          start_offset = read_word(data, index_offset)
          if start_offset != OFFSET_NO_ENTRY
            ## Set the index_offset to the start of the current entry
            index_offset = current + type_entryoffset + start_offset

            entry_flags = read_short(data, index_offset+2)
            entry_key = read_word(data, index_offset+4)
            entry_data_type = read_byte(data, index_offset+11)
            entry_data = read_word(data, index_offset+12)

            # Find the key in our strings index
            key_name = stringpool_keystrings.values[entry_key]
            # Parse the value into a string
            case entry_data_type
              when TYPE_NULL
                data_value = nil
              when TYPE_REFERENCE
                ## TODO: Mark these here, and resolve after package is parsed
                data_value = res_id_to_s(entry_data)
              when TYPE_STRING
                data_value = get_resource_string(entry_data_type, entry_data)
              when TYPE_INT_COLOR_ARGB8..TYPE_INT_COLOR_RGB4
                data_value = get_resource_color(entry_data_type, entry_data)
              when TYPE_DIMENSION
                data_value = get_resource_dimension(entry_data_type, entry_data)
              when TYPE_INT_DEC, TYPE_INT_HEX
                data_value = get_resource_integer(entry_data_type, entry_data)
              when TYPE_BOOL
                data_value = get_resource_bool(entry_data_type, entry_data)
              when TYPE_FLOAT
                data_value = get_resource_float(entry_data_type, entry_data)
              when TYPE_FRACTION
                data_value = get_resource_fraction(entry_data_type, entry_data)
              else
                puts "Complex Resource (%s,%d) not yet supported." % [type_name,entry_data_type] if DEBUG
                data_value = entry_data.to_s
            end
            current_entry[type_config] = ResTypeEntry.new(entry_flags, key_name, entry_data_type, data_value)
          end
          i += 1
        end

        current += header.chunk_size
      elsif header.type == CHUNKTYPE_PACKAGE
        ## This is the next package chunk, move along
        puts "Next Package Chunk Found...Ending" if DEBUG
        current = data.length
      else
        puts "Unknown Chunk Found: #{header.type} #{header.size}" if DEBUG
        ## End Immediately
        current = data.length
      end
    end

    return Package.new(package_header, stringpool_typestrings, stringpool_keystrings, type_data)
  end

  # Obtain string value for resource id
  def get_resource_string(entry_datatype, entry_data)
    result = @stringpool_main.values[entry_data]
    return result
  end

  # Obtain boolean value for resource id
  def get_resource_bool(entry_datatype, entry_data)
    if entry_data == TYPE_BOOL_TRUE
      return "true"
    elsif entry_data == TYPE_BOOL_FALSE
      return "false"
    else
      return "undefined"
    end
  end

  # Obtain integer value for resource id
  def get_resource_integer(entry_datatype, entry_data)
    if entry_datatype == TYPE_INT_HEX
      return "0x#{entry_data.to_s(16)}"
    else
      return entry_data.to_s
    end
  end

  # Obtain color value for resource id
  def get_resource_color(entry_datatype, entry_data)
    case entry_datatype
    when TYPE_INT_COLOR_RGB4
      return "#" + ((entry_data >> 16) & 0xF).to_s(16) + ((entry_data >> 8) & 0xF).to_s(16) + (entry_data & 0xF).to_s(16)
    when TYPE_INT_COLOR_ARGB4
      return "#" + ((entry_data >> 24) & 0xF).to_s(16) + ((entry_data >> 16) & 0xF).to_s(16) + ((entry_data >> 8) & 0xF).to_s(16) + (entry_data & 0xF).to_s(16)
    when TYPE_INT_COLOR_RGB8
      return "#" + ((entry_data >> 16) & 0xFF).to_s(16) + ((entry_data >> 8) & 0xFF).to_s(16) + (entry_data & 0xFF).to_s(16)
    when TYPE_INT_COLOR_ARGB8
      return "#" + ((entry_data >> 24) & 0xFF).to_s(16) + ((entry_data >> 16) & 0xFF).to_s(16) + ((entry_data >> 8) & 0xFF).to_s(16) + (entry_data & 0xFF).to_s(16)
    else
      return "0x#{entry_data.to_s(16)}"
    end
  end


  # Obtain a float value for resource id
  def get_resource_float(entry_data_type, entry_data)
    result = [entry_data].pack('I').unpack('F')
    return result[0].to_s
  end

  # Obtain dimension value for resource id
  def get_resource_dimension(entry_datatype, entry_data)
    unit_type = (entry_data & 0xF)
    case unit_type
    when COMPLEX_UNIT_PX
      unit_name = "px"
    when COMPLEX_UNIT_DIP
      unit_name = "dp"
    when COMPLEX_UNIT_SP
      unit_name = "sp"
    when COMPLEX_UNIT_PT
      unit_name = "pt"
    when COMPLEX_UNIT_IN
      unit_name = "in"
    when COMPLEX_UNIT_MM
      unit_name = "mm"
    else
      unit_name = ""
    end

    return complex_to_float(entry_data).to_s + unit_name
    #return ((entry_data >> 8) & 0xFFFFFF).to_s + unit_name
  end

  # Obtain a fraction value for resource id
  def get_resource_fraction(entry_data_type, entry_data)
    unit_type = (entry_data & 0xF)
    case unit_type
    when COMPLEX_UNIT_FRACTION
      unit_name = "%"
    when COMPLEX_UNIT_FRACTION_PARENT
      unit_name = "%p"
    else
      unit_name = ""
    end

    # Return float as a percentage
    return (complex_to_float(entry_data) * 100).to_s + unit_name
  end

  def complex_to_float(complex)
    mantissa_mult = 1.0 / (1 << 8)
    multipliers = [1.0*mantissa_mult, 1.0/(1<<7)*mantissa_mult, 1.0/(1<<15)*mantissa_mult, 1.0/(1<<23)*mantissa_mult]

    mantissa = complex & 0xFFFFFF00
    radix = (complex >> 4) & 0x3

    return (mantissa * multipliers[radix]).to_f.round(4)
  end
end
