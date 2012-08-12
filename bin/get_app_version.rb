#!/usr/bin/env ruby
#
# Read version information out of the given APK
# Returns an array of [versionCode, versionName]

require 'apktools/apkxml'

if ARGV.length != 1
	puts "usage: get_app_version <APKFile>"
	exit(1)
end

apk_file = ARGV[0]

# Load the XML data
parser = ApkXml.new(apk_file)
parser.parse_xml("AndroidManifest.xml", false, true)

elements = parser.xml_elements

versionCode = nil
versionName = nil

elements.each do |element|
	if element.name != "manifest"
		next
	end
	

	element.attributes.each do |attr|
		if attr.name == "versionCode"
			versionCode = attr.value
		elsif attr.name == "versionName"
			versionName = attr.value
		end
	end
end

puts [versionCode, versionName]