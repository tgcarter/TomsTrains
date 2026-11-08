"""Generate the dependency-free Xcode project using only the Python standard library."""
from pathlib import Path
import hashlib

ROOT = Path(__file__).resolve().parent.parent
objects = {}


def ident(key):
    return hashlib.sha1(key.encode()).hexdigest()[:24].upper()


def add(key, body):
    objects[ident(key)] = body
    return ident(key)


def array(items):
    return "(" + ", ".join(items) + ("," if items else "") + ")"


def file(path, kind):
    return add(path, f'isa = PBXFileReference; lastKnownFileType = {kind}; path = "{path}"; sourceTree = SOURCE_ROOT;')


shared = [file(str(p.relative_to(ROOT)), "sourcecode.swift") for p in sorted((ROOT / "Shared").rglob("*.swift"))]
groups = []
targets = []
products = []
for name, folder, product_type, extension, config in [
    ("TomsTrains", "TomsTrains", "application", "app", "App"),
    ("TomsTrainsTests", "TomsTrainsTests", "bundle.unit-test", "xctest", None),
]:
    sources = [file(str(p.relative_to(ROOT)), "sourcecode.swift") for p in sorted((ROOT / folder).rglob("*.swift"))]
    group = add(name + "group", f'isa = PBXGroup; name = "{name}"; children = {array(sources)}; sourceTree = "<group>";')
    groups.append(group)
    build_files = [add(name + source, f"isa = PBXBuildFile; fileRef = {source};") for source in sources + shared]
    source_phase = add(name + "sources", f"isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {array(build_files)}; runOnlyForDeploymentPostprocessing = 0;")
    phases = [source_phase]
    if name == "TomsTrains":
        assets = file("TomsTrains/Assets.xcassets", "folder.assetcatalog")
        asset_build = add("assetBuild", f"isa = PBXBuildFile; fileRef = {assets};")
        phases.append(add("resources", f"isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({asset_build},); runOnlyForDeploymentPostprocessing = 0;"))
    configs = []
    config_ref = file(f"Configuration/{config}.xcconfig", "text.xcconfig") if config else None
    for mode in ["Debug", "Release"]:
        settings = 'CODE_SIGN_STYLE = Automatic; SWIFT_VERSION = 6.0; IPHONEOS_DEPLOYMENT_TARGET = 26.0; TARGETED_DEVICE_FAMILY = 1; SDKROOT = iphoneos; MARKETING_VERSION = 0.1.0; CURRENT_PROJECT_VERSION = 1;'
        settings += ' LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks";'
        if mode == "Debug":
            settings += ' SWIFT_OPTIMIZATION_LEVEL = "-Onone"; SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG; ENABLE_TESTABILITY = YES; DEBUG_INFORMATION_FORMAT = dwarf;'
        else:
            settings += ' SWIFT_COMPILATION_MODE = wholemodule; DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";'
        if name == "TomsTrainsTests":
            settings += ' PRODUCT_BUNDLE_IDENTIFIER = uk.co.thomascarter.TomsTrainsTests; PRODUCT_NAME = "$(TARGET_NAME)"; GENERATE_INFOPLIST_FILE = YES;'
        configs.append(add(name + mode, f'isa = XCBuildConfiguration; {f"baseConfigurationReference = {config_ref};" if config_ref else ""} buildSettings = {{ {settings} }}; name = {mode};'))
    config_list = add(name + "configs", f"isa = XCConfigurationList; buildConfigurations = {array(configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")
    product = add(name + "product", f'isa = PBXFileReference; explicitFileType = {"wrapper.application" if extension == "app" else "wrapper.app-extension" if extension == "appex" else "wrapper.cfbundle"}; includeInIndex = 0; path = {name}.{extension}; sourceTree = BUILT_PRODUCTS_DIR;')
    products.append(product)
    dependencies = []
    targets.append(add(name + "target", f'isa = PBXNativeTarget; buildConfigurationList = {config_list}; buildPhases = {array(phases)}; buildRules = (); dependencies = {array(dependencies)}; name = {name}; productName = {name}; productReference = {product}; productType = "com.apple.product-type.{product_type}";'))

groups.append(add("sharedGroup", f'isa = PBXGroup; name = Shared; children = {array(shared)}; sourceTree = "<group>";'))
groups.append(add("configGroup", f'isa = PBXGroup; name = Configuration; children = {array([ident("Configuration/App.xcconfig"), ident("TomsTrains/Assets.xcassets")])}; sourceTree = "<group>";'))
product_group = add("products", f'isa = PBXGroup; name = Products; children = {array(products)}; sourceTree = "<group>";')
groups.append(product_group)
main_group = add("main", f'isa = PBXGroup; children = {array(groups)}; sourceTree = "<group>";')
project_configs = [add("project" + mode, f'isa = XCBuildConfiguration; buildSettings = {{ CLANG_ENABLE_MODULES = YES; COPY_PHASE_STRIP = NO; }}; name = {mode};') for mode in ["Debug", "Release"]]
project_config_list = add("projectConfigs", f'isa = XCConfigurationList; buildConfigurations = {array(project_configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
project = add("project", f'isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 2600; }}; buildConfigurationList = {project_config_list}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; knownRegions = (en, Base); mainGroup = {main_group}; productRefGroup = {product_group}; projectDirPath = ""; projectRoot = ""; targets = {array(targets)};')
text = "// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n"
text += "\n".join(f"{key} = {{ {body} }};" for key, body in objects.items())
text += f"\n}}; rootObject = {project}; }}\n"
(ROOT / "TomsTrains.xcodeproj/project.pbxproj").write_text(text)


def reference(name, extension):
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ident(name + "target")}" BuildableName="{name}.{extension}" BlueprintName="{name}" ReferencedContainer="container:TomsTrains.xcodeproj"/>'


scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
<BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference("TomsTrains", "app")}</BuildActionEntry>
</BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{reference("TomsTrainsTests", "xctest")}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference("TomsTrains", "app")}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference("TomsTrains", "app")}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/>
<ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
(ROOT / "TomsTrains.xcodeproj/xcshareddata/xcschemes/TomsTrains.xcscheme").write_text(scheme)
