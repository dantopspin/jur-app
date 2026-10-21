#!/usr/bin/env python3
"""Writes Jur.xcodeproj without XcodeGen, using Xcode 16+ folder-synced groups
(every file under Jur/ is picked up automatically). Also writes Info.plist and the
entitlements from project.yml's values. Run from ios/: python3 scripts/make_xcodeproj.py"""
import hashlib, os, plistlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def oid(name):  # stable 24-hex ids
    return hashlib.md5(name.encode()).hexdigest()[:24].upper()

I = {k: oid(k) for k in [
    'project', 'main', 'products', 'app', 'jurgroup', 'config', 'secrets', 'exceptions',
    'target', 'sources', 'frameworks', 'resources',
    'pcl', 'pdebug', 'prelease', 'tcl', 'tdebug', 'trelease',
    'pkg_supabase', 'pkg_rc', 'dep_supabase', 'dep_rc', 'bf_supabase', 'bf_rc',
]}

common_project = {
    'ALWAYS_SEARCH_USER_PATHS': 'NO', 'ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS': 'YES',
    'CLANG_ANALYZER_NONNULL': 'YES', 'CLANG_CXX_LANGUAGE_STANDARD': '"gnu++20"', 'CLANG_ENABLE_MODULES': 'YES',
    'CLANG_ENABLE_OBJC_ARC': 'YES', 'COPY_PHASE_STRIP': 'NO', 'ENABLE_STRICT_OBJC_MSGSEND': 'YES',
    'ENABLE_USER_SCRIPT_SANDBOXING': 'YES', 'GCC_C_LANGUAGE_STANDARD': 'gnu17', 'GCC_NO_COMMON_BLOCKS': 'YES',
    'IPHONEOS_DEPLOYMENT_TARGET': '17.0', 'LOCALIZATION_PREFERS_STRING_CATALOGS': 'YES',
    'MTL_FAST_MATH': 'YES', 'SDKROOT': 'iphoneos', 'SWIFT_VERSION': '5.0',
}
debug_project = dict(common_project, **{
    'DEBUG_INFORMATION_FORMAT': 'dwarf', 'ENABLE_TESTABILITY': 'YES', 'GCC_OPTIMIZATION_LEVEL': '0',
    'GCC_PREPROCESSOR_DEFINITIONS': '("DEBUG=1", "$(inherited)")', 'MTL_ENABLE_DEBUG_INFO': 'INCLUDE_SOURCE',
    'ONLY_ACTIVE_ARCH': 'YES', 'SWIFT_ACTIVE_COMPILATION_CONDITIONS': '"DEBUG $(inherited)"',
    'SWIFT_OPTIMIZATION_LEVEL': '"-Onone"',
})
release_project = dict(common_project, **{
    'DEBUG_INFORMATION_FORMAT': '"dwarf-with-dsym"', 'ENABLE_NS_ASSERTIONS': 'NO', 'MTL_ENABLE_DEBUG_INFO': 'NO',
    'SWIFT_COMPILATION_MODE': 'wholemodule', 'VALIDATE_PRODUCT': 'YES',
})
target_settings = {
    'ASSETCATALOG_COMPILER_APPICON_NAME': 'AppIcon', 'ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME': 'AccentColor',
    'CODE_SIGN_ENTITLEMENTS': 'Jur/Jur.entitlements', 'CODE_SIGN_STYLE': 'Automatic',
    'CURRENT_PROJECT_VERSION': '1', 'DEVELOPMENT_TEAM': '"$(JUR_TEAM_ID)"', 'ENABLE_PREVIEWS': 'YES',
    'GENERATE_INFOPLIST_FILE': 'NO', 'INFOPLIST_FILE': 'Jur/Info.plist',
    'LD_RUNPATH_SEARCH_PATHS': '("$(inherited)", "@executable_path/Frameworks")',
    'MARKETING_VERSION': '2.0.0', 'PRODUCT_BUNDLE_IDENTIFIER': 'kz.jur.app', 'PRODUCT_NAME': '"$(TARGET_NAME)"',
    'SWIFT_EMIT_LOC_STRINGS': 'YES', 'TARGETED_DEVICE_FAMILY': '1',
}

def settings(d):
    return ''.join(f'\t\t\t\t{k} = {v};\n' for k, v in sorted(d.items()))

def config(id_, name, d, base=None):
    b = f'\t\t\tbaseConfigurationReference = {I["secrets"]} /* Secrets.xcconfig */;\n' if base else ''
    return (f'\t\t{id_} /* {name} */ = {{\n\t\t\tisa = XCBuildConfiguration;\n{b}'
            f'\t\t\tbuildSettings = {{\n{settings(d)}\t\t\t}};\n\t\t\tname = {name};\n\t\t}};\n')

