#!/usr/bin/env ruby

# Copyright (C) 2012 Dave Smith
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

require 'apktools/apkxml'

# Read version information out of the given APK
# Returns an array of [versionCode, versionName]

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