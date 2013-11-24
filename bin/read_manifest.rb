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

# Parse AndroidManifest.xml from given APK file and write XML data
# to the given destination

if ARGV.length != 2
	puts "usage: read_manifest <APKFile> <OutFile>"
	exit(1)
end

# Initialize with an APK file
xml = ApkXml.new(ARGV[0])
outfile = ARGV[1]

# You can also optionally enable indented (pretty) output,
# and resolving of resource values
manifest_xml = xml.parse_xml("AndroidManifest.xml", true, true)

File.open(outfile, 'w') { |file| file.write(manifest_xml) }