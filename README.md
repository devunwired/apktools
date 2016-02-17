APK Resource Toolkit
====================
[![Gem Version](https://badge.fury.io/rb/apktools.png)](http://badge.fury.io/rb/apktools)

This repository contains the source code for the `apktools` ruby gem, a set of utilities for parsing resource data out of Android APK files.

This library only contains utility code to read XML and resource data from an APK.  It does not contain utilities to de-dex or otherwise decompile the sources.

Its intended purpose is to assist web applications that need to read basic resource information from APKs that are uploaded in order to manage them (like a private app store).

**This library is not feature complete, feedback is greatly appreciated.  Please submit issues or pull requests for anything you'd like to see added or changed to make this library more useful.**

Installing/Building
========
This library is packaged as a gem, and latest version is hosted on RubyGems.  You can install it directly via:
```
$ gem install apktools
```

You can also build the gem yourself and install it locally:
```
$ gem build apktools.gemspec
$ gem install apktools-x.x.x.gem
```

Usage Examples
==============
ApkXml
------
ApkXml parses any XML file inside an APK, including AndroidManifest.xml, and returns back the fully decoded XML string.  Any resource values encountered will be replaced with the proper keys by calling into ApkResources under the hood.

```ruby
require 'apktools/apkxml'

# Initialize with an APK file
xml = ApkXml.new("MyApplication.apk")

# Pass the name of the XML file to parse.  A string is returned with the result
main_xml = xml.parse_xml("main.xml")

# You can also optionally enable indented (pretty) output,
# and resolving of resource values
manifest_xml = xml.parse_xml("AndroidManifest.xml", true, true)
```

ApkXml can also go beyond reconstructing the original XML file and replace resource references with their values by enabling the `resolve_resources` option on the parser.

For example, let's look at an AndroidManifest.xml that originally looks like this:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
          package="com.apkresource.resourcesample"
          android:versionCode="10"
          android:versionName="@string/app_version">
    <uses-sdk android:minSdkVersion="@string/min_sdk"
        android:targetSdkVersion="@string/min_sdk" />
    <application android:label="@string/app_name"
        android:icon="@drawable/ic_launcher"
        android:theme="@style/Theme.Sample">
        <activity android:name=".MyActivity"
                  android:enabled="@bool/enableSwitch">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
    </application>
</manifest>
```

The parsed result would return like this with `resolve_resources` enabled:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
          package="com.apkresource.resourcesample"
          android:versionCode="10"
          android:versionName="1.1.1">
    <uses-sdk android:minSdkVersion="8"
        android:targetSdkVersion="8" />
    <application android:label="ResourceSample"
        android:icon="@drawable/ic_launcher"
        android:theme="@style/Theme.Sample">
        <activity android:name=".MyActivity"
                  android:enabled="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
        <activity android:name=".MySettingsActivity"
                  android:enabled="@bool/enableSettings" />
    </application>
</manifest>
```

Notice that the app icon resource did not resolve, and this is because (typically) there is no default resource for that value, only qualified resources for each density.  Similarly, the theme did not resolve, because this is a complex resource value that does not fit well into its place here in the XML.

ApkResources
------------
ApkResources parses the `resources.arsc` file inside an APK and provides methods to access the key/value data of the resources within.

Let's say the R.java file from your application looks like this:
```java
public final class R {
    public static final class drawable {
        public static final int ic_launcher=0x7f020000;
        public static final int new_shape=0x7f020001;
        public static final int shape=0x7f020002;
    }
    public static final class string {
        public static final int app_name=0x7f090000;
        public static final int app_version=0x7f090001;
        public static final int min_sdk=0x7f090002;
    }
}

```
Here is a simple example of how ApkResources can be used to resonstruct resource names into XML/Java sources:
```ruby
require 'apktools/apkresources'
require 'apktools/resconfiguration'

# Initialize with an APK file
resources = ApkResources.new("MyApplication.apk")

# Get Resource keys
app_name_key = resources.get_resource_key(0x7F090000)
# app_name_key is now "R.string.app_name"

# Also supports formatting for XML files
app_name_key = resources.get_resource_key(0x7F090000, true)
# app_name_key is now "@string/app_name"

# Dump all keys in the APK
all_keys = resources.get_all_keys
# Dump all strings in the APK
all_strings = resources.get_all_strings
```
You can also read the values of these resources.  Android resources are typed by the configuration that resource is defined for (screen size, density, API version, etc.) so multiple resources may exist for a given key.  ApkResources uses the custom structures `ResTypeConfig` and `ResTypeEntry` to store and return these values.
```ruby
# Read resource values
# Resource values are returned as a ResTypeEntry structure
#  where the value is stored in the :data attribute

# Return the value for the default configuration
#  may be nil if no default resources exists
app_name = resources.get_default_resource_value(0x7F090001).data
# app_name is now "My Application"

# If multiple entries exist for a single key, a hash is returned
#  where each key is the ResTypeConfig representing that resource
app_icons = resources.get_resource_value(0x7F020000)
# Create a configuration for the resource you want.
#  This is for an HDPI icon (min version 4 required for this attribute)
#  Platform constants are defined in the ResConfiguration module.
hdpi_config = ResTypeConfig.new(0, 0,
    ResConfiguration::ACONFIGURATION_DENSITY_HIGH << 16, #HDPI
    0, 0, 4, #Version > 4
    0, 0)
hdpi_icon = app_icons[hdpi_config].data
# hdpi_icon is now "res/drawable-hdpi/ic_launcher.png"

# …or just print them all
app_icons.values.each do |entry|
  puts entry.data
end
```

**For more information on the capabilities of the library, take a look at the RDoc posted in the `doc/` directory of the repository.**

Resource References
-------------------
`apktools` does not automatically follow references links found in resources. Instead, the library will return the resource id of the reference, allowing you to manually follow the reference as far as you like. The following example script recursively traces resource references until a value is found:
```ruby
require 'apktools/apkresources'

## Resolve a resource value, tracing references when necessary
def resolve_resource(resources, res_id)
  res_value = resources.get_default_resource_value(res_id)
  if res_value == nil
    return nil
  elsif res_value.data_type == ApkResources::TYPE_REFERENCE
    #This is a reference, trace it down
    return resolve_resource(resources, res_value.data)
  else
    return [res_value.key,res_value.data]
  end
end

# Read resource information out of the given APK
# Returns the initial resource key, and final resource key/value pair
# The above will be different if the initial resource contains a reference

if ARGV.length != 2
  puts "usage: ref_test <APKFile> <ResId>"
  exit(1)
end

apk_file = ARGV[0]
res_id = ARGV[1]

# Load the XML data
# Initialize with an APK file
resources = ApkResources.new(apk_file)

# Get Resource key
res_key = resources.get_resource_key(res_id)

# Get Resource value (ResTypeEntry struct)
res_value = resolve_resource(resources, res_id)
if res_value == nil
  puts "No resource found for #{res_id}"
else
  puts [res_key,res_value]
end
```

Utilities
=========

This gem also currently contains the following binary utility scripts:

* `get_app_version.rb`: Read the versionName and versionCode attributes out of AndroidManifest.xml; resolving any resource references if necessary.
* `read_manifest.rb`: Parse the AndroidManifest.xml file from the APK and write the formatted XML to an output file.

Planned Work
============
The following items are known features that this library still expects to implement in the future
- Add support for styled strings
- Add support for values of complex resources (attrs, ids, styles)
- Add errors/exceptions for invalid file conditions
- Add support for passing configuration specs to the parser for resolving resources

Acknowledgements
================
Many thanks to the work of Simon Lewis for deconstructing much of the parsing code located in the AOSP.  This greatly reduced the effort required to consolidate all this into a single library.

License
=======
This library is open sourced under the terms of the MIT License
