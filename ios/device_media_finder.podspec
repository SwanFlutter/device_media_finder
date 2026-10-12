#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint device_media_finder.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'device_media_finder'
  s.version          = '0.2.0'
  s.summary          = 'List device photos and videos of any size/format with full metadata and cached thumbnails.'
  s.description      = <<-DESC
Fast Flutter plugin that lists device media with full per-file metadata,
paginated loading and cached background thumbnails. On iOS it reads the Photos
library (images and videos) via PhotoKit.
                       DESC
  s.homepage         = 'https://github.com/SwanFlutter/device_media_finder'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'SwanFlutter' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'device_media_finder/Sources/device_media_finder/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'device_media_finder_privacy' => ['device_media_finder/Sources/device_media_finder/PrivacyInfo.xcprivacy']}
end