pbx = f'''// !$*UTF8*$!
{{
	archiveVersion = 1;
	classes = {{
	}};
	objectVersion = 77;
	objects = {{

/* Begin PBXBuildFile section */
		{I["bf_supabase"]} /* Supabase in Frameworks */ = {{isa = PBXBuildFile; productRef = {I["dep_supabase"]} /* Supabase */; }};
		{I["bf_rc"]} /* RevenueCat in Frameworks */ = {{isa = PBXBuildFile; productRef = {I["dep_rc"]} /* RevenueCat */; }};
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
		{I["app"]} /* Jur.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Jur.app; sourceTree = BUILT_PRODUCTS_DIR; }};
		{I["secrets"]} /* Secrets.xcconfig */ = {{isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Secrets.xcconfig; sourceTree = "<group>"; }};
/* End PBXFileReference section */

/* Begin PBXFileSystemSynchronizedBuildFileExceptionSet section */
		{I["exceptions"]} /* Exceptions for "Jur" folder in "Jur" target */ = {{
			isa = PBXFileSystemSynchronizedBuildFileExceptionSet;
			membershipExceptions = (
				Info.plist,
				Jur.entitlements,
				Resources/Fonts/README.md,
			);
			target = {I["target"]} /* Jur */;
		}};
/* End PBXFileSystemSynchronizedBuildFileExceptionSet section */

/* Begin PBXFileSystemSynchronizedRootGroup section */
		{I["jurgroup"]} /* Jur */ = {{
			isa = PBXFileSystemSynchronizedRootGroup;
			exceptions = (
				{I["exceptions"]} /* Exceptions for "Jur" folder in "Jur" target */,
			);
			path = Jur;
			sourceTree = "<group>";
		}};
/* End PBXFileSystemSynchronizedRootGroup section */

/* Begin PBXFrameworksBuildPhase section */
		{I["frameworks"]} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{I["bf_supabase"]} /* Supabase in Frameworks */,
				{I["bf_rc"]} /* RevenueCat in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		{I["main"]} = {{
			isa = PBXGroup;
			children = (
				{I["jurgroup"]} /* Jur */,
				{I["config"]} /* Config */,
				{I["products"]} /* Products */,
			);
			sourceTree = "<group>";
		}};
		{I["config"]} /* Config */ = {{
			isa = PBXGroup;
			children = (
				{I["secrets"]} /* Secrets.xcconfig */,
			);
			path = Config;
			sourceTree = "<group>";
		}};
		{I["products"]} /* Products */ = {{
			isa = PBXGroup;
			children = (
				{I["app"]} /* Jur.app */,
			);
			name = Products;
			sourceTree = "<group>";
		}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		{I["target"]} /* Jur */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {I["tcl"]} /* Build configuration list for PBXNativeTarget "Jur" */;
			buildPhases = (
				{I["sources"]} /* Sources */,
				{I["frameworks"]} /* Frameworks */,
				{I["resources"]} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			fileSystemSynchronizedGroups = (
				{I["jurgroup"]} /* Jur */,
			);
			name = Jur;
			packageProductDependencies = (
				{I["dep_supabase"]} /* Supabase */,
				{I["dep_rc"]} /* RevenueCat */,
			);
			productName = Jur;
			productReference = {I["app"]} /* Jur.app */;
			productType = "com.apple.product-type.application";
		}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		{I["project"]} /* Project object */ = {{
			isa = PBXProject;
			attributes = {{
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 1600;
				LastUpgradeCheck = 1600;
			}};
			buildConfigurationList = {I["pcl"]} /* Build configuration list for PBXProject "Jur" */;
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				ru,
				kk,
				Base,
			);
			mainGroup = {I["main"]};
			minimizedProjectReferenceProxies = 1;
			packageReferences = (
				{I["pkg_supabase"]} /* XCRemoteSwiftPackageReference "supabase-swift" */,
				{I["pkg_rc"]} /* XCRemoteSwiftPackageReference "purchases-ios-spm" */,
			);
			preferredProjectObjectVersion = 77;
			productRefGroup = {I["products"]} /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				{I["target"]} /* Jur */,
			);
		}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		{I["resources"]} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		{I["sources"]} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
{config(I["pdebug"], "Debug", debug_project, base=True)}{config(I["prelease"], "Release", release_project, base=True)}{config(I["tdebug"], "Debug", target_settings)}{config(I["trelease"], "Release", target_settings)}/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		{I["pcl"]} /* Build configuration list for PBXProject "Jur" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{I["pdebug"]} /* Debug */,
				{I["prelease"]} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{I["tcl"]} /* Build configuration list for PBXNativeTarget "Jur" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{I["tdebug"]} /* Debug */,
				{I["trelease"]} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
/* End XCConfigurationList section */

/* Begin XCRemoteSwiftPackageReference section */
		{I["pkg_supabase"]} /* XCRemoteSwiftPackageReference "supabase-swift" */ = {{
			isa = XCRemoteSwiftPackageReference;
			repositoryURL = "https://github.com/supabase/supabase-swift";
			requirement = {{
				kind = upToNextMajorVersion;
				minimumVersion = 2.20.0;
			}};
		}};
		{I["pkg_rc"]} /* XCRemoteSwiftPackageReference "purchases-ios-spm" */ = {{
			isa = XCRemoteSwiftPackageReference;
			repositoryURL = "https://github.com/RevenueCat/purchases-ios-spm";
			requirement = {{
				kind = upToNextMajorVersion;
				minimumVersion = 5.0.0;
			}};
		}};
/* End XCRemoteSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
		{I["dep_supabase"]} /* Supabase */ = {{
			isa = XCSwiftPackageProductDependency;
			package = {I["pkg_supabase"]} /* XCRemoteSwiftPackageReference "supabase-swift" */;
			productName = Supabase;
		}};
		{I["dep_rc"]} /* RevenueCat */ = {{
			isa = XCSwiftPackageProductDependency;
			package = {I["pkg_rc"]} /* XCRemoteSwiftPackageReference "purchases-ios-spm" */;
			productName = RevenueCat;
		}};
/* End XCSwiftPackageProductDependency section */
	}};
	rootObject = {I["project"]} /* Project object */;
}}
'''

