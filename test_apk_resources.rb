#!/usr/bin/env ruby
#
# Script to test APKResources development
#

require 'rubygems'
require 'zip/zip'
require 'apktools/apkresources'

# Begin Script
if ARGV.length != 1
	puts "APK Test"
	puts "usage: test_apk_resources <APKFile>"
	exit(1)
end

data = nil

# Get just the AndroidManifest.xml from the APK file
Zip::ZipFile.foreach(ARGV[0]) do |f|
  if f.name.match(/AndroidManifest.xml/)
    data = f.get_input_stream.read
  end
end

# Set up resources
resources = ApkResources.new(ARGV[0])

# BOOL
puts "#{resources.get_resource_key(0x7f050001)} = #{resources.get_default_resource_value(0x7f050001).data}"
puts "#{resources.get_resource_key(0x7f050000)} = #{resources.get_default_resource_value(0x7f050000).data}"

# COLOR
puts "#{resources.get_resource_key(0x7f060001)} = #{resources.get_default_resource_value(0x7f060001).data}"
puts "#{resources.get_resource_key(0x7f060003)} = #{resources.get_default_resource_value(0x7f060003).data}"
puts "#{resources.get_resource_key(0x7f060000)} = #{resources.get_default_resource_value(0x7f060000).data}"
puts "#{resources.get_resource_key(0x7f060002)} = #{resources.get_default_resource_value(0x7f060002).data}"

# DIMEN
puts "#{resources.get_resource_key(0x7f070001)} = #{resources.get_default_resource_value(0x7f070001).data}"
puts "#{resources.get_resource_key(0x7f070000)} = #{resources.get_default_resource_value(0x7f070000).data}"

# DRAWABLE
puts "#{resources.get_resource_key(0x7f020000)} = #{resources.get_resource_value(0x7f020000).values}"
puts "#{resources.get_resource_key(0x7f020001)} = #{resources.get_resource_value(0x7f020001).values}"
puts "#{resources.get_resource_key(0x7f020002)} = #{resources.get_resource_value(0x7f020002).values}"

# INTEGER
puts "#{resources.get_resource_key(0x7f080000)} = #{resources.get_default_resource_value(0x7f080000).data}"

# STRING
puts "#{resources.get_resource_key(0x7f090000)} = #{resources.get_default_resource_value(0x7f090000).data}"
puts "#{resources.get_resource_key(0x7f090001)} = #{resources.get_default_resource_value(0x7f090001).data}"
puts "#{resources.get_resource_key(0x7f090002)} = #{resources.get_default_resource_value(0x7f090002).data}"
