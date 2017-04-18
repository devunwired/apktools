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
require 'apktools/apkresources'

##
# Class to parse an APK's binary XML format back into textual XML
class ApkXml

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
  # Structure to house mappings of resource ids to strings
  #
  # XmlResourceMap = Struct.new(:header, :ids, :strings)
  #
  # * +header+ = ChunkHeader
  # * +ids+ = Array of resource ids
  # * +strings+ = Matching Array of resource strings
  XmlResourceMap = Struct.new(:header, :ids, :strings)

  ##
  # Structure defining header of an XML node
  #
  # XmlTreeHeader = Struct.new(:header, :line_num, :comment)
  #
  # * +header+ = ChunkHeader
  # * +line_num+ = Line number in original file
  # * +comment+ = Optional comment
  XmlTreeHeader = Struct.new(:header, :line_num, :comment)

  ##
  # Structure defining an XML element
  #
  # XmlElement = Struct.new(:header, :namespace, :name, :id_idx, :class_idx, :style_idx, :attributes, :is_root)
  #
  # * +header+ = XmlTreeHeader
  # * +namespace+ = Namespace prefix of the element
  # * +name+ = Name of the element
  # * +id_idx+ = Index of the attribute that represents the "id" in this element, if any
  # * +class_idx+ = Index of the attribute that represents the "class" in this element, if any
  # * +style_idx+ = Index of the attribute that represents the "style" in this element, if any
  # * +attributes+ = Array of XmlAttribute elements
  # * +is_root+ = Marks if this is the root element
  XmlElement = Struct.new(:header, :namespace, :name, :id_idx, :class_idx, :style_idx, :attributes, :is_root)

  ##
  # Structure defining an XML element's attribute
  #
  # XmlAttribute = Struct.new(:namespace, :name, :raw, :value)
  #
  # * +namespace+ = Namespace prefix of the attribute
  # * +name+ = Name of the attribute
  # * +value+ = Value of the attribute
  XmlAttribute = Struct.new(:namespace, :name, :value)

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

  # APK file where parser will search for XML
  attr_reader :current_apk
  # ApkResources instance used to resolve resources in this APK
  attr_reader :apk_resources
  # Array of XmlElements from the last parse operation
  attr_reader :xml_elements

  ##
  # Create a new ApkXml instance from the specified +apk_file+
  #
  # This opens and parses the contents of the APK's resources.arsc file.
  def initialize(apk_file)
    @current_apk = apk_file
    Zip.warn_invalid_date = false
    @apk_resources = ApkResources.new(apk_file)
  end #initialize

  ##
  # Read the requested XML file from inside the APK and parse out into
  # readable textual XML.  Returns a string of the parsed XML.
  #
  # xml_file: ID value of a resource as a FixNum or String representation (i.e. 0x7F060001)
  # pretty: Optionally format the XML output as human readable
  # resolve_resources: Optionally, where possible, resolve resource references to their default value
  #
  # This opens and parses the contents of the APK's resources.arsc file.
  def parse_xml(xml_file, pretty = false, resolve_resources = false)
    # Reset variables
    @xml_elements = Array.new()
    xml_output = ''
    indent = 0
    data = nil

    Zip.warn_invalid_date = false
    Zip::File.foreach(@current_apk) do |f|
      if f.name.match(xml_file)
        data = f.get_input_stream.read.force_encoding('BINARY')
      end
    end


    # Parse the Header Chunk
    header = ChunkHeader.new( read_short(data, HEADER_START),
        read_short(data, HEADER_START+2),
        read_word(data, HEADER_START+4) )

    # Parse the StringPool Chunk
    startoffset_pool = HEADER_START + header.size
    puts "Parse Main StringPool Chunk" if DEBUG
    stringpool_main = parse_stringpool(data, startoffset_pool)
    puts "#{stringpool_main.values.length} strings found" if DEBUG

    # Parse the remainder of the file chunks based on type
    namespaces = Hash.new()
    current = startoffset_pool + stringpool_main.header.chunk_size
    puts "Parse Remaining Chunks" if DEBUG
    while current < data.length
      ## Parse Header
      header = ChunkHeader.new( read_short(data, current),
          read_short(data, current+2),
          read_word(data, current+4) )
      ## Check Type
      if header.type == TYPE_XML_RESOURCEMAP
        ## Maps resource ids to strings in the pool
        map_ids = Array.new()
        map_strings = Array.new()

        index_offset = current + header.size
        i = 0
        while index_offset < (current + header.chunk_size)
          map_ids << read_word(data, index_offset)
          map_strings << stringpool_main.values[i]

          i += 1
          index_offset = i * 4 + (current + header.size)
        end

        current += header.chunk_size
      elsif header.type == TYPE_XML_STARTNAMESPACE
        tree_header = parse_tree_header(header, data, current)
        body_start = current+header.size
        prefix = stringpool_main.values[read_word(data, body_start)]
        uri = stringpool_main.values[read_word(data, body_start+4)]
        namespaces[uri] = prefix
        puts "NAMESPACE_START: xmlns:#{prefix} = '#{uri}'" if DEBUG
        current += header.chunk_size
      elsif header.type == TYPE_XML_ENDNAMESPACE
        tree_header = parse_tree_header(header, data, current)
        body_start = current+header.size
        prefix = stringpool_main.values[read_word(data, body_start)]
        uri = stringpool_main.values[read_word(data, body_start+4)]
        puts "NAMESPACE_END: xmlns:#{prefix} = '#{uri}'" if DEBUG
        current += header.chunk_size
      elsif header.type == TYPE_XML_STARTELEMENT
        tree_header = parse_tree_header(header, data, current)
        body_start = current+header.size
        # Parse the element/attribute data
        namespace = nil
        if read_word(data, body_start) != OFFSET_NO_ENTRY
          namespace = stringpool_main.values[read_word(data, body_start)]
        end
        name = stringpool_main.values[read_word(data, body_start+4)]

        attribute_offset = read_short(data, body_start+8)
        attribute_size = read_short(data, body_start+10)
        attribute_count = read_short(data, body_start+12)
        id_idx = read_short(data, body_start+14)
        class_idx = read_short(data, body_start+16)
        style_idx = read_short(data, body_start+18)

        attributes = Array.new()
        i=0
        while i < attribute_count
          index_offset = i * attribute_size + (body_start + attribute_offset)
          attr_namespace = nil
          if read_word(data, index_offset) != OFFSET_NO_ENTRY
            attr_uri = stringpool_main.values[read_word(data, index_offset)]
            attr_namespace = namespaces[attr_uri]
          end
          attr_name = stringpool_main.values[read_word(data, index_offset+4)]
          attr_raw = nil
          if read_word(data, index_offset+8) != OFFSET_NO_ENTRY
            # Attribute has a raw value, use it
            attr_raw = stringpool_main.values[read_word(data, index_offset+8)]
          end
          entry = ResTypeEntry.new(0, nil, read_byte(data, index_offset+15), read_word(data, index_offset+16))

          attr_value = nil
          if attr_raw != nil # Use raw value
            attr_value = attr_raw
          elsif entry.data_type == 1 # Value is a references to a resource
            # Find the resource
            default_res = apk_resources.get_default_resource_value(entry.data)
            if resolve_resources && default_res != nil
              # Use the default resource value
              attr_value = default_res.data
            else
              key_value = apk_resources.get_resource_key(entry.data, true)
              if key_value != nil
                # Use the key string
                attr_value = key_value
              else
                #No key found, use raw id marked as a resource
                attr_value = "res:0x#{entry.data.to_s(16)}"
              end
            end
          else # Value is a constant
            attr_value = "0x#{entry.data.to_s(16)}"
          end


          attributes << XmlAttribute.new(attr_namespace, attr_name, attr_value)
          i += 1
        end

        element = XmlElement.new(tree_header, namespace, name, id_idx, class_idx, style_idx, attributes, xml_output == "")

        # Print the element/attribute data
        puts "ELEMENT_START: #{element.namespace} #{element.name}" if DEBUG
        display_name = element.namespace == nil ? element.name : "#{element.namespace}:#{element.name}"

        if pretty
          xml_output += "\n" + ("  " * indent)
          indent += 1
        end
        xml_output += "<#{display_name} "
        # Only print namespaces on the root element
        if element.is_root
          keys = namespaces.keys
          keys.each do |key|
            xml_output += "xmlns:#{namespaces[key]}=\"#{key}\" "
            if pretty && key != keys.last
              xml_output += "\n" + ("  " * indent)
            end
          end
        end

        element.attributes.each do |attr|
          puts "---ATTRIBUTE: #{attr.namespace} #{attr.name} #{attr.value}" if DEBUG
          display_name = attr.namespace == nil ? attr.name : "#{attr.namespace}:#{attr.name}"
          if pretty
            xml_output += "\n" + ("  " * indent)
          end
          xml_output += "#{display_name}=\"#{attr.value}\" "
        end

        xml_output += ">"

        # Push every new element onto the array
        @xml_elements << element

        current += header.chunk_size
      elsif header.type == TYPE_XML_ENDELEMENT
        tree_header = parse_tree_header(header, data, current)
        body_start = current+header.size
        namespace = nil
        if read_word(data, body_start) != OFFSET_NO_ENTRY
          namespace = stringpool_main.values[read_word(data, body_start)]
        end
        name = stringpool_main.values[read_word(data, body_start+4)]

        puts "ELEMENT END: #{namespace} #{name}" if DEBUG
        display_name = namespace == nil ? name : "#{namespace}:#{name}"
        if pretty
          indent -= 1
          if indent < 0
            indent = 0
          end
          xml_output += "\n" + ("  " * indent)
        end
        xml_output += "</#{display_name}>"


        current += header.chunk_size
      elsif header.type == TYPE_XML_CDATA
        tree_header = parse_tree_header(header, data, current)
        body_start = current+header.size

        cdata = stringpool_main.values[read_word(data, body_start)]
        cdata_type = read_word(data, body_start+7)
        cdata_value = read_word(data, body_start+8)
        puts "CDATA: #{cdata} #{cdata_type} #{cdata_value}" if DEBUG

        cdata.split(/\r?\n/).each do |item|
          if pretty
            xml_output += "\n" + ("  " * indent)
          end
          xml_output += "<![CDATA[#{item.strip}]]>"
        end

        current += header.chunk_size
      else
        puts "Unknown Chunk Found: #{header.type} #{header.size}" if DEBUG
        ## End Immediately
        current = data.length
      end
    end

    return xml_output
  end #parse_xml

  private # Private Helper Methods

  #Flag Constants
  FLAG_UTF8 = 0x100 # :nodoc:

  OFFSET_NO_ENTRY = 0xFFFFFFFF # :nodoc:
  HEADER_START = 0 # :nodoc:

  TYPE_XML_RESOURCEMAP = 0x180 # :nodoc:
  TYPE_XML_STARTNAMESPACE = 0x100 # :nodoc:
  TYPE_XML_ENDNAMESPACE = 0x101 # :nodoc:
  TYPE_XML_STARTELEMENT = 0x102 # :nodoc:
  TYPE_XML_ENDELEMENT = 0x103 # :nodoc:
  TYPE_XML_CDATA = 0x104 # :nodoc:

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

  # Parse out an XmlTreeHeader
  def parse_tree_header(chunk_header, data, offset)
    line_num = read_word(data, offset+8)
    comment = nil
    if read_word(data, offset+12) != OFFSET_NO_ENTRY
      comment = stringpool_main.values[read_word(data, offset+12)]
    end
    return XmlTreeHeader.new(chunk_header, line_num, comment)
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

end