os.makedirs(f'{ROOT}/Jur.xcodeproj/xcshareddata/xcschemes', exist_ok=True)
open(f'{ROOT}/Jur.xcodeproj/project.pbxproj', 'w').write(pbx)

scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1600" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{I["target"]}" BuildableName = "Jur.app" BlueprintName = "Jur" ReferencedContainer = "container:Jur.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{I["target"]}" BuildableName = "Jur.app" BlueprintName = "Jur" ReferencedContainer = "container:Jur.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
'''
open(f'{ROOT}/Jur.xcodeproj/xcshareddata/xcschemes/Jur.xcscheme', 'w').write(scheme)

info = {
    'CFBundleDevelopmentRegion': 'en', 'CFBundleDisplayName': 'JÜR', 'CFBundleExecutable': '$(EXECUTABLE_NAME)',
    'CFBundleIdentifier': '$(PRODUCT_BUNDLE_IDENTIFIER)', 'CFBundleInfoDictionaryVersion': '6.0',
    'CFBundleName': '$(PRODUCT_NAME)', 'CFBundlePackageType': '$(PRODUCT_BUNDLE_PACKAGE_TYPE)',
    'CFBundleShortVersionString': '$(MARKETING_VERSION)', 'CFBundleVersion': '$(CURRENT_PROJECT_VERSION)',
    'CFBundleLocalizations': ['en', 'ru', 'kk'], 'ITSAppUsesNonExemptEncryption': False, 'LSRequiresIPhoneOS': True,
    'UILaunchScreen': {'UIColorName': 'LaunchBlue', 'UIImageName': 'LaunchMark'},
    'UISupportedInterfaceOrientations': ['UIInterfaceOrientationPortrait'], 'UIRequiresFullScreen': True,
    'UIAppFonts': ['Unbounded-Bold.ttf', 'Unbounded-ExtraBold.ttf', 'Manrope-Regular.ttf', 'Manrope-Medium.ttf',
                   'Manrope-SemiBold.ttf', 'Manrope-Bold.ttf', 'Manrope-ExtraBold.ttf'],
    'NSCameraUsageDescription': 'JÜR uses the camera for your verification selfie and photos.',
    'NSPhotoLibraryUsageDescription': 'Choose photos for your profile and chats.',
    'NSMicrophoneUsageDescription': 'Record voice notes in chats.',
    'NSContactsUsageDescription': 'Hide your profile from people in your contacts. Only one-way codes leave your phone.',
    'JurSupabaseHost': '$(SUPABASE_HOST)', 'JurSupabaseAnonKey': '$(SUPABASE_ANON_KEY)',
    'JurRevenueCatKey': '$(REVENUECAT_IOS_KEY)', 'JurSiteHost': '$(SITE_HOST)',
    'JurSupportEmail': '$(SUPPORT_EMAIL)', 'JurEvents': '$(JUR_EVENTS)',
}
with open(f'{ROOT}/Jur/Info.plist', 'wb') as f: plistlib.dump(info, f)
ent = {
    'com.apple.developer.applesignin': ['Default'],
    'com.apple.developer.sensitivecontentanalysis.client': ['analysis'],
    'aps-environment': 'development',
    'com.apple.security.application-groups': ['group.kz.jur.app'],
}
with open(f'{ROOT}/Jur/Jur.entitlements', 'wb') as f: plistlib.dump(ent, f)
print('wrote Jur.xcodeproj, Jur/Info.plist, Jur/Jur.entitlements')
