# Uncomment this line to define a global platform for your project
source 'https://mirrors.tuna.tsinghua.edu.cn/git/CocoaPods/Specs.git'
platform :osx, '14.0'
inhibit_all_warnings!

target 'ShadowsocksX-NG' do
  # Comment this line if you're not using Swift and don't want to use dynamic frameworks
  use_frameworks!

  # Pods for ShadowsocksX-NG
  pod 'Alamofire', '~> 5.9'
  pod 'GCDWebServer', '~> 3.5'
  pod 'MASShortcut', '~> 2.4'

end

target 'proxy_conf_helper' do
  pod 'BRLOptionParser'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '14.0'
      config.build_settings['ARCHS'] = 'arm64'
      config.build_settings.delete('VALID_ARCHS')
    end
  end
end
