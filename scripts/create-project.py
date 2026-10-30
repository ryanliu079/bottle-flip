#!/usr/bin/env python3
"""Generate the dependency-free Xcode project deterministically."""
import hashlib
from pathlib import Path

root = Path(__file__).resolve().parent.parent

def ident(key):
    return hashlib.sha1(key.encode()).hexdigest()[:24].upper()

def ref(key):
    return ident(key)

objects = []
def obj(key, value):
    objects.append(f'\t\t{ref(key)} = {{ {value} }};')

sources = sorted((root / 'BottleFlip/Core').glob('*.swift')) + sorted((root / 'BottleFlip/App').glob('*.swift')) + sorted((root / 'BottleFlip/App/Shaders').glob('*.metal'))
for path in sources:
    rel = str(path.relative_to(root))
    filetype = 'sourcecode.metal' if path.suffix == '.metal' else 'sourcecode.swift'
    obj(rel, f'isa = PBXFileReference; lastKnownFileType = {filetype}; path = "{rel}"; sourceTree = SOURCE_ROOT;')
    obj('build:' + rel, f'isa = PBXBuildFile; fileRef = {ref(rel)};')
for key, path, filetype in [
    ('assets', 'BottleFlip/Assets.xcassets', 'folder.assetcatalog'),
    ('sounds', 'BottleFlip/App/Sounds', 'folder'),
    ('music', 'BottleFlip/App/Music', 'folder'),
    ('scenery', 'BottleFlip/App/Scenery', 'folder'),
    ('plist', 'BottleFlip/Info.plist', 'text.plist.xml'),
    ('readme', 'README.md', 'net.daringfireball.markdown')
]:
    obj(key, f'isa = PBXFileReference; lastKnownFileType = {filetype}; path = "{path}"; sourceTree = SOURCE_ROOT;')
obj('build:assets', f'isa = PBXBuildFile; fileRef = {ref("assets")};')
obj('build:sounds', f'isa = PBXBuildFile; fileRef = {ref("sounds")};')
obj('build:music', f'isa = PBXBuildFile; fileRef = {ref("music")};')
obj('build:scenery', f'isa = PBXBuildFile; fileRef = {ref("scenery")};')
obj('product', 'isa = PBXFileReference; explicitFileType = wrapper.application; path = BottleFlip.app; sourceTree = BUILT_PRODUCTS_DIR;')
obj('coreGroup', 'isa = PBXGroup; name = Core; sourceTree = "<group>"; children = (' + ','.join(ref(str(p.relative_to(root))) for p in sources if p.parent.name == 'Core') + ');')
obj('appGroup', 'isa = PBXGroup; name = App; sourceTree = "<group>"; children = (' + ','.join(ref(str(p.relative_to(root))) for p in sources if p.parent.name != 'Core') + ');')
obj('products', f'isa = PBXGroup; name = Products; sourceTree = "<group>"; children = ({ref("product")});')
obj('mainGroup', f'isa = PBXGroup; sourceTree = "<group>"; children = ({ref("coreGroup")},{ref("appGroup")},{ref("assets")},{ref("sounds")},{ref("music")},{ref("scenery")},{ref("plist")},{ref("readme")},{ref("products")});')
obj('sources', 'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; runOnlyForDeploymentPostprocessing = 0; files = (' + ','.join(ref('build:' + str(p.relative_to(root))) for p in sources) + ');')
obj('resources', f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; runOnlyForDeploymentPostprocessing = 0; files = ({ref("build:assets")},{ref("build:sounds")},{ref("build:music")},{ref("build:scenery")});')
obj('frameworks', 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; runOnlyForDeploymentPostprocessing = 0; files = ();')
common = 'CLANG_ENABLE_MODULES = YES; IPHONEOS_DEPLOYMENT_TARGET = 17.0; SDKROOT = iphoneos; SWIFT_VERSION = 6.0;'
app = 'ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon; ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor; CODE_SIGN_STYLE = Automatic; CURRENT_PROJECT_VERSION = 2; GENERATE_INFOPLIST_FILE = NO; INFOPLIST_FILE = BottleFlip/Info.plist; MARKETING_VERSION = 0.1; PRODUCT_BUNDLE_IDENTIFIER = com.ryanliu.bottleflip.prototype; PRODUCT_NAME = "$(TARGET_NAME)"; SUPPORTED_PLATFORMS = "iphoneos iphonesimulator"; TARGETED_DEVICE_FAMILY = 1; SWIFT_EMIT_LOC_STRINGS = YES;'
for scope, settings in [('project', common), ('target', app)]:
    for name in ['Debug', 'Release']:
        debug = 'DEBUG_INFORMATION_FORMAT = dwarf; SWIFT_OPTIMIZATION_LEVEL = "-Onone"; SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;' if name == 'Debug' else 'DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym"; SWIFT_COMPILATION_MODE = wholemodule; SWIFT_OPTIMIZATION_LEVEL = "-O";'
        obj(scope + name, f'isa = XCBuildConfiguration; name = {name}; buildSettings = {{ {settings} {debug} }};')
    obj(scope + 'Configs', f'isa = XCConfigurationList; buildConfigurations = ({ref(scope + "Debug")},{ref(scope + "Release")}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
obj('target', f'isa = PBXNativeTarget; buildConfigurationList = {ref("targetConfigs")}; buildPhases = ({ref("sources")},{ref("frameworks")},{ref("resources")}); buildRules = (); dependencies = (); name = BottleFlip; productName = BottleFlip; productReference = {ref("product")}; productType = "com.apple.product-type.application";')
obj('project', f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 2700; TargetAttributes = {{ {ref("target")} = {{ CreatedOnToolsVersion = 27.0; ProvisioningStyle = Automatic; }}; }}; }}; buildConfigurationList = {ref("projectConfigs")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; knownRegions = (en,Base); mainGroup = {ref("mainGroup")}; productRefGroup = {ref("products")}; projectDirPath = ""; projectRoot = ""; targets = ({ref("target")});')
project = root / 'BottleFlip.xcodeproj'
project.mkdir(exist_ok=True)
(project / 'project.pbxproj').write_text('// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n' + '\n'.join(objects) + f'\n\t}};\n\trootObject = {ref("project")};\n}}\n')
schemes = project / 'xcshareddata/xcschemes'
schemes.mkdir(parents=True, exist_ok=True)
(schemes / 'BottleFlip.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ref('target')}" BuildableName="BottleFlip.app" BlueprintName="BottleFlip" ReferencedContainer="container:BottleFlip.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables/></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ref('target')}" BuildableName="BottleFlip.app" BlueprintName="BottleFlip" ReferencedContainer="container:BottleFlip.xcodeproj"/></BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ref('target')}" BuildableName="BottleFlip.app" BlueprintName="BottleFlip" ReferencedContainer="container:BottleFlip.xcodeproj"/></BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print(project)
