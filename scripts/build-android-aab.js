const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

function getVersion() {
    const pubspec = fs.readFileSync('pubspec.yaml', 'utf8');
    const versionMatch = pubspec.match(/^version:\s*([\d.]+)/m);
    return versionMatch ? versionMatch[1] : '0.0.1';
}

function getVersionCode(version) {
    const parts = version.split('.');
    const major = parseInt(parts[0]) || 0;
    const minor = parseInt(parts[1]) || 0;
    const patch = parseInt(parts[2]) || 0;
    return major * 10000 + minor * 100 + patch;
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

const version = getVersion();
const versionCode = getVersionCode(version);
const deployDir = 'deploy';
const aabName = path.join(deployDir, `belair-v${version}.aab`);
const dummyKeyPath = 'D:\\AndroidPlayStore\\belair\\key.properties';
const targetKeyPath = path.join('android', 'key.properties');
const sourceAndroidIcon = path.join('belair Icon', 'BelairIcon-1024.png');
const androidBuildRoot = path.join('build', 'app');

console.log(`Building Android AAB v${version} (versionCode: ${versionCode})...`);

try {
    if (!fs.existsSync(deployDir)) {
        fs.mkdirSync(deployDir);
    }

    cleanDeployArtifacts(deployDir, /^belair-v.*\.aab$/i);

    if (!fs.existsSync(sourceAndroidIcon)) {
        throw new Error(`Missing Android icon source: ${sourceAndroidIcon}`);
    }

    console.log('Regenerating Android launcher icons...');
    execSync('dart run flutter_launcher_icons', { stdio: 'inherit' });

    if (fs.existsSync(androidBuildRoot)) {
        try {
            safeRemove(androidBuildRoot);
        } catch (cleanupError) {
            console.warn(`Warning: Could not clean ${androidBuildRoot}: ${cleanupError.message}`);
        }
    }

    // Kill lingering Java/Gradle processes that might hold lint cache locks.
    try { execSync('taskkill /f /im java.exe', { stdio: 'pipe' }); } catch (_) {}
    try { execSync('taskkill /f /im gradle.exe', { stdio: 'pipe' }); } catch (_) {}

    // Clean lint cache to avoid stale file locks.
    const lintCache = path.join('build', 'app', 'intermediates', 'lint-cache');
    if (fs.existsSync(lintCache)) {
        try {
            safeRemove(lintCache);
        } catch (cleanupError) {
            console.warn(`Warning: Could not clean lint cache: ${cleanupError.message}`);
        }
    }

    if (fs.existsSync(dummyKeyPath)) {
        console.log(`Copying and fixing signing properties from ${dummyKeyPath}...`);
        let content = fs.readFileSync(dummyKeyPath, 'utf8');
        content = content.replace(/storeFile=(.*)/, (match, p1) => {
            return `storeFile=${p1.replace(/\\/g, '\\\\')}`;
        });
        fs.writeFileSync(targetKeyPath, content);
    } else {
        console.warn(`Warning: Belair key not found at ${dummyKeyPath}. Build might not be signed.`);
    }

    const buildCommand = `flutter build appbundle --release --build-name=${version} --build-number=${versionCode}`;
    execSync(buildCommand, { stdio: 'inherit' });

    const sourceAab = path.join('build', 'app', 'outputs', 'bundle', 'release', 'app-release.aab');
    if (fs.existsSync(sourceAab)) {
        console.log(`Naming AAB to ${aabName}...`);
        fs.copyFileSync(sourceAab, aabName);
        console.log(`Build complete: ${aabName}`);
    } else {
        console.error('Could not find output AAB.');
    }

} catch (error) {
    console.error('Build failed:', error);
    process.exit(1);
}
