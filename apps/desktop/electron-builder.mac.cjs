module.exports = {
  appId: 'com.flechazoyq.commandv.mac',
  productName: 'CommandV',
  directories: {output: '../../release/macos'},
  files: ['dist/**', 'package.json', '!node_modules/koffi/**', '!node_modules/@koromix/**'],
  extraResources: [{from: 'resources/commandv-mac', to: 'commandv-mac'}],
  asarUnpack: ['node_modules/sharp/**', 'node_modules/@img/**'],
  artifactName: 'CommandV-${version}-macOS-${arch}.${ext}',
  mac: {
    target: ['zip'],
    category: 'public.app-category.utilities',
    minimumSystemVersion: '13.0',
    identity: process.env.CSC_LINK ? undefined : '-',
    hardenedRuntime: Boolean(process.env.CSC_LINK),
    notarize: Boolean(process.env.CSC_LINK && process.env.APPLE_API_KEY),
    binaries: ['Contents/Resources/commandv-mac'],
    extendInfo: {NSLocalNetworkUsageDescription: '通过局域网接收已配对手机发送的素材。', NSBonjourServices: ['_imagebridge._tcp']},
  },
};
