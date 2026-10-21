#!/usr/bin/env python3
"""Generate the small native extension project from explicit, reviewed inputs."""
from pathlib import Path
import hashlib, json, plistlib
ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'WidgetExtension/AudifernWidgets.xcodeproj'
APP_INFO = plistlib.loads((ROOT / 'Resources/Info.plist').read_bytes())
def ident(name): return hashlib.sha256(('audifern-widget:' + name).encode()).hexdigest()[:24].upper()
def q(value): return json.dumps(str(value))
objects = []
def obj(name, kind, fields):
    key = ident(name)
    objects.append(f'{key} = {{isa = {kind}; {fields}}};')
    return key
refs, sources, resources = [], [], []
for folder in ['Sources/QuickAccessKit', 'Sources/QuickAccessUI', 'WidgetExtension/Sources']:
    for file in sorted((ROOT / folder).glob('*.swift')):
        relative = '../' + file.relative_to(ROOT).as_posix()
        ref = obj(relative, 'PBXFileReference', f'lastKnownFileType = sourcecode.swift; path = {q(relative)}; sourceTree = SOURCE_ROOT; ')
        refs.append(ref)
        sources.append(obj('build:' + relative, 'PBXBuildFile', f'fileRef = {ref}; '))
for name in ['HearingAid.png', 'BrandMark.png']:
    relative = '../Sources/Audifern/Resources/' + name
    ref = obj(relative, 'PBXFileReference', f'lastKnownFileType = image.png; path = {q(relative)}; sourceTree = SOURCE_ROOT; ')
    refs.append(ref); resources.append(obj('build:' + relative, 'PBXBuildFile', f'fileRef = {ref}; '))
locales = []
for language in ['en', 'pt-BR', 'es']:
    relative = f'../Sources/Audifern/Resources/{language}.lproj/Localizable.strings'
    locales.append(obj(relative, 'PBXFileReference', f'lastKnownFileType = text.plist.strings; name = {q(language)}; path = {q(relative)}; sourceTree = SOURCE_ROOT; '))
variant = obj('localizations', 'PBXVariantGroup', f'children = ({",".join(locales)}); name = Localizable.strings; sourceTree = "<group>"; ')
refs.append(variant); resources.append(obj('build:localizations', 'PBXBuildFile', f'fileRef = {variant}; '))
product = obj('product', 'PBXFileReference', 'explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = AudifernWidgets.appex; sourceTree = BUILT_PRODUCTS_DIR; ')
products = obj('products', 'PBXGroup', f'children = ({product}); name = Products; sourceTree = "<group>"; ')
group = obj('group', 'PBXGroup', f'children = ({",".join(refs + [products])}); sourceTree = "<group>"; ')
src = obj('sources', 'PBXSourcesBuildPhase', f'buildActionMask = 2147483647; files = ({",".join(sources)}); runOnlyForDeploymentPostprocessing = 0; ')
res = obj('resources', 'PBXResourcesBuildPhase', f'buildActionMask = 2147483647; files = ({",".join(resources)}); runOnlyForDeploymentPostprocessing = 0; ')
frameworks = obj('frameworks', 'PBXFrameworksBuildPhase', 'buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; ')
project_configs, target_configs = [], []
for config in ['Debug', 'Release']:
    project_configs.append(obj('project:' + config, 'XCBuildConfiguration', f'buildSettings = {{SDKROOT = macosx; MACOSX_DEPLOYMENT_TARGET = 14.0; SWIFT_VERSION = 6.0; CLANG_ENABLE_MODULES = YES; }}; name = {config}; '))
    settings = {
        'PRODUCT_NAME': 'AudifernWidgets', 'PRODUCT_BUNDLE_IDENTIFIER': 'org.audifern.app.widgets', 'ENABLE_DEBUG_DYLIB': 'NO',
        'INFOPLIST_FILE': 'Info.plist', 'GENERATE_INFOPLIST_FILE': 'NO', 'SKIP_INSTALL': 'YES',
        'APPLICATION_EXTENSION_API_ONLY': 'YES', 'ENABLE_APP_SANDBOX': 'YES',
        'SWIFT_VERSION': '6.0', 'SWIFT_ACTIVE_COMPILATION_CONDITIONS': '$(inherited) WIDGET_EXTENSION',
        'SWIFT_OPTIMIZATION_LEVEL': '-Onone' if config == 'Debug' else '-O',
        'MACOSX_DEPLOYMENT_TARGET': '14.0', 'SUPPORTED_PLATFORMS': 'macosx',
        'LD_RUNPATH_SEARCH_PATHS': '$(inherited) @executable_path/../Frameworks @executable_path/../../../../Frameworks',
        'MARKETING_VERSION': APP_INFO['CFBundleShortVersionString'], 'CURRENT_PROJECT_VERSION': APP_INFO['CFBundleVersion'], 'AUDIFERN_APP_GROUP_ID': '',
        'SWIFT_EMIT_LOC_STRINGS': 'NO', 'ENABLE_USER_SCRIPT_SANDBOXING': 'YES',
        'CODE_SIGNING_ALLOWED': 'NO', 'DEBUG_INFORMATION_FORMAT': 'dwarf',
    }
    target_configs.append(obj('target:' + config, 'XCBuildConfiguration', 'buildSettings = {' + ' '.join(f'{k} = {q(v)};' for k,v in settings.items()) + f'}}; name = {config}; '))
project_list = obj('project-config-list', 'XCConfigurationList', f'buildConfigurations = ({",".join(project_configs)}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; ')
target_list = obj('target-config-list', 'XCConfigurationList', f'buildConfigurations = ({",".join(target_configs)}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; ')
target = obj('target', 'PBXNativeTarget', f'buildConfigurationList = {target_list}; buildPhases = ({src},{frameworks},{res}); buildRules = (); dependencies = (); name = AudifernWidgets; productName = AudifernWidgets; productReference = {product}; productType = "com.apple.product-type.app-extension"; ')
project = obj('project', 'PBXProject', f'attributes = {{LastUpgradeCheck = 2700; }}; buildConfigurationList = {project_list}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, "pt-BR", es, Base); mainGroup = {group}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = ({target}); ')
PROJECT.mkdir(parents=True, exist_ok=True)
(PROJECT / 'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n' + '\n'.join(objects) + f'\n}}; rootObject = {project}; }}\n')
schemes = PROJECT / 'xcshareddata/xcschemes'; schemes.mkdir(parents=True, exist_ok=True)
(schemes / 'AudifernWidgets.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3"><BuildAction parallelizeBuildables="NO" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="AudifernWidgets.appex" BlueprintName="AudifernWidgets" ReferencedContainer="container:AudifernWidgets.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>
''')
print('Generated WidgetExtension/AudifernWidgets.xcodeproj')
