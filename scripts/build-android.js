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

const version = getVersion();
const versionCode = getVersionCode(version);
const deployDir = 'deploy';
const apkName = path.join(deployDir, `belair-v${version}.apk`);
const dummyKeyPath = 'D:\\AndroidPlayStore\\Dummy\\key.properties';
const targetKeyPath = path.join('android', 'key.properties');
const sourceAndroidIcon = path.join('belair Icon', 'BelairIcon-1024.png');
const androidBuildRoot = path.join('build', 'app');

console.log(`Building Android APK v${version} (versionCode: ${versionCode})...`);

try {
    if (!fs.existsSync(deployDir)) {
        fs.mkdirSync(deployDir);
    }

    if (!fs.existsSync(sourceAndroidIcon)) {
        throw new Error(`Missing Android icon source: ${sourceAndroidIcon}`);
    }

    console.log('Regenerating Android launcher icons...');
    execSync('dart run flutter_launcher_icons', { stdio: 'inherit' });

    // Prevent stale Android packaging artifacts from reusing old launcher resources.
    if (fs.existsSync(androidBuildRoot)) {
        try {
            fs.rmSync(androidBuildRoot, { recursive: true, force: true });
        } catch (cleanupError) {
            console.warn(`Warning: Could not clean ${androidBuildRoot}: ${cleanupError.message}`);
        }
    }

    // Ensure key.properties is in place for signing
    if (fs.existsSync(dummyKeyPath)) {
        console.log(`Copying and fixing signing properties from ${dummyKeyPath}...`);
        let content = fs.readFileSync(dummyKeyPath, 'utf8');
        // Fix backslashes for Java/Properties format if they are single
        content = content.replace(/storeFile=(.*)/, (match, p1) => {
            return `storeFile=${p1.replace(/\\/g, '\\\\')}`;
        });
        fs.writeFileSync(targetKeyPath, content);
    } else {
        console.warn(`Warning: Dummy key not found at ${dummyKeyPath}. Build might not be signed.`);
    }

    const buildCommand = `flutter build apk --release --build-name=${version} --build-number=${versionCode}`;
    execSync(buildCommand, { stdio: 'inherit' });
    
    const sourceApk = path.join('build', 'app', 'outputs', 'flutter-apk', 'app-release.apk');
    if (fs.existsSync(sourceApk)) {
        console.log(`Naming APK to ${apkName}...`);
        fs.copyFileSync(sourceApk, apkName);
        console.log(`Build complete: ${apkName}`);
    } else {
        console.error('Could not find output APK.');
    }

} catch (error) {
    console.error('Build failed:', error);
    process.exit(1);
} finally {
    // Cleanup key.properties if we copied it (optional, but safer to not leave it if it was temporary)
    // Actually, usually it's fine to leave it in the android folder for developers.
}
