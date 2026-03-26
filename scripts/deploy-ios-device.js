const { execSync } = require('child_process');
const os = require('os');

const env = {
    ...process.env,
    // Prefer Homebrew binaries so Flutter picks a working CocoaPods.
    PATH: ['/opt/homebrew/bin', process.env.PATH || ''].filter(Boolean).join(':'),
};

function run(command, options = {}) {
    return execSync(command, {
        stdio: options.capture ? ['ignore', 'pipe', 'pipe'] : 'inherit',
        encoding: options.capture ? 'utf8' : undefined,
        env,
    });
}

function parseArgs(argv) {
    const args = {
        mode: 'debug',
        deviceHint: null,
    };

    for (let i = 0; i < argv.length; i += 1) {
        const token = argv[i];
        if (token === '--release') {
            args.mode = 'release';
        } else if (token === '--profile') {
            args.mode = 'profile';
        } else if (token === '--debug') {
            args.mode = 'debug';
        } else if (token === '--device' && argv[i + 1]) {
            args.deviceHint = argv[i + 1];
            i += 1;
        }
    }

    return args;
}

function getConnectedIosDevices() {
    const raw = run('flutter devices --machine', { capture: true });
    const devices = JSON.parse(raw);

    return devices.filter((device) => {
        const platform = String(device.targetPlatform || '').toLowerCase();
        const isIos = platform === 'ios';
        const isEmulator = Boolean(device.emulator);
        return isIos && !isEmulator;
    });
}

function chooseDevice(devices, deviceHint) {
    if (!devices.length) {
        throw new Error(
            'No connected physical iOS devices found. Connect and unlock your iPhone/iPad, trust this Mac, and enable Developer Mode.'
        );
    }

    if (!deviceHint) {
        return devices[0];
    }

    const hint = deviceHint.toLowerCase();
    const match = devices.find((d) => {
        const id = String(d.id || '').toLowerCase();
        const name = String(d.name || '').toLowerCase();
        return id === hint || name.includes(hint) || id.includes(hint);
    });

    if (!match) {
        const available = devices.map((d) => `${d.name} (${d.id})`).join(', ');
        throw new Error(`Device '${deviceHint}' not found. Available iOS devices: ${available}`);
    }

    return match;
}

function modeToFlag(mode) {
    if (mode === 'release') return '--release';
    if (mode === 'profile') return '--profile';
    return '--debug';
}

function main() {
    if (os.platform() !== 'darwin') {
        throw new Error('iOS deployment requires macOS.');
    }

    const { mode, deviceHint } = parseArgs(process.argv.slice(2));

    console.log('Checking toolchain...');
    run('pod --version');
    run('flutter pub get');

    const devices = getConnectedIosDevices();
    const device = chooseDevice(devices, deviceHint || process.env.IOS_DEVICE_ID || null);

    console.log(`Selected iOS device: ${device.name} (${device.id})`);
    console.log(`Building and deploying (${mode})...`);

    const flutterRunCommand = [
        'flutter run',
        `-d ${device.id}`,
        modeToFlag(mode),
        '--no-resident',
    ].join(' ');

    run(flutterRunCommand);
    console.log('Deploy complete.');
}

try {
    main();
} catch (error) {
    console.error('iOS deploy failed:', error.message || error);
    process.exit(1);
}
