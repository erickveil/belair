const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const env = {
    ...process.env,
    // Prefer Homebrew binaries on Apple Silicon (for CocoaPods compatibility).
    PATH: ['/opt/homebrew/bin', process.env.PATH || ''].filter(Boolean).join(':'),
};

function run(command) {
    execSync(command, { stdio: 'inherit', env });
}

function getVersion() {
    const pubspec = fs.readFileSync('pubspec.yaml', 'utf8');
    const versionMatch = pubspec.match(/^version:\s*([\d.]+)/m);
    return versionMatch ? versionMatch[1] : '0.0.1';
}

function safeRemove(filePath) {
    if (fs.existsSync(filePath)) {
        fs.rmSync(filePath, { recursive: true, force: true });
    }
}

function cleanDeployArtifacts(dirPath, matcher) {
    if (!fs.existsSync(dirPath)) {
        return;
    }

    for (const name of fs.readdirSync(dirPath)) {
        if (matcher.test(name)) {
            safeRemove(path.join(dirPath, name));
        }
    }
}

function ensureDir(dirPath) {
    if (!fs.existsSync(dirPath)) {
        fs.mkdirSync(dirPath, { recursive: true });
    }
}

const projectRoot = path.resolve(__dirname, '..');
process.chdir(projectRoot);

const version = getVersion();
const deployDir = 'deploy';
const appName = 'belair.app';
const macBuildRoot = path.join('build', 'macos');
const sourceAppBundle = path.join(macBuildRoot, 'Build', 'Products', 'Release', appName);
const stagedAppBundle = path.join(deployDir, `belair-v${version}.app`);
const zipName = path.join(deployDir, `belair-v${version}-macos-local.zip`);

console.log(`Building macOS local release v${version}...`);

try {
    ensureDir(deployDir);

    // Remove old local macOS deployment outputs before building.
    cleanDeployArtifacts(deployDir, /^belair-v.*-macos-local\.zip$/i);
    cleanDeployArtifacts(deployDir, /^belair-v.*\.app$/i);

    // Rebuild launcher icons to keep macOS app icon in sync with source artwork.
    run('dart run flutter_launcher_icons');

    // Validate CocoaPods from the preferred PATH before invoking Flutter build.
    run('pod --version');

    // Avoid stale artifacts from previous macOS builds.
    safeRemove(macBuildRoot);

    run('flutter build macos --release');

    if (!fs.existsSync(sourceAppBundle)) {
        throw new Error(`Missing built app bundle: ${sourceAppBundle}`);
    }

    fs.cpSync(sourceAppBundle, stagedAppBundle, { recursive: true });

    // Preserve resource forks and keep the parent .app bundle in the archive.
    const zipCommand = `ditto -c -k --sequesterRsrc --keepParent "${stagedAppBundle}" "${zipName}"`;
    run(zipCommand);

    console.log(`Staged app bundle: ${stagedAppBundle}`);
    console.log(`Build complete: ${zipName}`);
} catch (error) {
    console.error('Build failed:', error);
    process.exit(1);
}
