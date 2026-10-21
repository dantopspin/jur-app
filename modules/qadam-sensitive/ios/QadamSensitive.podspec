Pod::Spec.new do |s|
  s.name           = 'QadamSensitive'
  s.version        = '1.0.0'
  s.summary        = 'On-device nudity check for chat photos (Apple Sensitive Content Analysis).'
  s.author         = 'Qadam'
  s.homepage       = 'https://qadam.app'
  s.license        = 'MIT'
  s.platforms      = { :ios => '15.1' }
  s.source         = { git: '' }
  s.static_framework = true
  s.dependency 'ExpoModulesCore'
  s.weak_frameworks = 'SensitiveContentAnalysis'
  s.source_files   = '**/*.swift'
end
