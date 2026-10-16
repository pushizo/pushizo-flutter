Pod::Spec.new do |s|
  s.name             = 'pushizo_flutter'
  s.version          = '0.1.0'
  s.summary          = 'Pushizo Flutter SDK (iOS köprüsü)'
  s.description      = <<-DESC
Pushizo iOS SDK üzerine Flutter MethodChannel/EventChannel köprüsü.
                       DESC
  s.homepage         = 'https://github.com/exec0de/pushizo'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Pushizo' => 'bildirim@pushizo.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  # Uygulama Podfile'ında: pod 'Pushizo', :path => '<repo>/sdk/ios'
  s.dependency 'Pushizo', '~> 0.1'
  s.platform = :ios, '15.0'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.9'
end
