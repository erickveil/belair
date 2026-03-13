const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

function getVersion() {
    const pubspec = fs.readFileSync('pubspec.yaml', 'utf8');
    const versionMatch = pubspec.match(/^version:\s*([\d.]+)/m);
    return versionMatch ? versionMatch[1] : '0.0.1';
}

const version = getVersion();
const deployDir = 'deploy';
const zipName = path.join(deployDir, `belair-v${version}.zip`);
const exeName = path.join(deployDir, `belair-v${version}.exe`);
const buildDir = path.join('build', 'windows', 'x64', 'runner', 'Release');
const builtExe = path.join(buildDir, 'belair.exe');
const windowsBuildRoot = path.join('build', 'windows');
const sourceIcoIcon = path.join('belair Icon', 'BelairIcon.ico');
const runnerIcon = path.join('windows', 'runner', 'resources', 'app_icon.ico');

console.log(`Building Windows Release v${version}...`);

try {
    if (!fs.existsSync(deployDir)) {
        fs.mkdirSync(deployDir);
    }

    // Keep the runner icon in sync with the canonical design ICO.
    if (!fs.existsSync(sourceIcoIcon)) {
        throw new Error(`Missing source ICO icon: ${sourceIcoIcon}`);
    }
    fs.copyFileSync(sourceIcoIcon, runnerIcon);

    // Force a relink so the executable always embeds the latest icon.
    if (fs.existsSync(windowsBuildRoot)) {
        fs.rmSync(windowsBuildRoot, { recursive: true, force: true });
    }

    execSync('flutter build windows --release', { stdio: 'inherit' });

    if (!fs.existsSync(builtExe)) {
        throw new Error(`Missing built executable: ${builtExe}`);
    }

    // Copy to a versioned path so icon inspection can bypass shell path cache.
    fs.copyFileSync(builtExe, exeName);
    
    if (fs.existsSync(zipName)) {
        fs.unlinkSync(zipName);
    }

    console.log(`Zipping to ${zipName}...`);
    // Using PowerShell to zip for simplicity in a Windows environment
    const zipCommand = `powershell.exe -Command "Compress-Archive -Path '${buildDir}\\*' -DestinationPath '${zipName}'"`;
    execSync(zipCommand, { stdio: 'inherit' });
    
    console.log(`Copied EXE: ${exeName}`);
    console.log(`Build complete: ${zipName}`);
} catch (error) {
    console.error('Build failed:', error);
    process.exit(1);
}
