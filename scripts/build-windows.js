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
const buildDir = path.join('build', 'windows', 'x64', 'runner', 'Release');

console.log(`Building Windows Release v${version}...`);

try {
    if (!fs.existsSync(deployDir)) {
        fs.mkdirSync(deployDir);
    }

    execSync('flutter build windows --release', { stdio: 'inherit' });
    
    if (fs.existsSync(zipName)) {
        fs.unlinkSync(zipName);
    }

    console.log(`Zipping to ${zipName}...`);
    // Using PowerShell to zip for simplicity in a Windows environment
    const zipCommand = `powershell.exe -Command "Compress-Archive -Path '${buildDir}\\*' -DestinationPath '${zipName}'"`;
    execSync(zipCommand, { stdio: 'inherit' });
    
    console.log(`Build complete: ${zipName}`);
} catch (error) {
    console.error('Build failed:', error);
    process.exit(1);
}
