#
# Native AEC module for voice_flutter (spec §9, T18 — optional).
# v1's happy path does not require this podspec at all; it's only consulted
# when an app's build picks up the package's ios/ directory, which only
# happens once a consuming app actually links against it.
#
Pod::Spec.new do |s|
  s.name             = 'voice_flutter'
  s.version          = '0.1.0'
  s.summary          = 'Native AEC support for the voice_flutter package.'
  s.description      = <<-DESC
Optional native echo-cancellation mic capture for voice_flutter's full-duplex mode.
                       DESC
  s.homepage         = 'https://github.com/example/voice_ai_sdk'
  s.license          = { :type => 'Unlicensed', :text => 'Private — not yet published.' }
  s.author           = { 'Voice AI SDK' => 'noreply@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
