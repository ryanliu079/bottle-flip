#!/usr/bin/env python3
"""Build a standalone XCTest UI runner against the installed simulator game."""
from pathlib import Path
import hashlib

root = Path(__file__).resolve().parents[1]
project = root / 'build/NavigationChecks.xcodeproj'
project.mkdir(parents=True, exist_ok=True)
objects = []


def key(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()


def obj(name, body):
    objects.append(f'{key(name)} = {{ {body} }};')


source = root / 'Tests/NavigationUITests/NavigationTests.swift'
obj('source', f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{source}"; sourceTree = "<absolute>";')
obj('buildSource', f'isa = PBXBuildFile; fileRef = {key("source")};')
obj('product', 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = NavigationChecks.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
obj('products', f'isa = PBXGroup; name = Products; children = ({key("product")}); sourceTree = "<group>";')
obj('group', f'isa = PBXGroup; children = ({key("source")},{key("products")}); sourceTree = "<group>";')
obj('sources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({key("buildSource")}); runOnlyForDeploymentPostprocessing = 0;')
obj('frameworks', 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
settings = 'SDKROOT = iphonesimulator; IPHONEOS_DEPLOYMENT_TARGET = 17.0; SUPPORTED_PLATFORMS = iphonesimulator; SWIFT_VERSION = 6.0; GENERATE_INFOPLIST_FILE = YES; PRODUCT_BUNDLE_IDENTIFIER = com.ryanliu.bottleflip.navigation-checks; PRODUCT_NAME = "$(TARGET_NAME)"; TARGETED_DEVICE_FAMILY = 1; CODE_SIGNING_ALLOWED = NO;'
for scope in ['project', 'target']:
    obj(scope + 'Debug', f'isa = XCBuildConfiguration; name = Debug; buildSettings = {{ {settings} SWIFT_OPTIMIZATION_LEVEL = "-Onone"; }};')
    obj(scope + 'Configs', f'isa = XCConfigurationList; buildConfigurations = ({key(scope + "Debug")}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug;')
obj('target', f'isa = PBXNativeTarget; name = NavigationChecks; productName = NavigationChecks; productReference = {key("product")}; productType = "com.apple.product-type.bundle.ui-testing"; buildConfigurationList = {key("targetConfigs")}; buildPhases = ({key("sources")},{key("frameworks")}); buildRules = (); dependencies = ();')
obj('project', f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 2700; }}; buildConfigurationList = {key("projectConfigs")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; knownRegions = (en,Base); mainGroup = {key("group")}; productRefGroup = {key("products")}; projectDirPath = ""; projectRoot = ""; targets = ({key("target")});')
(project / 'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n' + '\n'.join(objects) + f'\n}}; rootObject = {key("project")}; }}\n')
schemes = project / 'xcshareddata/xcschemes'
schemes.mkdir(parents=True, exist_ok=True)
(schemes / 'NavigationChecks.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{key('target')}" BuildableName="NavigationChecks.xctest" BlueprintName="NavigationChecks" ReferencedContainer="container:NavigationChecks.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{key('target')}" BuildableName="NavigationChecks.xctest" BlueprintName="NavigationChecks" ReferencedContainer="container:NavigationChecks.xcodeproj"/></TestableReference></Testables></TestAction>
</Scheme>''')
print(project)
